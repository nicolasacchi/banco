package main

import (
	"encoding/json"
	"flag"
	"fmt"
	"io"
	"net/url"
	"os"
	"path/filepath"
	"regexp"
	"strconv"
	"time"
)

// The shots of an item revision as the student sees it on a phone (D-336): one WebP per stored instance at 390 px, drawn on demand in the server's
// Chrome. `banco item shots REV` reads the status and asks for the render when there is none; with --wait it polls until the render is done; with
// --dir it writes DIR/REV/instance-NN_390x844.webp. `review open` and `solve open` ask for the render too (requestItemShots) and print the command that
// fetches the pictures; they never wait for it.

// the viewport of a shot, part of a file name: 390x844-cream
var itemShotViewportRe = regexp.MustCompile(`^([0-9]{3,4})x([0-9]{3,4})-(cream|dark)$`)

// the default folder: the one of the figures of an opened item (review open, solve open), so one folder per revision holds both
const defaultItemShotsDir = "banco-figures"

// defaultItemShotsTimeout is the wait of `--wait` in seconds: a Chrome lane with a queue of validations takes longer than 5 minutes (D-402 waves).
const defaultItemShotsTimeout = 1200

type itemShotsList struct {
	Status    string            `json:"status"`
	RenderID  int               `json:"render_id"`
	Message   string            `json:"message"`
	Errors    json.RawMessage   `json:"errors"`
	Notes     json.RawMessage   `json:"notes"`
	Instances int               `json:"instances"`
	SeedNote  string            `json:"seed_note"`
	Next      string            `json:"next"`
	Shots     []itemShotsRecord `json:"shots"`
}

type itemShotsRecord struct {
	Instance   int             `json:"instance"`
	State      string          `json:"state"`
	Seed       string          `json:"seed"`
	ShownOrder json.RawMessage `json:"shown_order"`
	Viewport   string          `json:"viewport"`
	Width      int             `json:"width"`
	Height     int             `json:"height"`
	Available  bool            `json:"available"`
	Path       string          `json:"path"`
}

func (l itemShotsList) done() bool { return l.Status == "passed" || l.Status == "failed" }

// itemShotsPath is the endpoint of a revision's shots.
func itemShotsPath(rev string) string {
	return "/api/v1/item-revisions/" + url.PathEscape(rev) + "/shots"
}

func (e *env) itemShots(rev string) (itemShotsList, error) {
	body, err := e.client().do("item shots", "GET", itemShotsPath(rev))
	if err != nil {
		return itemShotsList{}, err
	}
	var list itemShotsList
	if err := json.Unmarshal(body, &list); err != nil {
		return list, newErr(ExitServer, "E-HTTP", "", "the server's answer is not JSON: "+err.Error(), "banco health")
	}
	return list, nil
}

// requestItemShots asks for the render (POST, once: the server enqueues one job and says so). It answers {enqueued, status, render_id, error?}; a token that
// cannot request (bot_read, teacher) or a revision that has nothing to draw is an error the caller reports, never fatal.
func requestItemShots(e *env, rev string, force bool) (map[string]any, error) {
	path := itemShotsPath(rev)
	if force {
		path += "?force=1"
	}
	body, err := e.client().doBody("item shots", "POST", path, nil)
	if err != nil {
		return nil, err
	}
	var out map[string]any
	if err := json.Unmarshal(body, &out); err != nil {
		return nil, newErr(ExitServer, "E-HTTP", "", "the server's answer is not JSON: "+err.Error(), "banco health")
	}
	return out, nil
}

