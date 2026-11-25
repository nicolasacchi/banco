package main

import (
	"net/http"
	"net/http/httptest"
	"os"
	"path/filepath"
	"strings"
	"testing"

	"banco/contract"
)

// recorder answers {} and remembers the last request.
type recorded struct {
	method, path, query, dry, body string
}

func recordingServer(t *testing.T) (*httptest.Server, *recorded) {
	t.Helper()
	r := &recorded{}
	srv := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, req *http.Request) {
		buf := make([]byte, 1<<16)
		n, _ := req.Body.Read(buf)
		r.method, r.path, r.query, r.dry, r.body = req.Method, req.URL.Path, req.URL.RawQuery, req.Header.Get("X-Banco-Dry-Run"), string(buf[:n])
		w.Header().Set("X-Banco-Contract", contract.Digest())
		w.Header().Set("Content-Type", "application/json")
		_, _ = w.Write([]byte(`{}`))
	}))
	t.Cleanup(srv.Close)
	return srv, r
}

func TestContractListsTheCourseCommands(t *testing.T) {
	c, err := contract.Parse()
	if err != nil {
		t.Fatal(err)
	}
	want := map[string][2]string{
		"course open":          {"GET", "/api/v1/subjects/:subject/course"},
		"course submit":        {"POST", "/api/v1/subjects/:subject/course"},
		"lessons list":         {"GET", "/api/v1/subjects/:subject/lessons"},
		"lesson open":          {"GET", "/api/v1/lessons/:lesson"},
		"lesson submit":        {"POST", "/api/v1/lessons/submit"},
		"lesson status":        {"GET", "/api/v1/lesson-revisions/:revision"},
		"lesson render":        {"POST", "/api/v1/lesson-revisions/:revision/render"},
		"lesson shots":         {"GET", "/api/v1/lesson-revisions/:revision/shots"},
		"lesson-review open":   {"GET", "/api/v1/lesson-revisions/:revision/review"},
		"lesson-review submit": {"POST", "/api/v1/lesson-revisions/:revision/review"},
		"topics list":          {"GET", "/api/v1/subjects/:subject/topics"},
		"topic open":           {"GET", "/api/v1/topics/:topic"},
		"topic submit":         {"POST", "/api/v1/topics/:topic"},
		"practice progress":    {"GET", "/api/v1/subjects/:subject/practice/progress"},
	}
	if c.Version != 1 {
		t.Errorf("contract_version stays 1, got %d", c.Version)
	}
	seen := 0
	for _, cmd := range c.Commands {
		w, ok := want[cmd.Name]
		if !ok {
			continue
		}
		seen++
		if cmd.Local || cmd.Method == nil || cmd.Path == nil || *cmd.Method != w[0] || *cmd.Path != w[1] {
			t.Errorf("%s: want %v, got %v %v", cmd.Name, w, cmd.Method, cmd.Path)
		}
		if len(cmd.ErrorCodes) == 0 || cmd.ErrorCodes[0] != "E-AUTH" {
			t.Errorf("%s: error codes should start with E-AUTH, got %v", cmd.Name, cmd.ErrorCodes)
		}
	}
	if seen != len(want) {
		t.Fatalf("the contract lists %d of %d course commands", seen, len(want))
	}
}

func TestContractChangesOfExistingCommands(t *testing.T) {
	c, _ := contract.Parse()
	has := func(list []string, s string) bool {
		for _, x := range list {
			if x == s {
				return true
			}
		}
		return false
	}
	for _, cmd := range c.Commands {
		switch cmd.Name {
		case "items list":
			if !has(cmd.Flags, "--kind") {
				t.Error("items list lacks --kind")
			}
		case "work submit":
			for _, code := range []string{"E-HINTS", "E-HINT-KEY", "E-PRACTICE-POOL"} {
				if !has(cmd.ErrorCodes, code) {
					t.Errorf("work submit lacks %s", code)
				}
			}
		case "blueprint submit":
			if !has(cmd.ErrorCodes, "E-BLUEPRINT-PRACTICE-ITEM") {
				t.Error("blueprint submit lacks E-BLUEPRINT-PRACTICE-ITEM")
			}
		case "review submit":
			if !has(cmd.ErrorCodes, "E-REVIEW-CHECKLIST") {
				t.Error("review submit lacks E-REVIEW-CHECKLIST")
			}
		}
		if strings.Contains(cmd.Name, "approve") || strings.Contains(cmd.Name, "release") {
			t.Errorf("%s: no command decides (firm rule 2)", cmd.Name)
		}
	}
}

