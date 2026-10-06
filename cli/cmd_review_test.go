package main

import (
	"bytes"
	"encoding/json"
	"io"
	"net/http"
	"net/http/httptest"
	"strings"
	"testing"
	"time"

	"banco/contract"
)

// runWithSession is runCLI with a session id, as BANCO_SESSION would give it.
func runWithSession(t *testing.T, baseURL, session string, args ...string) result {
	t.Helper()
	var out, errb bytes.Buffer
	e := &env{stdout: &out, stderr: &errb, getenv: func(string) string { return "" }}
	e.client = func() *client {
		return &client{baseURL: baseURL, http: &http.Client{Timeout: 5 * time.Second}, tokens: envToken("bnc_x"), session: session}
	}
	code := runWith(args, e)
	return result{code, out.String(), errb.String()}
}

func TestSessionNewPostsAndPrintsTheId(t *testing.T) {
	srv, seen := sequenceServer(t, [2]string{"201", `{"id":42,"role":"reviewer","family":"openai"}`})
	r := runWithSession(t, srv.URL, "", "session", "new", "--role", "reviewer", "--agent", "omp", "--model", "gpt-5.2", "--id")
	if r.exit != ExitOK || strings.TrimSpace(r.stdout) != "42" {
		t.Fatalf("exit %d stdout %q stderr %q", r.exit, r.stdout, r.stderr)
	}
	got := (*seen)[0]
	if got.method != "POST" || got.path != "/api/v1/sessions" || got.body["role"] != "reviewer" || got.body["agent"] != "omp" || got.body["model"] != "gpt-5.2" {
		t.Fatalf("request %+v", got)
	}
	// Without --id the whole answer is printed.
	r = runWithSession(t, srv.URL, "", "session", "new", "--role", "grader", "--agent", "claude-code", "--model", "claude-sonnet-5-5")
	if r.exit != ExitOK || !strings.Contains(r.stdout, `"family":"openai"`) {
		t.Fatalf("exit %d stdout %q", r.exit, r.stdout)
	}
}

func TestSessionNewUsageErrors(t *testing.T) {
	srv, seen := sequenceServer(t, [2]string{"201", `{}`})
	for _, args := range [][]string{
		{"session", "new"},
		{"session", "new", "--role", "operator", "--agent", "a", "--model", "m"},
		{"session", "new", "--role", "author", "--model", "m"},
		{"session", "new", "--role", "author", "--agent", "a"},
		{"session", "new", "--role", "author", "--agent", "a", "--model", "m", "extra"},
	} {
		r := runWithSession(t, srv.URL, "", args...)
		if r.exit != ExitUsage {
			t.Errorf("%v: exit %d", args, r.exit)
		}
		assertErrJSON(t, r.stderr, "E-USAGE")
	}
	if len(*seen) != 0 {
		t.Fatal("a usage error must not reach the server")
	}
}