func runItemShots(e *env, args []string) error {
	fs := flag.NewFlagSet("item shots", flag.ContinueOnError)
	fs.SetOutput(io.Discard)
	dir := fs.String("dir", "", "folder for the images: DIR/REV/instance-NN_390x844.webp (default "+defaultItemShotsDir+")")
	wait := fs.Bool("wait", false, "wait until the render is done (the Chrome lane runs one job at a time)")
	force := fs.Bool("force", false, "draw the revision again even if it has been drawn")
	timeout := fs.Int("timeout", defaultItemShotsTimeout, "seconds to wait with --wait (a busy Chrome lane can take many minutes)")
	fs.Bool("json", false, "JSON output (the default)")
	pos, err := parseFlags(fs, args)
	if err != nil {
		return err
	}
	const next = "banco item shots 12 --dir banco-figures --wait"
	if len(pos) != 1 || !idRe.MatchString(pos[0]) {
		return newErr(ExitUsage, "E-USAGE", "revision", "item shots takes one argument: an item revision id (a number)", next)
	}
	rev := pos[0]
	parent := *dir
	if parent == "" {
		parent = defaultItemShotsDir
	}
	fetch := "banco item shots " + rev + " --dir " + parent + " --wait"
	interval := 3 * time.Second
	if ms, err := strconv.Atoi(e.getenv("BANCO_POLL_MS")); err == nil && ms > 0 {
		interval = time.Duration(ms) * time.Millisecond
	}

	// the render that counts: the latest one, or the one this request enqueues (a verdict row after the request's own). The CLI always asks: the server
	// alone knows whether a verdict is outdated (drawn under another harness version) and enqueues at most one job.
	after := 0
	list, err := e.itemShots(rev)
	if err != nil {
		return err
	}
	requested := map[string]any{"requested": false}
	req, rerr := requestItemShots(e, rev, *force)
	switch {
	case rerr == nil:
		requested = map[string]any{"requested": true, "enqueued": req["enqueued"], "status": req["status"]}
		if id, ok := req["render_id"].(float64); ok && (*force || req["enqueued"] == true) {
			after = int(id)
		}
	case !*force && (list.done() || list.Status == "queued"):
		// this token cannot ask (bot_read, teacher): it reads the verdict there is, or waits for the pending render
		requested["error"] = rerr.Error()
	default:
		return rerr
	}
	if *wait {
		deadline := time.Now().Add(time.Duration(*timeout) * time.Second)
		for {
			if list, err = e.itemShots(rev); err != nil {
				return err
			}
			if list.done() && list.RenderID > after {
				break
			}
			if list.Status == "error" && list.RenderID > after {
				return newErr(ExitServer, "E-CHROME-UNAVAILABLE", "revision", "the render could not run (Chrome did not answer): "+list.Message, "retry later: "+fetch+" --force")
			}
			if time.Now().After(deadline) {
				return newErr(ExitServer, "E-TIMEOUT", "revision", "the render did not finish within "+strconv.Itoa(*timeout)+" s (the Chrome lane runs one job at a time and may be busy): run the command again to keep waiting, with a longer --timeout SECONDS (this run "+strconv.Itoa(*timeout)+", default "+strconv.Itoa(defaultItemShotsTimeout)+")", fetch+" --timeout "+strconv.Itoa(2**timeout))
			}
			time.Sleep(interval)
		}
	} else if !list.done() || list.RenderID <= after {
		status := any(list.Status)
		if st, ok := requested["status"]; ok {
			status = st
		}
		return e.printJSON(map[string]any{"revision": rev, "status": status, "request": requested, "next": "the render is not done: " + fetch})
	}

	target := filepath.Join(parent, rev)
	files, removed, err := saveItemShots(e, list, target, fetch)
	if err != nil {
		return err
	}
	out := map[string]any{
		"revision": rev, "dir": target, "status": list.Status, "instances": list.Instances, "errors": jsonOrEmpty(list.Errors), "notes": jsonOrEmpty(list.Notes),
		"files": files, "removed_by_purge": removed, "request": requested, "seed_note": list.SeedNote,
		"next": "look at every file, instance by instance (390 px is the phone); a letter or number on a choice, a matching row or a step is the position in shown_order",
	}
	if removed > 0 {
		out["next"] = "some images were removed by the purge: draw the revision again: banco item shots " + rev + " --dir " + parent + " --wait --force"
	}
	if root := gitRootAbove(target); root != "" {
		out["warning"] = "the folder " + target + " is inside the git work tree " + root + ": nothing of the work may be committed there; use --dir OUTSIDE/shots and delete it after"
	}
	return e.printJSON(out)
}

