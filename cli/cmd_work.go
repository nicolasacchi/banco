package main

import (
	"encoding/json"
	"flag"
	"io"
	"net/url"
	"os"
	"path"
	"path/filepath"
	"regexp"
	"sort"
	"strconv"
	"strings"
	"time"
)

// A work folder is the files of one item revision: item.json, generator.mjs,
// verify.mjs and assets/*. `banco work open` writes it with a .banco/work.json
// that remembers the item, the revision it is based on and the role.
const stateDir = ".banco"
const stateFile = "work.json"

var itemKeyRe = regexp.MustCompile(`^[a-z0-9][a-z0-9_-]{0,63}$`)
var assetRe = regexp.MustCompile(`^assets/[A-Za-z0-9._-]+$`)

type workState struct {
	Item       string `json:"item"`
	Base       int    `json:"base"`
	Role       string `json:"role"`
	RevisionID int    `json:"revision_id"`
}

func readState(dir string) (workState, bool) {
	raw, err := os.ReadFile(filepath.Join(dir, stateDir, stateFile))
	if err != nil {
		return workState{}, false
	}
	var s workState
	if json.Unmarshal(raw, &s) != nil {
		return workState{}, false
	}
	return s, true
}

func writeState(dir string, s workState) error {
	if err := os.MkdirAll(filepath.Join(dir, stateDir), 0o755); err != nil {
		return err
	}
	raw, _ := json.MarshalIndent(s, "", "  ")
	return os.WriteFile(filepath.Join(dir, stateDir, stateFile), append(raw, '\n'), 0o644)
}

// validFileName: a name the server accepts, as a clean relative path.
func validFileName(name string) bool {
	return name == "item.json" || name == "generator.mjs" || name == "verify.mjs" || (assetRe.MatchString(name) && path.Clean(name) == name)
}

// runWorkOpen writes the folder of the latest revision of an item
// (GET /api/v1/work/items/:item). --role verifier gets the item, the tests and
// instances with their expected answers, never generator.mjs.
func runWorkOpen(e *env, args []string) error {
	fs := flag.NewFlagSet("work open", flag.ContinueOnError)
	fs.SetOutput(io.Discard)
	role := fs.String("role", "author", "author or verifier")
	dir := fs.String("dir", "", "folder to write (default ./ITEM)")
	fs.Bool("json", false, "JSON output (the default)")
	pos, err := parseFlags(fs, args)
	if err != nil {
		return err
	}
	const next = "banco work open ITEM [--role verifier]"
	if len(pos) != 1 || !itemKeyRe.MatchString(pos[0]) {
		return newErr(ExitUsage, "E-USAGE", "item", "work open takes one item key (lowercase letters, digits, - and _)", next)
	}
	if *role != "author" && *role != "verifier" {
		return newErr(ExitUsage, "E-USAGE", "role", "role is author or verifier", next)
	}
	item := pos[0]
	target := *dir
	if target == "" {
		target = item
	}
	if err := checkEmptyOrWork(target); err != nil {
		return err
	}

	body, err := e.client().do("work open", "GET", "/api/v1/work/items/"+url.PathEscape(item)+"?role="+url.QueryEscape(*role))
	if err != nil {
		return err
	}
	var answer struct {
		RevisionID int               `json:"revision_id"`
		Seq        int               `json:"seq"`
		Status     string            `json:"status"`
		Files      map[string]string `json:"files"`
		Instances  json.RawMessage   `json:"instances"`
		Tests      json.RawMessage   `json:"tests"`
		Validation json.RawMessage   `json:"validation"`
	}
	if err := json.Unmarshal(body, &answer); err != nil {
		return newErr(ExitServer, "E-HTTP", "", "the server's answer is not JSON: "+err.Error(), "banco health")
	}
	names := make([]string, 0, len(answer.Files))
	for name, text := range answer.Files {
		if !validFileName(name) {
			return newErr(ExitServer, "E-HTTP", "files", "the server sent a file name that is not allowed: "+name, "banco schema")
		}
		if err := writeFile(filepath.Join(target, filepath.FromSlash(name)), []byte(text)); err != nil {
			return err
		}
		names = append(names, name)
	}
	if *role == "verifier" {
		if len(answer.Instances) > 0 {
			if err := writeFile(filepath.Join(target, "instances.json"), answer.Instances); err != nil {
				return err
			}
			names = append(names, "instances.json")
		}
		if len(answer.Tests) > 0 && string(answer.Tests) != "null" {
			if err := writeFile(filepath.Join(target, "tests.json"), answer.Tests); err != nil {
				return err
			}
			names = append(names, "tests.json")
		}
	}
	sort.Strings(names)
	if err := writeState(target, workState{Item: item, Base: answer.RevisionID, Role: *role, RevisionID: answer.RevisionID}); err != nil {
		return newErr(ExitUsage, "E-USAGE", "dir", err.Error(), next)
	}
	out := map[string]any{
		"item": item, "role": *role, "dir": target, "revision_id": answer.RevisionID, "seq": answer.Seq,
		"status": answer.Status, "files": names, "validation": answer.Validation,
		"next": "edit the files, then banco work submit " + target + " --dry-run",
	}
	return json.NewEncoder(e.stdout).Encode(out)
}

