package main

import (
	"encoding/base64"
	"encoding/json"
	"flag"
	"fmt"
	"io"
	"io/fs"
	"net/url"
	"os"
	"path/filepath"
	"regexp"
	"sort"
	"strconv"
	"strings"
)

// Free pages, release 2 (D-289, SPEC B9): list a subject's pages, open one as a folder, submit a revision, read its state, its
// screenshots and its diff, review it. None of these commands decides anything: the teacher tries a page and approves the topic that
// embeds it in the browser (firm rule 2).

var pageKeyRe = regexp.MustCompile(`^[a-z_]+\.[a-z0-9]+(-[a-z0-9]+)*$`)

const cardFile = "CARD.md"

// textExt are the page files sent as text; every other file (images) travels as {"base64": ...}.
var textExt = map[string]bool{".mjs": true, ".json": true, ".css": true, ".svg": true}

func runPagesList(e *env, a []string) error {
	fs := flag.NewFlagSet("pages list", flag.ContinueOnError)
	fs.SetOutput(io.Discard)
	subject := fs.String("subject", "", "subject key, for example math")
	fs.Bool("json", false, "JSON output (the default)")
	pos, err := parseFlags(fs, a)
	if err != nil {
		return err
	}
	const next = "banco pages list --subject math"
	if !subjectRe.MatchString(*subject) || len(pos) != 0 {
		return newErr(ExitUsage, "E-USAGE", "subject", "give --subject KEY (a subject key such as math)", next)
	}
	return send(e, "pages list", "GET", "/api/v1/subjects/"+url.PathEscape(*subject)+"/pages", nil, false)
}

// page open KEY [--dir D]: the files of the latest revision, or the skeleton of a new page, and the card that embeds it.
func runPageOpen(e *env, args []string) error {
	fl := flag.NewFlagSet("page open", flag.ContinueOnError)
	fl.SetOutput(io.Discard)
	dir := fl.String("dir", "", "folder for the page (default $TMPDIR/banco-work/page-KEY)")
	fl.Bool("json", false, "JSON output (the default)")
	pos, err := parseFlags(fl, args)
	if err != nil {
		return err
	}
	const next = "banco page open math.balance-3d"
	if len(pos) != 1 || !pageKeyRe.MatchString(pos[0]) {
		return newErr(ExitUsage, "E-USAGE", "page", "page open takes one page key such as math.balance-3d", next)
	}
	key := pos[0]
	target := *dir
	if target == "" {
		target = filepath.Join(os.TempDir(), "banco-work", "page-"+key)
	}
	if entries, err := os.ReadDir(target); err == nil && len(entries) > 0 {
		for _, ent := range entries {
			if !pageFolderEntry(ent.Name()) {
				return newErr(ExitUsage, "E-USAGE", "dir", target+" holds "+ent.Name()+" and is not a page folder", "banco page open "+key+" --dir OTHER")
			}
		}
	}
	body, err := e.client().do("page open", "GET", "/api/v1/pages/"+url.PathEscape(key))
	if err != nil {
		return err
	}
	var answer struct {
		Page    string                     `json:"page"`
		Subject string                     `json:"subject"`
		Exists  bool                       `json:"exists"`
		Latest  json.RawMessage            `json:"latest"`
		Files   map[string]json.RawMessage `json:"files"`
		Card    json.RawMessage            `json:"card"`
		Brief   json.RawMessage            `json:"brief"`
		Libs    []string                   `json:"libs"`
	}
	if err := json.Unmarshal(body, &answer); err != nil {
		return newErr(ExitServer, "E-HTTP", "", "the server's answer is not JSON: "+err.Error(), "banco health")
	}
	names := make([]string, 0, len(answer.Files))
	for name := range answer.Files {
		names = append(names, name)
	}
	sort.Strings(names)
	for _, name := range names {
		data, err := decodePageFile(answer.Files[name])
		if err != nil {
			return newErr(ExitServer, "E-HTTP", "files", name+": "+err.Error(), "banco health")
		}
		if err := writeFile(filepath.Join(target, filepath.FromSlash(name)), data); err != nil {
			return err
		}
	}
	var latest struct {
		RevisionID int `json:"revision_id"`
	}
	_ = json.Unmarshal(answer.Latest, &latest)
	if latest.RevisionID != 0 {
		if err := writeFile(filepath.Join(target, baseFile), []byte(strconv.Itoa(latest.RevisionID)+"\n")); err != nil {
			return err
		}
	}
	if len(answer.Card) > 0 && string(answer.Card) != "null" {
		if err := writeFile(filepath.Join(target, cardFile), append(answer.Card, '\n')); err != nil {
			return err
		}
	}
	out := map[string]any{
		"page": answer.Page, "subject": answer.Subject, "exists": answer.Exists, "dir": target, "latest": answer.Latest, "card": answer.Card, "libs": answer.Libs,
		"next": "work from the card only (banco brief show page), edit " + target + ", then banco page submit " + target + " --dry-run",
	}
	if root := gitRootAbove(target); root != "" {
		out["warning"] = "the folder " + target + " is inside the git work tree " + root + ": nothing of the work may be committed there; use --dir OUTSIDE/page and delete this folder"
	}
	return json.NewEncoder(e.stdout).Encode(out)
}