func TestCourseCommandsSendTheRightRequests(t *testing.T) {
	srv, r := recordingServer(t)
	dir := t.TempDir()
	write := func(name, body string) string {
		p := filepath.Join(dir, name)
		if err := os.WriteFile(p, []byte(body), 0o600); err != nil {
			t.Fatal(err)
		}
		return p
	}
	topic := write("topic.json", `{"key":"ripasso.math.demo-equations","schema":"banco.topic/1"}`)
	course := write("course.json", `{"schema":"banco.course/1"}`)
	review := write("review.json", `{"schema":"banco.lesson_review/1"}`)
	cases := []struct {
		args                []string
		method, path, query string
		dry                 string
		bodyHas             string
	}{
		{[]string{"course", "open", "--subject", "math"}, "GET", "/api/v1/subjects/math/course", "", "", ""},
		{[]string{"course", "submit", "--subject", "math", course, "--dry-run"}, "POST", "/api/v1/subjects/math/course", "", "1", `{"course":`},
		{[]string{"lessons", "list", "--subject", "italian"}, "GET", "/api/v1/subjects/italian/lessons", "", "", ""},
		{[]string{"lesson", "status", "12"}, "GET", "/api/v1/lesson-revisions/12", "", "", ""},
		{[]string{"lesson-review", "open", "12"}, "GET", "/api/v1/lesson-revisions/12/review", "", "", ""},
		{[]string{"lesson-review", "submit", "12", "--file", review}, "POST", "/api/v1/lesson-revisions/12/review", "", "", `{"review":`},
		{[]string{"topics", "list", "--subject", "math"}, "GET", "/api/v1/subjects/math/topics", "", "", ""},
		{[]string{"topic", "open", "ripasso.math.demo-equations"}, "GET", "/api/v1/topics/ripasso.math.demo-equations", "", "", ""},
		{[]string{"topic", "submit", topic, "--dry-run"}, "POST", "/api/v1/topics/ripasso.math.demo-equations", "", "1", `{"topic":`},
		{[]string{"practice", "progress", "--subject", "math"}, "GET", "/api/v1/subjects/math/practice/progress", "", "", ""},
		{[]string{"practice", "progress", "--subject", "math", "--student", "trial-1"}, "GET", "/api/v1/subjects/math/practice/progress", "student=trial-1", "", ""},
		{[]string{"items", "list", "--subject", "math", "--kind", "practice"}, "GET", "/api/v1/items", "kind=practice&subject=math", "", ""},
	}
	for _, c := range cases {
		*r = recorded{}
		res := runCLI(t, srv.URL, envToken("tok"), c.args...)
		if res.exit != ExitOK {
			t.Errorf("%v: exit %d, stderr %s", c.args, res.exit, res.stderr)
			continue
		}
		if r.method != c.method || r.path != c.path || r.query != c.query || r.dry != c.dry || !strings.Contains(r.body, c.bodyHas) {
			t.Errorf("%v: sent %+v", c.args, *r)
		}
	}
}

func TestCourseCommandsRefuseBadArguments(t *testing.T) {
	srv, r := recordingServer(t)
	for _, args := range [][]string{
		{"items", "list", "--kind", "testlet"},
		{"lesson", "status", "abc"},
		{"lesson-review", "submit", "12"},
		{"topic", "open", "math.demo"},
		{"topic", "open", "ripasso.math.demo", "--dry-run"},
		{"course", "open"},
		{"practice", "progress", "--subject", "math", "--student", "../x"},
		{"lesson", "open", "nope"},
		{"lesson", "submit"},
	} {
		*r = recorded{}
		res := runCLI(t, srv.URL, envToken("tok"), args...)
		if res.exit != ExitUsage {
			t.Errorf("%v: exit %d, want usage; stderr %s", args, res.exit, res.stderr)
		}
		if r.method != "" {
			t.Errorf("%v: reached the server", args)
		}
	}
}