// checkEmptyOrWork refuses to open into a folder that holds something else.
func checkEmptyOrWork(dir string) error {
	entries, err := os.ReadDir(dir)
	if err != nil {
		return nil
	}
	if len(entries) == 0 {
		return nil
	}
	if _, ok := readState(dir); ok {
		return nil
	}
	return newErr(ExitUsage, "E-USAGE", "dir", dir+" is not empty and is not a banco work folder", "banco work open ITEM --dir OTHER")
}

func writeFile(name string, data []byte) error {
	if err := os.MkdirAll(filepath.Dir(name), 0o755); err != nil {
		return newErr(ExitUsage, "E-USAGE", "dir", err.Error(), "check the folder")
	}
	if err := os.WriteFile(name, data, 0o644); err != nil {
		return newErr(ExitUsage, "E-USAGE", "dir", err.Error(), "check the folder")
	}
	return nil
}

// readWorkFiles reads the files of a folder that go to the server. A verifier's
// folder sends verify.mjs only: the rest of it is read-only material.
func readWorkFiles(dir, role string) (map[string]string, error) {
	files := map[string]string{}
	names := []string{"item.json", "generator.mjs", "verify.mjs"}
	if role == "verifier" {
		names = []string{"verify.mjs"}
	}
	for _, name := range names {
		raw, err := os.ReadFile(filepath.Join(dir, name))
		if err == nil {
			files[name] = string(raw)
		}
	}
	if role != "verifier" {
		entries, _ := os.ReadDir(filepath.Join(dir, "assets"))
		for _, ent := range entries {
			name := "assets/" + ent.Name()
			if ent.IsDir() || !assetRe.MatchString(name) {
				continue
			}
			raw, err := os.ReadFile(filepath.Join(dir, "assets", ent.Name()))
			if err == nil {
				files[name] = string(raw)
			}
		}
	}
	return files, nil
}

// runWorkSubmit sends the folder as a new revision (POST /api/v1/work/submit).
// --dry-run validates in the request and writes nothing on the server: it exits 3
// with the codes when the item fails. Without it the server queues the validation
// and the answer carries the revision to watch with `banco work status REV --wait`.
func runWorkSubmit(e *env, args []string) error {
	fs := flag.NewFlagSet("work submit", flag.ContinueOnError)
	fs.SetOutput(io.Discard)
	itemFlag := fs.String("item", "", "item key (default: from the folder's state, or its name)")
	baseFlag := fs.Int("base", 0, "revision this one is based on (default: from the folder's state)")
	dry := fs.Bool("dry-run", false, "validate in the request and store nothing")
	fs.Bool("json", false, "JSON output (the default)")
	pos, err := parseFlags(fs, args)
	if err != nil {
		return err
	}
	const next = "banco work submit DIR --dry-run"
	if len(pos) != 1 {
		return newErr(ExitUsage, "E-USAGE", "dir", "work submit takes exactly one folder", next)
	}
	dir := pos[0]
	if st, err := os.Stat(dir); err != nil || !st.IsDir() {
		return newErr(ExitUsage, "E-USAGE", "dir", dir+" is not a folder", next)
	}
	state, hasState := readState(dir)
	item := *itemFlag
	if item == "" {
		item = state.Item
	}
	if item == "" {
		abs, _ := filepath.Abs(dir)
		item = filepath.Base(abs)
	}
	if !itemKeyRe.MatchString(item) {
		return newErr(ExitUsage, "E-USAGE", "item", "an item key is lowercase letters, digits, - and _ (use --item KEY)", next)
	}
	base := *baseFlag
	if base == 0 {
		base = state.Base
	}
	files, _ := readWorkFiles(dir, state.Role)
	if len(files) == 0 {
		return newErr(ExitUsage, "E-USAGE", "dir", "no item.json, generator.mjs or verify.mjs in "+dir, next)
	}
	payload := map[string]any{"item": item, "files": files}
	if base != 0 {
		payload["base"] = base
	} else {
		payload["base"] = nil
	}
	raw, err := json.Marshal(payload)
	if err != nil {
		return newErr(ExitUsage, "E-USAGE", "", err.Error(), next)
	}
	headers := map[string]string{}
	if *dry {
		headers["X-Banco-Dry-Run"] = "1"
	}
	out, err := e.client().doWith("work submit", "POST", "/api/v1/work/submit", raw, headers)
	if err != nil {
		return err
	}
	if !*dry {
		var answer struct {
			RevisionID int `json:"revision_id"`
		}
		if json.Unmarshal(out, &answer) == nil && answer.RevisionID != 0 {
			state.Item, state.Base, state.RevisionID = item, answer.RevisionID, answer.RevisionID
			if !hasState || state.Role == "" {
				state.Role = "author"
			}
			_ = writeState(dir, state)
		}
	}
	_, err = e.stdout.Write(append(out, '\n'))
	return err
}

