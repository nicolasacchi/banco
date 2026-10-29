package main

import (
	"bytes"
	"encoding/base64"
	"encoding/json"
	"io"
	"net/http"
	"net/http/httptest"
	"os"
	"path/filepath"
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

func TestSessionNewAcceptsParenthesesAndNamesBadCharacters(t *testing.T) {
	srv, seen := sequenceServer(t, [2]string{"201", `{"id":7}`})
	r := runWithSession(t, srv.URL, "", "session", "new", "--role", "author", "--agent", "claude-code (promoted from staging)", "--model", "m", "--id")
	if r.exit != ExitOK || strings.TrimSpace(r.stdout) != "7" {
		t.Fatalf("exit %d stdout %q stderr %q", r.exit, r.stdout, r.stderr)
	}
	if (*seen)[0].body["agent"] != "claude-code (promoted from staging)" {
		t.Fatalf("request %+v", (*seen)[0])
	}
	r = runWithSession(t, srv.URL, "", "session", "new", "--role", "author", "--agent", "bad$name", "--model", "m")
	if r.exit != ExitUsage || !strings.Contains(r.stderr, "letters, digits") {
		t.Fatalf("exit %d stderr %q", r.exit, r.stderr)
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
		{[]string{"findings", "respond", "9", "--file", "FILE"}, "POST", "/api/v1/findings/9/responses", "response", ""},
		{[]string{"findings", "respond", "9", "--file", "FILE", "--dry-run"}, "POST", "/api/v1/findings/9/responses", "response", "1"},
		{[]string{"findings", "assess", "9", "--file", "FILE"}, "POST", "/api/v1/findings/9/assessments", "assessment", ""},
		{[]string{"findings", "assess", "9", "--file", "FILE", "--dry-run"}, "POST", "/api/v1/findings/9/assessments", "assessment", "1"},
		{[]string{"findings", "list", "--subject", "italian"}, "GET", "/api/v1/subjects/italian/findings", "", ""},
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

func TestSubmissionsStudentFlag(t *testing.T) {
	for args, want := range map[string]string{"": "", "prova-1": "student=prova-1", "all": "student=all"} {
		var gotQuery string
		srv := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
			gotQuery = r.URL.RawQuery
			w.Header().Set("X-Banco-Contract", contract.Digest())
			_, _ = w.Write([]byte(`{"ok":true}`))
		}))
		cmd := []string{"submissions", "--pending", "--json"}
		if args != "" {
			cmd = append(cmd, "--student", args)
		}
		r := runWithSession(t, srv.URL, "31", cmd...)
		srv.Close()
		if r.exit != ExitOK || gotQuery != want {
			t.Errorf("--student %q: exit %d query %q, want %q (%s)", args, r.exit, gotQuery, want, r.stderr)
		}
	}
	srv, seen := sequenceServer(t, [2]string{"200", `{}`})
	r := runWithSession(t, srv.URL, "31", "submissions", "--pending", "--student", "Bad Key")
	if r.exit != ExitUsage || len(*seen) != 0 {
		t.Errorf("a bad student key: exit %d, requests %d", r.exit, len(*seen))
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

func TestFindingsListOpenFlagAndUsage(t *testing.T) {
	var gotQuery, gotPath string
	srv := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		gotQuery, gotPath = r.URL.RawQuery, r.URL.Path
		w.Header().Set("X-Banco-Contract", contract.Digest())
		_, _ = w.Write([]byte(`{"rows":[]}`))
	}))
	defer srv.Close()
	r := runWithSession(t, srv.URL, "31", "findings", "list", "--subject", "italian", "--open")
	if r.exit != ExitOK || gotPath != "/api/v1/subjects/italian/findings" || gotQuery != "open=1" {
		t.Fatalf("exit %d path %q query %q: %s", r.exit, gotPath, gotQuery, r.stderr)
	}
	for _, args := range [][]string{{"findings", "list"}, {"findings", "list", "--subject", "Bad Key"}, {"findings", "respond", "x", "--file", "f"}, {"findings", "respond", "3"}, {"findings", "assess", "x", "--file", "f"}, {"findings", "assess", "3"}} {
		if r := runWithSession(t, srv.URL, "31", args...); r.exit != ExitUsage {
			t.Errorf("%v: exit %d, want usage", args, r.exit)
		}
	}
}