func pageFolderEntry(name string) bool {
	return name == baseFile || name == cardFile || name == "page.json" || name == "style.css" || name == "assets" || strings.HasSuffix(name, ".mjs")
}

// decodePageFile: a JSON string is a text file, {"base64": "..."} an image.
func decodePageFile(raw json.RawMessage) ([]byte, error) {
	var text string
	if json.Unmarshal(raw, &text) == nil {
		return []byte(text), nil
	}
	var bin struct {
		Base64 string `json:"base64"`
	}
	if err := json.Unmarshal(raw, &bin); err != nil || bin.Base64 == "" {
		return nil, fmt.Errorf("a file is a string or {\"base64\": ...}")
	}
	return base64.StdEncoding.DecodeString(bin.Base64)
}

// page submit DIR [--base N] [--dry-run]
func runPageSubmit(e *env, args []string) error {
	fl := flag.NewFlagSet("page submit", flag.ContinueOnError)
	fl.SetOutput(io.Discard)
	baseFlag := fl.String("base", "", "the revision the folder is based on (default: DIR/.base)")
	dry := fl.Bool("dry-run", false, "validate and store nothing")
	fl.Bool("json", false, "JSON output (the default)")
	pos, err := parseFlags(fl, args)
	if err != nil {
		return err
	}
	const next = "banco page submit DIR --dry-run"
	if len(pos) != 1 {
		return newErr(ExitUsage, "E-USAGE", "dir", "page submit takes exactly one folder with page.json", next)
	}
	dir := pos[0]
	raw, err := os.ReadFile(filepath.Join(dir, "page.json"))
	if err != nil {
		return newErr(ExitUsage, "E-USAGE", "dir", "cannot read "+filepath.Join(dir, "page.json")+": "+err.Error(), next)
	}
	var manifest struct {
		Key string `json:"key"`
	}
	if err := json.Unmarshal(raw, &manifest); err != nil || !pageKeyRe.MatchString(manifest.Key) {
		return newErr(ExitValidation, "E-FILES", "key", "page.json has no valid \"key\" (a page key such as math.balance-3d)", next)
	}
	files := map[string]any{}
	err = filepath.WalkDir(dir, func(path string, d fs.DirEntry, err error) error {
		if err != nil || d.IsDir() {
			return err
		}
		rel, err := filepath.Rel(dir, path)
		if err != nil {
			return err
		}
		rel = filepath.ToSlash(rel)
		if rel == baseFile || rel == cardFile {
			return nil
		}
		data, err := os.ReadFile(path)
		if err != nil {
			return err
		}
		if textExt[strings.ToLower(filepath.Ext(rel))] {
			files[rel] = string(data)
		} else {
			files[rel] = map[string]string{"base64": base64.StdEncoding.EncodeToString(data)}
		}
		return nil
	})
	if err != nil {
		return newErr(ExitUsage, "E-USAGE", "dir", "cannot read the folder: "+err.Error(), next)
	}
	var base any
	baseText := strings.TrimSpace(*baseFlag)
	if baseText == "" {
		if saved, err := os.ReadFile(filepath.Join(dir, baseFile)); err == nil {
			baseText = strings.TrimSpace(string(saved))
		}
	}
	if baseText != "" {
		n, err := strconv.Atoi(baseText)
		if err != nil {
			return newErr(ExitUsage, "E-USAGE", "base", "the base is a revision id (a number)", next)
		}
		base = n
	}
	payload, _ := json.Marshal(map[string]any{"page": manifest.Key, "base": base, "files": files})
	headers := map[string]string{}
	if *dry {
		headers["X-Banco-Dry-Run"] = "1"
	}
	out, err := e.client().doWith("page submit", "POST", "/api/v1/pages/submit", payload, headers)
	if err != nil {
		return err
	}
	if !*dry {
		var answer struct {
			RevisionID int `json:"revision_id"`
		}
		if json.Unmarshal(out, &answer) == nil && answer.RevisionID != 0 {
			_ = os.WriteFile(filepath.Join(dir, baseFile), []byte(strconv.Itoa(answer.RevisionID)+"\n"), 0o644)
		}
	}
	_, err = e.stdout.Write(append(out, '\n'))
	return err
}