func TestLessonOpenWritesTheFolderAndSubmitReadsItBack(t *testing.T) {
	var got struct{ method, path, dry, body string }
	srv := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, req *http.Request) {
		w.Header().Set("X-Banco-Contract", contract.Digest())
		w.Header().Set("Content-Type", "application/json")
		if req.Method == "GET" {
			_, _ = w.Write([]byte(`{"lesson":"ripasso.math.demo-equations","kind":"ripasso","subject":"math","latest":{"revision_id":41,"seq":2},"files":{"lesson.md":"---\nkey: ripasso.math.demo-equations\n---\n\n## Perché ti serve\nTesto.\n"},"reviews":[],"teacher_comments":[]}`))
			return
		}
		buf := make([]byte, 1<<16)
		n, _ := req.Body.Read(buf)
		got.method, got.path, got.dry, got.body = req.Method, req.URL.Path, req.Header.Get("X-Banco-Dry-Run"), string(buf[:n])
		w.WriteHeader(201)
		_, _ = w.Write([]byte(`{"lesson":"ripasso.math.demo-equations","revision_id":42,"seq":3,"replayed":false,"warnings":[]}`))
	}))
	t.Cleanup(srv.Close)
	dir := filepath.Join(t.TempDir(), "lesson")
	res := runCLI(t, srv.URL, envToken("tok"), "lesson", "open", "ripasso.math.demo-equations", "--dir", dir)
	if res.exit != 0 {
		t.Fatalf("lesson open: exit %d, stderr %s", res.exit, res.stderr)
	}
	md, err := os.ReadFile(filepath.Join(dir, "lesson.md"))
	if err != nil || !strings.Contains(string(md), "## Perché ti serve") {
		t.Fatalf("lesson.md not written: %v %q", err, md)
	}
	if base, _ := os.ReadFile(filepath.Join(dir, ".base")); strings.TrimSpace(string(base)) != "41" {
		t.Errorf(".base = %q, want 41", base)
	}
	if !strings.Contains(res.stdout, `"dir":"`+dir+`"`) {
		t.Errorf("stdout lacks the dir: %s", res.stdout)
	}
	res = runCLI(t, srv.URL, envToken("tok"), "lesson", "submit", dir, "--dry-run")
	if res.exit != 0 || got.method != "POST" || got.path != "/api/v1/lessons/submit" || got.dry != "1" {
		t.Fatalf("dry run: exit %d, sent %+v, stderr %s", res.exit, got, res.stderr)
	}
	for _, want := range []string{`"lesson":"ripasso.math.demo-equations"`, `"base":41`, `"lesson.md":`} {
		if !strings.Contains(got.body, want) {
			t.Errorf("body lacks %s: %s", want, got.body)
		}
	}
	if base, _ := os.ReadFile(filepath.Join(dir, ".base")); strings.TrimSpace(string(base)) != "41" {
		t.Errorf("a dry run moved .base to %q", base)
	}
	res = runCLI(t, srv.URL, envToken("tok"), "lesson", "submit", dir)
	if res.exit != 0 {
		t.Fatalf("submit: exit %d, stderr %s", res.exit, res.stderr)
	}
	if base, _ := os.ReadFile(filepath.Join(dir, ".base")); strings.TrimSpace(string(base)) != "42" {
		t.Errorf(".base = %q after the submit, want 42", base)
	}
	res = runCLI(t, srv.URL, envToken("tok"), "lesson", "submit", dir, "--base", "7")
	if !strings.Contains(got.body, `"base":7`) {
		t.Errorf("--base ignored: %s", got.body)
	}
}