// solve open and review open write the figures of the item as PNG files and print their paths instead of the
// pictures (D-320).
func TestSolveOpenWritesTheFigures(t *testing.T) {
	png := []byte("\x89PNG\r\n\x1a\nnot really a picture")
	enc := base64.StdEncoding.EncodeToString(png)
	body := `{"revision_id":7,"instances":[{"instance":1,"display":{"figure":{"alt_it":"Curva","file":"figure-1.png"}}}],` +
		`"figures":[{"name":"figure-1.png","alt_it":"Curva","instances":[1],"width":1000,"height":600,"png_base64":"` + enc + `"},` +
		`{"name":"figure-2.png","alt_it":"Manca","instances":[1],"missing":true}]}`
	srv, seen := sequenceServer(t, [2]string{"200", body})
	dir := filepath.Join(t.TempDir(), "figs")
	// stale files and a symlink of an earlier open are removed, never followed
	if err := os.MkdirAll(dir, 0o700); err != nil {
		t.Fatal(err)
	}
	victim := filepath.Join(t.TempDir(), "victim")
	if err := os.WriteFile(victim, []byte("keep"), 0o600); err != nil {
		t.Fatal(err)
	}
	if err := os.Symlink(victim, filepath.Join(dir, "figure-1.png")); err != nil {
		t.Fatal(err)
	}
	if err := os.WriteFile(filepath.Join(dir, "figure-9.png"), []byte("stale"), 0o600); err != nil {
		t.Fatal(err)
	}
	r := runWithSession(t, srv.URL, "5", "solve", "open", "7", "--dir", dir)
	// a figure the student is shown no picture for: the answer is printed, the exit is not zero
	if r.exit != ExitValidation || !strings.Contains(r.stderr, "E-FIGURE-MISSING") || !strings.Contains(r.stdout, `"warnings"`) {
		t.Fatalf("exit %d stdout %q stderr %q", r.exit, r.stdout, r.stderr)
	}
	if b, _ := os.ReadFile(victim); string(b) != "keep" {
		t.Fatalf("the symlink target was written: %q", b)
	}
	if _, err := os.Stat(filepath.Join(dir, "figure-9.png")); err == nil {
		t.Fatal("a stale figure file was left")
	}
	if st, err := os.Stat(filepath.Join(dir, "figure-1.png")); err != nil || st.Mode().Perm() != 0o600 {
		t.Fatalf("mode %v %v", st, err)
	}
	if (*seen)[0].method != "GET" || (*seen)[0].path != "/api/v1/revisions/7/solve" {
		t.Fatalf("request %+v", (*seen)[0])
	}
	got, err := os.ReadFile(filepath.Join(dir, "figure-1.png"))
	if err != nil || !bytes.Equal(got, png) {
		t.Fatalf("file: %v %q", err, got)
	}
	if _, err := os.Stat(filepath.Join(dir, "figure-2.png")); err == nil {
		t.Fatal("a missing figure must not be written")
	}
	var out struct {
		FiguresDir string           `json:"figures_dir"`
		Figures    []map[string]any `json:"figures"`
	}
	if err := json.Unmarshal([]byte(r.stdout), &out); err != nil {
		t.Fatalf("stdout %q: %v", r.stdout, err)
	}
	if out.FiguresDir == "" || len(out.Figures) != 2 || out.Figures[0]["path"] != filepath.Join(out.FiguresDir, "figure-1.png") || out.Figures[0]["alt_it"] != "Curva" {
		t.Fatalf("figures %+v", out)
	}
	if _, ok := out.Figures[0]["png_base64"]; ok || strings.Contains(r.stdout, enc) {
		t.Fatalf("the picture must not be printed: %q", r.stdout)
	}
	if out.Figures[1]["missing"] != true || out.Figures[1]["path"] != nil {
		t.Fatalf("missing figure %+v", out.Figures[1])
	}
}

func TestOpenWithoutFiguresIsPrintedAsItCame(t *testing.T) {
	srv, _ := sequenceServer(t, [2]string{"200", `{"revision_id":7,"instances":[],"figures":[]}`})
	r := runWithSession(t, srv.URL, "5", "review", "open", "7")
	if r.exit != ExitOK || strings.TrimSpace(r.stdout) != `{"revision_id":7,"instances":[],"figures":[]}` {
		t.Fatalf("exit %d stdout %q stderr %q", r.exit, r.stdout, r.stderr)
	}
}

func TestOpenRefusesUnsafeFigureNamesAndDirOnSubmit(t *testing.T) {
	srv, _ := sequenceServer(t, [2]string{"200", `{"figures":[{"name":"../x.png","png_base64":"AAAA"}]}`})
	r := runWithSession(t, srv.URL, "5", "solve", "open", "7", "--dir", t.TempDir())
	if r.exit == ExitOK {
		t.Fatalf("a figure named ../x.png was accepted: %q", r.stdout)
	}
	r = runWithSession(t, srv.URL, "5", "solve", "submit", "7", "--dir", t.TempDir(), "--file", "x.json")
	if r.exit != ExitUsage {
		t.Fatalf("exit %d stderr %q", r.exit, r.stderr)
	}
}