func jsonOrEmpty(raw json.RawMessage) json.RawMessage {
	if len(raw) == 0 {
		return json.RawMessage("[]")
	}
	return raw
}

func (e *env) printJSON(v any) error { return json.NewEncoder(e.stdout).Encode(v) }

// saveItemShots writes DIR/REV/instance-NN_WxH.webp (instance-NN-tr_WxH.webp for the picture with the Italian translation open) for each shot the server still holds, after clearing the instance files of an earlier fetch (a
// symlink is removed, never followed), and answers what was written and how many files the purge had removed.
func saveItemShots(e *env, list itemShotsList, target, next string) ([]map[string]any, int, error) {
	old, _ := filepath.Glob(filepath.Join(target, "instance-*.webp"))
	for _, f := range old {
		if err := os.Remove(f); err != nil {
			return nil, 0, newErr(ExitUsage, "E-USAGE", "dir", "cannot clear "+f+": "+err.Error(), next)
		}
	}
	files := []map[string]any{}
	written := map[string]bool{}
	removed := 0
	for _, s := range list.Shots {
		if !s.Available {
			removed++
			continue
		}
		m := itemShotViewportRe.FindStringSubmatch(s.Viewport)
		if m == nil || s.Instance < 1 {
			return nil, 0, newErr(ExitServer, "E-HTTP", "viewport", "the server named a shot "+strconv.Quote(s.Viewport)+" of instance "+strconv.Itoa(s.Instance)+" that is not WxH-theme", "banco health")
		}
		data, err := e.client().do("item shots", "GET", s.Path)
		if err != nil {
			return nil, 0, err
		}
		// the picture of an instance with the Italian translation open (state "tr", D-402) sits beside the one as drawn: instance-NN-tr_WxH.webp
		suffix := ""
		if s.State != "" {
			suffix = "-" + s.State
		}
		file := filepath.Join(target, fmt.Sprintf("instance-%02d%s_%sx%s.webp", s.Instance, suffix, m[1], m[2]))
		// two pictures never share a file: the later would overwrite the earlier one without a word
		if written[file] {
			return nil, 0, newErr(ExitServer, "E-HTTP", "shots", "the server listed two pictures for "+filepath.Base(file)+" (instance "+strconv.Itoa(s.Instance)+", state "+strconv.Quote(s.State)+")", "banco health")
		}
		written[file] = true
		if err := writeFile(file, data); err != nil {
			return nil, 0, err
		}
		entry := map[string]any{"instance": s.Instance, "file": file, "width": s.Width, "height": s.Height, "seed": s.Seed, "shown_order": jsonOrEmpty(s.ShownOrder)}
		if s.State != "" {
			entry["state"] = s.State
		}
		files = append(files, entry)
	}
	return files, removed, nil
}

// itemShotsHint is what review open and solve open add to their answer (D-336): the render is requested (best effort: a token that cannot request, a
// revision with nothing to draw and a busy server never fail the open) and the command that fetches the pictures is printed.
func itemShotsHint(e *env, rev, dir string) map[string]any {
	hint := map[string]any{"fetch": "banco item shots " + rev + " --dir " + dir + " --wait",
		"why": "the pictures of every instance as the student sees it on a 390 px phone: look at them before you answer"}
	req, err := requestItemShots(e, rev, false)
	if err != nil {
		hint["requested"] = false
		hint["note"] = err.Error()
		return hint
	}
	hint["requested"] = true
	hint["enqueued"] = req["enqueued"]
	hint["status"] = req["status"]
	return hint
}

// withItemShots adds the item_shots member to the answer of an open when the answer is a JSON object.
func withItemShots(body []byte, hint map[string]any) []byte {
	var doc map[string]json.RawMessage
	if json.Unmarshal(body, &doc) != nil || doc == nil {
		return body
	}
	raw, err := json.Marshal(hint)
	if err != nil {
		return body
	}
	doc["item_shots"] = raw
	out, err := json.Marshal(doc)
	if err != nil {
		return body
	}
	return out
}