func TestLessonOpenRefusesAFolderThatHoldsOtherFiles(t *testing.T) {
	srv, r := recordingServer(t)
	dir := t.TempDir()
	if err := os.WriteFile(filepath.Join(dir, "notes.txt"), []byte("x"), 0o644); err != nil {
		t.Fatal(err)
	}
	res := runCLI(t, srv.URL, envToken("tok"), "lesson", "open", "ripasso.math.demo-equations", "--dir", dir)
	if res.exit != ExitUsage || r.method != "" {
		t.Errorf("exit %d, reached the server %q", res.exit, r.method)
	}
}

func TestLessonSubmitNeedsAKeyInTheFrontMatter(t *testing.T) {
	srv, r := recordingServer(t)
	dir := t.TempDir()
	if err := os.WriteFile(filepath.Join(dir, "lesson.md"), []byte("---\ntitle_it: x\n---\n"), 0o644); err != nil {
		t.Fatal(err)
	}
	res := runCLI(t, srv.URL, envToken("tok"), "lesson", "submit", dir)
	if res.exit != ExitValidation || r.method != "" {
		t.Errorf("exit %d, reached the server %q, stderr %s", res.exit, r.method, res.stderr)
	}
}

func TestLessonOpenSchemaFlagIsSentAndChecked(t *testing.T) {
	var query string
	srv := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, req *http.Request) {
		w.Header().Set("X-Banco-Contract", contract.Digest())
		w.Header().Set("Content-Type", "application/json")
		query = req.URL.RawQuery
		_, _ = w.Write([]byte(`{"lesson":"ripasso.math.demo-equations","kind":"ripasso","subject":"math","latest":{"revision_id":41},"files":{"lesson.md":"---\nschema: banco.lesson/2\nkey: ripasso.math.demo-equations\n---\n"},"reviews":[],"teacher_comments":[]}`))
	}))
	t.Cleanup(srv.Close)
	dir := filepath.Join(t.TempDir(), "lesson")
	res := runCLI(t, srv.URL, envToken("tok"), "lesson", "open", "ripasso.math.demo-equations", "--dir", dir, "--schema", "2")
	if res.exit != 0 || query != "schema=2" {
		t.Fatalf("--schema 2: exit %d, query %q, stderr %s", res.exit, query, res.stderr)
	}
	query = ""
	res = runCLI(t, srv.URL, envToken("tok"), "lesson", "open", "ripasso.math.demo-equations", "--dir", dir)
	if res.exit != 0 || query != "" {
		t.Fatalf("no flag: exit %d, query %q", res.exit, query)
	}
	res = runCLI(t, srv.URL, envToken("tok"), "lesson", "open", "ripasso.math.demo-equations", "--dir", dir, "--schema", "3")
	if res.exit != ExitUsage || !strings.Contains(res.stderr, "E-USAGE") {
		t.Fatalf("--schema 3: exit %d, stderr %s", res.exit, res.stderr)
	}
}

func TestLessonRenderRetryAsksTheServerForAnotherDraw(t *testing.T) {
	srv, rec := recordingServer(t)
	res := runCLI(t, srv.URL, envToken("tok"), "lesson", "render", "12", "--retry")
	if res.exit != 0 {
		t.Fatalf("lesson render --retry: exit %d, stderr %s", res.exit, res.stderr)
	}
	if rec.method != "POST" || rec.path != "/api/v1/lesson-revisions/12/render" || rec.dry != "" {
		t.Errorf("request: %+v", rec)
	}
	res = runCLI(t, srv.URL, envToken("tok"), "lesson", "render", "12", "--retry", "--dry-run")
	if res.exit != 0 || rec.dry != "1" {
		t.Errorf("--dry-run: exit %d, %+v", res.exit, rec)
	}
	// without --retry nothing is asked: the render runs by itself, and only a timed-out one is drawn again
	*rec = recorded{}
	res = runCLI(t, srv.URL, envToken("tok"), "lesson", "render", "12")
	if res.exit != ExitUsage || !strings.Contains(res.stderr, "--retry") || rec.method != "" {
		t.Errorf("without --retry: exit %d stderr %s request %+v", res.exit, res.stderr, rec)
	}
	res = runCLI(t, srv.URL, envToken("tok"), "lesson", "render", "abc", "--retry")
	if res.exit != ExitUsage || rec.method != "" {
		t.Errorf("a revision is a number: exit %d %+v", res.exit, rec)
	}
}