func TestReviewSolveGradeCommandsSendTheSessionAndTheirBody(t *testing.T) {
	cases := []struct {
		args   []string
		method string
		path   string
		member string
		dry    string
	}{
		{[]string{"review", "open", "7"}, "GET", "/api/v1/revisions/7/review", "", ""},
		{[]string{"review", "submit", "7", "--file", "FILE"}, "POST", "/api/v1/revisions/7/review", "review", ""},
		{[]string{"review", "submit", "--file", "FILE", "7", "--dry-run"}, "POST", "/api/v1/revisions/7/review", "review", "1"},
		{[]string{"solve", "open", "12"}, "GET", "/api/v1/revisions/12/solve", "", ""},
		{[]string{"solve", "submit", "12", "--file", "FILE"}, "POST", "/api/v1/revisions/12/solve", "solve", ""},
		{[]string{"grade", "propose", "5", "--file", "FILE"}, "POST", "/api/v1/attempts/5/grade-proposals", "grade", ""},
		{[]string{"grade", "propose", "5", "--file", "FILE", "--dry-run"}, "POST", "/api/v1/attempts/5/grade-proposals", "grade", "1"},
		{[]string{"submissions", "--pending", "--json"}, "GET", "/api/v1/submissions/pending", "", ""},
	}
	for _, c := range cases {
		var gotSession, gotDry, gotMethod, gotPath string
		var gotBody map[string]any
		srv := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
			gotSession, gotDry, gotMethod, gotPath = r.Header.Get("X-Banco-Session"), r.Header.Get("X-Banco-Dry-Run"), r.Method, r.URL.Path
			raw, _ := io.ReadAll(r.Body)
			_ = json.Unmarshal(raw, &gotBody)
			w.Header().Set("X-Banco-Contract", contract.Digest())
			_, _ = w.Write([]byte(`{"ok":true}`))
		}))
		file := writeTemp(t, "doc.json", `{"schema":"x"}`)
		args := append([]string{}, c.args...)
		for i, a := range args {
			if a == "FILE" {
				args[i] = file
			}
		}
		r := runWithSession(t, srv.URL, "31", args...)
		srv.Close()
		if r.exit != ExitOK {
			t.Fatalf("%v: exit %d: %s", c.args, r.exit, r.stderr)
		}
		if gotSession != "31" || gotMethod != c.method || gotPath != c.path || gotDry != c.dry {
			t.Errorf("%v: session %q method %s path %s dry %q", c.args, gotSession, gotMethod, gotPath, gotDry)
		}
		if c.member != "" {
			doc, _ := gotBody[c.member].(map[string]any)
			if doc["schema"] != "x" {
				t.Errorf("%v: the file must travel under %q, body = %v", c.args, c.member, gotBody)
			}
		}
	}
}

func TestRevisionCommandsUsageErrors(t *testing.T) {
	srv, seen := sequenceServer(t, [2]string{"200", `{}`})
	file := writeTemp(t, "doc.json", `{}`)
	bad := writeTemp(t, "bad.json", `{not json`)
	for _, args := range [][]string{
		{"review", "open"},
		{"review", "open", "abc"},
		{"review", "open", "0"},
		{"review", "open", "7", "--file", file},
		{"review", "open", "7", "--dry-run"},
		{"review", "submit", "7"},
		{"review", "submit", "7", "--file", "/nonexistent/x.json"},
		{"solve", "submit", "7", "--file", file, "8"},
		{"grade", "propose", "x", "--file", file},
		{"grade", "propose", "5"},
		{"submissions"},
		{"submissions", "--pending", "extra"},
	} {
		r := runWithSession(t, srv.URL, "1", args...)
		if r.exit != ExitUsage {
			t.Errorf("%v: exit %d (%s)", args, r.exit, r.stderr)
		}
	}
	r := runWithSession(t, srv.URL, "1", "review", "submit", "7", "--file", bad)
	if r.exit != ExitValidation {
		t.Errorf("a file that is not JSON: exit %d", r.exit)
	}
	assertErrJSON(t, r.stderr, "E-FILES")
	if len(*seen) != 0 {
		t.Fatalf("a usage error must not reach the server: %d requests", len(*seen))
	}
}

func TestServerRefusalsKeepTheirCodes(t *testing.T) {
	srv, _ := sequenceServer(t, [2]string{"422", `{"code":"E-QUOTE-NOT-FOUND","field":"/findings/0/quote","message":"no","next":"fix"}`})
	file := writeTemp(t, "doc.json", `{}`)
	r := runWithSession(t, srv.URL, "1", "review", "submit", "7", "--file", file)
	if r.exit != ExitValidation {
		t.Fatalf("exit %d", r.exit)
	}
	assertErrJSON(t, r.stderr, "E-QUOTE-NOT-FOUND")
}

// The CLI accepts --json (the default) on the open commands, so the contract lists it.
func TestOpenCommandsDeclareJSONFlag(t *testing.T) {
	c, err := contract.Parse()
	if err != nil {
		t.Fatal(err)
	}
	for _, name := range []string{"review open", "solve open"} {
		found := false
		for _, cc := range c.Commands {
			if cc.Name != name {
				continue
			}
			for _, f := range cc.Flags {
				found = found || f == "--json"
			}
		}
		if !found {
			t.Errorf("%s: contract flags lack --json", name)
		}
	}
}
