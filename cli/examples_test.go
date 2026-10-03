package main

import (
	"bytes"
	"encoding/json"
	"os"
	"path/filepath"
	"regexp"
	"strings"
	"testing"

	"banco/contract"
)

// An example is one request and its answer, written by the Rails integration tests
// (contract/examples/<command>.<variant>.json, UPDATE_CONTRACT=1). The unknown-field
// check makes a new member of the file a failure here until this struct knows it.
type example struct {
	Command string `json:"command"`
	Request struct {
		Method string          `json:"method"`
		Path   string          `json:"path"`
		Query  string          `json:"query"`
		DryRun bool            `json:"dry_run"`
		Body   json.RawMessage `json:"body"`
	} `json:"request"`
	Response struct {
		Status int             `json:"status"`
		Body   json.RawMessage `json:"body"`
	} `json:"response"`
}

func TestExamples(t *testing.T) {
	files, err := filepath.Glob("../contract/examples/*.json")
	if err != nil {
		t.Fatal(err)
	}
	if len(files) == 0 {
		t.Fatal("contract/examples is empty: run the Rails tests with UPDATE_CONTRACT=1")
	}
	c, err := contract.Parse()
	if err != nil {
		t.Fatal(err)
	}
	byName := map[string]contract.Command{}
	for _, cmd := range c.Commands {
		byName[cmd.Name] = cmd
	}
	seen := map[string]bool{}
	for _, file := range files {
		raw, err := os.ReadFile(file)
		if err != nil {
			t.Fatal(err)
		}
		dec := json.NewDecoder(bytes.NewReader(raw))
		dec.DisallowUnknownFields()
		var ex example
		if err := dec.Decode(&ex); err != nil {
			t.Errorf("%s: %v", file, err)
			continue
		}
		cmd, ok := byName[ex.Command]
		if !ok {
			t.Errorf("%s: %q is not a command of the contract", file, ex.Command)
			continue
		}
		seen[ex.Command] = true
		if cmd.Local || cmd.Method == nil || cmd.Path == nil {
			t.Errorf("%s: %q is local and has no request", file, ex.Command)
			continue
		}
		if ex.Request.Method != *cmd.Method {
			t.Errorf("%s: method %s, the contract says %s", file, ex.Request.Method, *cmd.Method)
		}
		if !pathMatches(*cmd.Path, ex.Request.Path) {
			t.Errorf("%s: path %s does not fit %s", file, ex.Request.Path, *cmd.Path)
		}
		if ex.Request.DryRun && !hasFlag(cmd, "--dry-run") {
			t.Errorf("%s: a dry run of a command that has no --dry-run", file)
		}
		if ex.Response.Status < 200 || ex.Response.Status > 599 {
			t.Errorf("%s: status %d", file, ex.Response.Status)
		}
		if !json.Valid(ex.Response.Body) {
			t.Errorf("%s: the response body is not JSON", file)
		}
		// An error answer carries a code the contract lists for the command.
		if ex.Response.Status >= 400 {
			var e struct {
				Code string `json:"code"`
			}
			_ = json.Unmarshal(ex.Response.Body, &e)
			if !contains(cmd.ErrorCodes, e.Code) {
				t.Errorf("%s: error code %q is not in the contract's error_codes for %q", file, e.Code, ex.Command)
			}
		}
	}
	// The commands of the content cycle each have an example (the big ones, schema and
	// brief show, and the local one are not shown here).
	for _, name := range []string{"status", "syllabus lines", "work open", "work submit", "work status", "skill-graph open", "skill-graph submit", "skill-graph coverage", "blueprint open", "blueprint submit"} {
		if !seen[name] {
			t.Errorf("no example for %q", name)
		}
	}
}

func pathMatches(template, actual string) bool {
	pattern := "^" + regexp.MustCompile(`:[a-z_]+`).ReplaceAllString(regexp.QuoteMeta(template), `[^/]+`) + "$"
	// QuoteMeta escaped nothing in ":name"; the colon survives it.
	return regexp.MustCompile(pattern).MatchString(strings.TrimSuffix(actual, "/"))
}

func hasFlag(c contract.Command, flag string) bool { return contains(c.Flags, flag) }

func contains(list []string, want string) bool {
	for _, s := range list {
		if s == want {
			return true
		}
	}
	return false
}