func TestLessonRenderRetryRefusedIsTheServersAnswer(t *testing.T) {
	srv := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, req *http.Request) {
		w.Header().Set("X-Banco-Contract", contract.Digest())
		w.WriteHeader(409)
		_, _ = w.Write([]byte(`{"code":"E-RETRY-REFUSED","field":"revision","message":"the latest render did not fail on the server's time limits alone","next":"banco lesson status 12"}`))
	}))
	t.Cleanup(srv.Close)
	res := runCLI(t, srv.URL, envToken("tok"), "lesson", "render", "12", "--retry")
	if res.exit == 0 || !strings.Contains(res.stderr, "E-RETRY-REFUSED") || !strings.Contains(res.stderr, "banco lesson status 12") {
		t.Errorf("refusal: exit %d stderr %s", res.exit, res.stderr)
	}
}

func TestLessonShotsDownloadsEveryImage(t *testing.T) {
	sha := strings.Repeat("a", 64)
	gone := strings.Repeat("b", 64)
	srv := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, req *http.Request) {
		w.Header().Set("X-Banco-Contract", contract.Digest())
		switch req.URL.Path {
		case "/api/v1/lesson-revisions/12/shots":
			w.Header().Set("Content-Type", "application/json")
			_, _ = w.Write([]byte(`{"revision_id":12,"status":"passed","errors":[],"shots":[` +
				`{"card":0,"level":"cover","viewport":"390x844-cream","sha256":"` + sha + `","available":true,"path":"/api/v1/lesson-revisions/12/shots/` + sha + `"},` +
				`{"card":1,"viewport":"390x844-cream","sha256":"` + sha + `","available":true,"path":"/api/v1/lesson-revisions/12/shots/` + sha + `"},` +
				`{"card":1,"state":"ex2","viewport":"390x844-cream","sha256":"` + sha + `","available":true,"path":"/api/v1/lesson-revisions/12/shots/` + sha + `"},` +
				`{"card":2,"viewport":"1280x800-dark","sha256":"` + gone + `","available":false,"path":"/api/v1/lesson-revisions/12/shots/` + gone + `"}]}`))
		case "/api/v1/lesson-revisions/12/shots/" + sha:
			w.Header().Set("Content-Type", "image/webp")
			_, _ = w.Write([]byte("RIFFxxxxWEBP"))
		default:
			w.WriteHeader(404)
		}
	}))
	t.Cleanup(srv.Close)
	dir := filepath.Join(t.TempDir(), "shots")
	res := runCLI(t, srv.URL, envToken("tok"), "lesson", "shots", "12", "--dir", dir)
	if res.exit != 0 {
		t.Fatalf("lesson shots: exit %d, stderr %s", res.exit, res.stderr)
	}
	data, err := os.ReadFile(filepath.Join(dir, "card-01_390x844-cream.webp"))
	if err != nil || string(data) != "RIFFxxxxWEBP" {
		t.Fatalf("image not written: %v %q", err, data)
	}
	// the cover (card 0, the hero figure) is a file of its own
	if _, err := os.ReadFile(filepath.Join(dir, "card-00_390x844-cream.webp")); err != nil {
		t.Fatalf("the cover's image not written: %v", err)
	}
	// another exercise of Prova tu (D-311): its own file, the state in the name and in the answer
	if _, err := os.ReadFile(filepath.Join(dir, "card-01-ex2_390x844-cream.webp")); err != nil {
		t.Fatalf("the state's image not written: %v", err)
	}
	if !strings.Contains(res.stdout, `"state":"ex2"`) {
		t.Errorf("answer without the state: %s", res.stdout)
	}
	if !strings.Contains(res.stdout, `"removed_by_purge":1`) || !strings.Contains(res.stdout, `"status":"passed"`) {
		t.Errorf("answer: %s", res.stdout)
	}
	if bad := runCLI(t, srv.URL, envToken("tok"), "lesson", "shots", "abc"); bad.exit == 0 {
		t.Error("a revision that is not a number must be refused")
	}
}