func runPageStatus(e *env, args []string) error {
	return runKeyed(e, keyedCommand{"page status", "/api/v1/page-revisions/", "", "", idRe, "revision", "a revision id (a number)", "banco page status REV"}, args)
}
func runPageDiff(e *env, args []string) error {
	return runKeyed(e, keyedCommand{"page diff", "/api/v1/page-revisions/", "/diff", "", idRe, "revision", "a revision id (a number)", "banco page diff REV"}, args)
}
func runPageReviewOpen(e *env, args []string) error {
	return runKeyed(e, keyedCommand{"page-review open", "/api/v1/page-revisions/", "/review", "", idRe, "revision", "a revision id (a number)", "banco page-review open REV"}, args)
}
func runPageReviewSubmit(e *env, args []string) error {
	return runKeyed(e, keyedCommand{"page-review submit", "/api/v1/page-revisions/", "/review", "review", idRe, "revision", "a revision id (a number)", "banco page-review submit REV --file review.json"}, args)
}

// page shots REV --dir D: the screenshots of the validation, one WebP per seed and state, so that a multimodal model looks at each.
// Files are named KIND_seedN_WIDTH[_actionN].webp.
func runPageShots(e *env, args []string) error {
	fl := flag.NewFlagSet("page shots", flag.ContinueOnError)
	fl.SetOutput(io.Discard)
	dir := fl.String("dir", "", "folder for the images (default $TMPDIR/banco-work/page-shots-REV)")
	fl.Bool("json", false, "JSON output (the default)")
	pos, err := parseFlags(fl, args)
	if err != nil {
		return err
	}
	const next = "banco page shots 12 --dir /tmp/shots"
	if len(pos) != 1 || !idRe.MatchString(pos[0]) {
		return newErr(ExitUsage, "E-USAGE", "revision", "page shots takes one argument: a revision id (a number)", next)
	}
	rev := pos[0]
	target := *dir
	if target == "" {
		target = filepath.Join(os.TempDir(), "banco-work", "page-shots-"+rev)
	}
	body, err := e.client().do("page shots", "GET", "/api/v1/page-revisions/"+rev+"/shots")
	if err != nil {
		return err
	}
	var list struct {
		Status string          `json:"status"`
		Errors json.RawMessage `json:"errors"`
		Shots  []struct {
			Kind      string `json:"kind"`
			SeedIndex int    `json:"seed_index"`
			Width     int    `json:"width"`
			Action    int    `json:"action"`
			Available bool   `json:"available"`
			Path      string `json:"path"`
		} `json:"shots"`
	}
	if err := json.Unmarshal(body, &list); err != nil {
		return newErr(ExitServer, "E-HTTP", "", "the server's answer is not JSON: "+err.Error(), "banco health")
	}
	files := []map[string]any{}
	missing := 0
	for _, s := range list.Shots {
		if !s.Available {
			missing++
			continue
		}
		data, err := e.client().do("page shots", "GET", s.Path)
		if err != nil {
			return err
		}
		name := fmt.Sprintf("%s_seed%d_%d", s.Kind, s.SeedIndex+1, s.Width)
		if s.Action > 0 {
			name += fmt.Sprintf("_action%d", s.Action)
		}
		name += ".webp"
		if err := writeFile(filepath.Join(target, name), data); err != nil {
			return err
		}
		files = append(files, map[string]any{"kind": s.Kind, "seed": s.SeedIndex + 1, "width": s.Width, "file": filepath.Join(target, name)})
	}
	out := map[string]any{
		"revision": rev, "dir": target, "status": list.Status, "errors": list.Errors, "files": files, "removed_by_purge": missing,
		"next": "look at every file (the 390 px ones are the phone) and write the review: banco page-review open " + rev,
	}
	if root := gitRootAbove(target); root != "" {
		out["warning"] = "the folder " + target + " is inside the git work tree " + root + ": nothing of the work may be committed there; use --dir OUTSIDE/shots and delete it after"
	}
	return json.NewEncoder(e.stdout).Encode(out)
}