// runWorkStatus prints the validation of a revision (GET /api/v1/work/revisions/:revision).
// With --wait it polls until the verdict is final: exit 0 for passed, 3 for failed
// (the codes are on stderr), 6 when the validation ended in error or the wait ran out.
func runWorkStatus(e *env, args []string) error {
	fs := flag.NewFlagSet("work status", flag.ContinueOnError)
	fs.SetOutput(io.Discard)
	wait := fs.Bool("wait", false, "wait for the final verdict")
	timeout := fs.Int("timeout", 300, "seconds to wait with --wait")
	fs.Bool("json", false, "JSON output (the default)")
	pos, err := parseFlags(fs, args)
	if err != nil {
		return err
	}
	const next = "banco work status REV --wait"
	if len(pos) != 1 {
		return newErr(ExitUsage, "E-USAGE", "revision", "work status takes one revision id", next)
	}
	if _, err := strconv.Atoi(pos[0]); err != nil {
		return newErr(ExitUsage, "E-USAGE", "revision", "a revision id is a number", next)
	}
	interval := 2 * time.Second
	if ms, err := strconv.Atoi(e.getenv("BANCO_POLL_MS")); err == nil && ms > 0 {
		interval = time.Duration(ms) * time.Millisecond
	}
	deadline := time.Now().Add(time.Duration(*timeout) * time.Second)
	for {
		body, err := e.client().do("work status", "GET", "/api/v1/work/revisions/"+url.PathEscape(pos[0]))
		if err != nil {
			return err
		}
		var st struct {
			Status   string            `json:"status"`
			Settled  bool              `json:"settled"`
			Codes    []string          `json:"codes"`
			Findings []json.RawMessage `json:"findings"`
		}
		if err := json.Unmarshal(body, &st); err != nil {
			return newErr(ExitServer, "E-HTTP", "", "the server's answer is not JSON: "+err.Error(), "banco health")
		}
		if !*wait || st.Settled {
			if _, err := e.stdout.Write(append(body, '\n')); err != nil {
				return err
			}
			if !*wait {
				return nil
			}
			switch st.Status {
			case "passed":
				return nil
			case "failed":
				ce := newErr(ExitValidation, "E-VALIDATION-FAILED", "revision", "validation failed: "+strings.Join(st.Codes, ", "), "fix the files and banco work submit DIR --dry-run")
				if len(st.Codes) > 0 {
					ce.Code = st.Codes[0]
				}
				if len(st.Codes) == 1 && st.Codes[0] == "E-VERIFY-MISSING" {
					ce.Next = "the files are clean: a verifier runs banco work open ITEM --role verifier and writes verify.mjs"
				}
				ce.Codes, ce.Findings = st.Codes, st.Findings
				return ce
			default:
				return newErr(ExitServer, "E-VALIDATION-ERROR", "revision", "the validation could not run (Chrome or the grader did not answer); submit again later", "banco health")
			}
		}
		if time.Now().After(deadline) {
			return newErr(ExitServer, "E-TIMEOUT", "revision", "the validation did not finish within "+strconv.Itoa(*timeout)+" s", next)
		}
		time.Sleep(interval)
	}
}