func TestLessonSubmitAllowReservedSendsItsHeaderOnlyWithADryRun(t *testing.T) {
	var dry, reserved string
	srv := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, req *http.Request) {
		w.Header().Set("X-Banco-Contract", contract.Digest())
		w.Header().Set("Content-Type", "application/json")
		dry, reserved = req.Header.Get("X-Banco-Dry-Run"), req.Header.Get("X-Banco-Allow-Reserved")
		_, _ = w.Write([]byte(`{"dry_run":true,"status":"passed","codes":[],"warnings":[]}`))
	}))
	t.Cleanup(srv.Close)
	dir := t.TempDir()
	md := "---\nkey: ripasso.math.demo-equations\n---\n\n## Perché ti serve\nTesto.\n"
	if err := os.WriteFile(filepath.Join(dir, "lesson.md"), []byte(md), 0o644); err != nil {
		t.Fatal(err)
	}
	res := runCLI(t, srv.URL, envToken("tok"), "lesson", "submit", dir, "--dry-run", "--allow-reserved")
	if res.exit != 0 || dry != "1" || reserved != "1" {
		t.Fatalf("dry run with --allow-reserved: exit %d, dry %q, reserved %q, stderr %s", res.exit, dry, reserved, res.stderr)
	}
	dry, reserved = "", ""
	res = runCLI(t, srv.URL, envToken("tok"), "lesson", "submit", dir, "--dry-run")
	if res.exit != 0 || dry != "1" || reserved != "" {
		t.Fatalf("dry run alone: exit %d, dry %q, reserved %q", res.exit, dry, reserved)
	}
	dry, reserved = "", ""
	res = runCLI(t, srv.URL, envToken("tok"), "lesson", "submit", dir, "--allow-reserved")
	if res.exit == 0 || dry != "" || reserved != "" || !strings.Contains(res.stderr, "allow-reserved") {
		t.Fatalf("--allow-reserved without --dry-run must be refused before any request: exit %d, sent %q/%q, stderr %s", res.exit, dry, reserved, res.stderr)
	}
}

func TestLessonSubmitDryRunRefusalIsOutputOnStdoutWithExitThree(t *testing.T) {
	body := `{"code":"E-LESSON-BLOCK","field":"/cards/0/blocks/1","message":"m","next":"fix","dry_run":true,"codes":["E-LESSON-BLOCK"],"findings":[{"code":"E-LESSON-BLOCK","severity":"error","field":"/cards/0/blocks/1","message":"m"}]}`
	srv, _ := sequenceServer(t, [2]string{"422", body}, [2]string{"422", body}, [2]string{"409", `{"code":"E-CHROME-BUSY","field":"chrome","message":"busy","next":"retry"}`})
	dir := t.TempDir()
	write(t, dir, "lesson.md", "---\nkey: ripasso.math.demo-equations\n---\n\n## Perché ti serve\nTesto.\n")
	res := runCLI(t, srv.URL, envToken("tok"), "lesson", "submit", dir, "--dry-run")
	if res.exit != ExitValidation {
		t.Fatalf("exit %d, want 3", res.exit)
	}
	if e := assertErrJSON(t, res.stdout, "E-LESSON-BLOCK"); len(e.Codes) != 1 || len(e.Findings) != 1 || !e.DryRun {
		t.Errorf("the findings are the output: %+v", e)
	}
	if res.stderr != "" {
		t.Errorf("stderr = %q", res.stderr)
	}
	// a real submit stays an error on stderr; a conflict of a dry run (Chrome busy) is no verdict and stays on stderr too
	res = runCLI(t, srv.URL, envToken("tok"), "lesson", "submit", dir)
	if res.exit != ExitValidation || res.stdout != "" {
		t.Errorf("real submit: exit %d stdout %q", res.exit, res.stdout)
	}
	res = runCLI(t, srv.URL, envToken("tok"), "lesson", "submit", dir, "--dry-run")
	if res.exit != ExitConflict || res.stdout != "" || !strings.Contains(res.stderr, "E-CHROME-BUSY") {
		t.Errorf("busy dry run: exit %d stdout %q stderr %q", res.exit, res.stdout, res.stderr)
	}
}
