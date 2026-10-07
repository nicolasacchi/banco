package main

import (
	"encoding/json"
	"io"
	"net/http"
	"net/http/httptest"
	"os"
	"path/filepath"
	"strings"
	"sync"
	"testing"

	"banco/contract"
)

// request keeps what the CLI sent to the fake API.
type request struct {
	method, path, query, dry string
	body                     map[string]any
}

// sequenceServer answers each request with the next canned (status, body); the last
// one repeats. It records every request.
func sequenceServer(t *testing.T, answers ...[2]string) (*httptest.Server, *[]request) {
	t.Helper()
	var mu sync.Mutex
	var seen []request
	n := 0
	srv := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		mu.Lock()
		defer mu.Unlock()
		raw, _ := io.ReadAll(r.Body)
		var body map[string]any
		_ = json.Unmarshal(raw, &body)
		seen = append(seen, request{method: r.Method, path: r.URL.Path, query: r.URL.RawQuery, dry: r.Header.Get("X-Banco-Dry-Run"), body: body})
		a := answers[min(n, len(answers)-1)]
		n++
		w.Header().Set("X-Banco-Contract", contract.Digest())
		status := 200
		if a[0] != "" {
			status = atoi(a[0])
		}
		w.WriteHeader(status)
		_, _ = w.Write([]byte(a[1]))
	}))
	t.Cleanup(srv.Close)
	return srv, &seen
}

func atoi(s string) int {
	n := 0
	for _, c := range s {
		n = n*10 + int(c-'0')
	}
	return n
}

func write(t *testing.T, dir, name, content string) {
	t.Helper()
	p := filepath.Join(dir, filepath.FromSlash(name))
	if err := os.MkdirAll(filepath.Dir(p), 0o755); err != nil {
		t.Fatal(err)
	}
	if err := os.WriteFile(p, []byte(content), 0o644); err != nil {
		t.Fatal(err)
	}
}

func read(t *testing.T, dir, name string) string {
	t.Helper()
	raw, err := os.ReadFile(filepath.Join(dir, filepath.FromSlash(name)))
	if err != nil {
		t.Fatal(err)
	}
	return string(raw)
}

func exists(dir, name string) bool {
	_, err := os.Stat(filepath.Join(dir, filepath.FromSlash(name)))
	return err == nil
}

func TestWorkOpenWritesTheFolderAndRemembersTheBase(t *testing.T) {
	srv, seen := sequenceServer(t, [2]string{"200", `{"item":"eq-1","revision_id":7,"seq":2,"status":"failed","files":{"item.json":"{\"a\":1}","generator.mjs":"export {}","assets/f.svg":"<svg/>"},"validation":{"codes":["E-VERIFY-MISSING"]}}`})
	dir := filepath.Join(t.TempDir(), "w")
	r := runCLI(t, srv.URL, envToken("bnc_x"), "work", "open", "eq-1", "--dir", dir, "--json")
	if r.exit != ExitOK {
		t.Fatalf("exit %d: %s", r.exit, r.stderr)
	}
	if (*seen)[0].method != "GET" || (*seen)[0].path != "/api/v1/work/items/eq-1" || (*seen)[0].query != "role=author" {
		t.Errorf("request = %+v", (*seen)[0])
	}
	if read(t, dir, "item.json") != `{"a":1}` || read(t, dir, "generator.mjs") != "export {}" || read(t, dir, "assets/f.svg") != "<svg/>" {
		t.Error("files were not written")
	}
	var state workState
	if err := json.Unmarshal([]byte(read(t, dir, ".banco/work.json")), &state); err != nil || state.Item != "eq-1" || state.Base != 7 || state.Role != "author" {
		t.Errorf("state = %+v (%v)", state, err)
	}
	var out map[string]any
	if err := json.Unmarshal([]byte(r.stdout), &out); err != nil || out["revision_id"] != float64(7) {
		t.Errorf("stdout = %q", r.stdout)
	}
}

func TestWorkOpenPrintsReviewFindingsAndTeacherComments(t *testing.T) {
	srv, _ := sequenceServer(t, [2]string{"200", `{"item":"eq-1","revision_id":7,"seq":2,"status":"passed","files":{"item.json":"{}"},"review_findings":[{"id":445,"review_id":268,"severity":"major","quote":"q","problem_it":"p","fix_it":"f"}],"teacher_comments":[{"comment_it":"c"}]}`})
	r := runCLI(t, srv.URL, envToken("bnc_x"), "work", "open", "eq-1", "--dir", filepath.Join(t.TempDir(), "w"))
	if r.exit != ExitOK {
		t.Fatalf("exit %d: %s", r.exit, r.stderr)
	}
	var out map[string]any
	if err := json.Unmarshal([]byte(r.stdout), &out); err != nil {
		t.Fatal(err)
	}
	rf, _ := out["review_findings"].([]any)
	tc, _ := out["teacher_comments"].([]any)
	if len(rf) != 1 || len(tc) != 1 {
		t.Errorf("review_findings and teacher_comments must be printed: %s", r.stdout)
	}
}

func TestWorkOpenWarnsInsideAGitWorkTree(t *testing.T) {
	srv, _ := sequenceServer(t, [2]string{"200", `{"revision_id":1,"files":{"item.json":"{}"}}`})
	repo := t.TempDir()
	write(t, repo, ".git/HEAD", "ref: refs/heads/main")
	r := runCLI(t, srv.URL, envToken("bnc_x"), "work", "open", "eq-1", "--dir", filepath.Join(repo, "eq-1"))
	if r.exit != ExitOK || !strings.Contains(r.stdout, `"warning"`) {
		t.Fatalf("exit %d, want a warning: %s", r.exit, r.stdout)
	}
	out := runCLI(t, srv.URL, envToken("bnc_x"), "work", "open", "eq-1", "--dir", filepath.Join(t.TempDir(), "x"))
	if strings.Contains(out.stdout, `"warning"`) {
		t.Errorf("no warning expected outside a repo: %s", out.stdout)
	}
}

func TestWorkOpenAsVerifierWritesInstancesAndTestsButNoGenerator(t *testing.T) {
	srv, seen := sequenceServer(t, [2]string{"200", `{"item":"eq-1","revision_id":7,"seq":1,"status":"failed","files":{"item.json":"{}"},"instances":[{"answer":"7"}],"tests":{"blank":"invalid"}}`})
	dir := filepath.Join(t.TempDir(), "v")
	r := runCLI(t, srv.URL, envToken("bnc_x"), "work", "open", "eq-1", "--role", "verifier", "--dir", dir)
	if r.exit != ExitOK {
		t.Fatalf("exit %d: %s", r.exit, r.stderr)
	}
	if (*seen)[0].query != "role=verifier" {
		t.Errorf("query = %q", (*seen)[0].query)
	}
	if exists(dir, "generator.mjs") || !exists(dir, "instances.json") || !exists(dir, "tests.json") {
		t.Error("a verifier's folder has the instances and the tests, never generator.mjs")
	}
}

func TestWorkOpenRefusesAFolderThatIsNotEmptyAndNames(t *testing.T) {
	srv, _ := sequenceServer(t, [2]string{"200", `{"revision_id":1,"files":{"item.json":"{}"}}`})
	dir := t.TempDir()
	write(t, dir, "notes.txt", "mine")
	r := runCLI(t, srv.URL, envToken("bnc_x"), "work", "open", "eq-1", "--dir", dir)
	if r.exit != ExitUsage {
		t.Fatalf("exit %d", r.exit)
	}
	assertErrJSON(t, r.stderr, "E-USAGE")

	for _, bad := range []string{"../escape.json", "assets/../../x.svg", "notes.txt", "/abs.json"} {
		body, _ := json.Marshal(map[string]any{"revision_id": 1, "files": map[string]string{bad: "x"}})
		bsrv, _ := sequenceServer(t, [2]string{"200", string(body)})
		r := runCLI(t, bsrv.URL, envToken("bnc_x"), "work", "open", "eq-1", "--dir", filepath.Join(t.TempDir(), "d"))
		if r.exit != ExitServer {
			t.Errorf("%q: exit %d, want a refusal of the name", bad, r.exit)
		}
	}
	for _, args := range [][]string{{"work", "open"}, {"work", "open", "Bad Key"}, {"work", "open", "eq-1", "--role", "boss"}} {
		if got := runCLI(t, srv.URL, envToken("bnc_x"), args...); got.exit != ExitUsage {
			t.Errorf("%v: exit %d", args, got.exit)
		}
	}
}

func TestWorkSubmitSendsTheFilesTheBaseAndTheDryRunHeader(t *testing.T) {
	srv, seen := sequenceServer(t, [2]string{"202", `{"item":"eq-1","revision_id":8,"seq":3,"status":"validating","replayed":false}`})
	dir := t.TempDir()
	write(t, dir, "item.json", `{"kind":"diagnosis_item"}`)
	write(t, dir, "generator.mjs", "export function generate() {}")
	write(t, dir, "assets/f.svg", "<svg/>")
	write(t, dir, "assets/notes.txt", "not an asset name? it is: allowed by the pattern")
	write(t, dir, "scratch.md", "never sent")
	if err := writeState(dir, workState{Item: "eq-1", Base: 7, Role: "author", RevisionID: 7}); err != nil {
		t.Fatal(err)
	}
	r := runCLI(t, srv.URL, envToken("bnc_x"), "work", "submit", dir)
	if r.exit != ExitOK {
		t.Fatalf("exit %d: %s", r.exit, r.stderr)
	}
	got := (*seen)[0]
	if got.method != "POST" || got.path != "/api/v1/work/submit" || got.dry != "" {
		t.Errorf("request = %+v", got)
	}
	if got.body["item"] != "eq-1" || got.body["base"] != float64(7) {
		t.Errorf("body = %v", got.body)
	}
	files := got.body["files"].(map[string]any)
	for _, name := range []string{"item.json", "generator.mjs", "assets/f.svg"} {
		if files[name] == nil {
			t.Errorf("%s was not sent", name)
		}
	}
	if files["scratch.md"] != nil {
		t.Error("an unknown file was sent")
	}
	// The next submit builds on the new revision.
	var state workState
	_ = json.Unmarshal([]byte(read(t, dir, ".banco/work.json")), &state)
	if state.Base != 8 || state.Item != "eq-1" {
		t.Errorf("state after submit = %+v", state)
	}

	dsrv, dseen := sequenceServer(t, [2]string{"200", `{"dry_run":true,"status":"passed","codes":[]}`})
	r = runCLI(t, dsrv.URL, envToken("bnc_x"), "work", "submit", dir, "--dry-run")
	if r.exit != ExitOK || (*dseen)[0].dry != "1" {
		t.Fatalf("dry run: exit %d dry=%q", r.exit, (*dseen)[0].dry)
	}
	_ = json.Unmarshal([]byte(read(t, dir, ".banco/work.json")), &state)
	if state.Base != 8 {
		t.Errorf("a dry run must not change the base: %+v", state)
	}
}

func TestWorkSubmitNewItemHasNoBaseAndTakesTheFolderName(t *testing.T) {
	srv, seen := sequenceServer(t, [2]string{"202", `{"revision_id":1}`})
	dir := filepath.Join(t.TempDir(), "my-item")
	write(t, dir, "item.json", "{}")
	if r := runCLI(t, srv.URL, envToken("bnc_x"), "work", "submit", dir); r.exit != ExitOK {
		t.Fatalf("exit %d: %s", r.exit, r.stderr)
	}
	if (*seen)[0].body["item"] != "my-item" || (*seen)[0].body["base"] != nil {
		t.Errorf("body = %v", (*seen)[0].body)
	}
	if r := runCLI(t, srv.URL, envToken("bnc_x"), "work", "submit", dir, "--item", "Bad Key"); r.exit != ExitUsage {
		t.Errorf("a bad --item: exit %d", r.exit)
	}
}

func TestWorkSubmitAsVerifierSendsVerifyOnly(t *testing.T) {
	srv, seen := sequenceServer(t, [2]string{"202", `{"revision_id":9}`})
	dir := t.TempDir()
	write(t, dir, "item.json", "{}")
	write(t, dir, "verify.mjs", "export function verify() {}")
	write(t, dir, "instances.json", "[]")
	_ = writeState(dir, workState{Item: "eq-1", Base: 7, Role: "verifier"})
	if r := runCLI(t, srv.URL, envToken("bnc_x"), "work", "submit", dir); r.exit != ExitOK {
		t.Fatalf("exit %d: %s", r.exit, r.stderr)
	}
	files := (*seen)[0].body["files"].(map[string]any)
	if len(files) != 1 || files["verify.mjs"] == nil {
		t.Errorf("a verifier sends verify.mjs only, sent %v", files)
	}
}

func TestWorkSubmitDryRunFailureExitsThreeWithTheCodes(t *testing.T) {
	body := `{"code":"E-VERIFY-REJECTS","field":"/verify.mjs","message":"verify rejects 24 clean instances","next":"fix","dry_run":true,"status":"failed","codes":["E-VERIFY-REJECTS"],"findings":[{"code":"E-VERIFY-REJECTS","severity":"error","field":"/verify.mjs","message":"m"}]}`
	srv, _ := sequenceServer(t, [2]string{"422", body})
	dir := t.TempDir()
	write(t, dir, "item.json", "{}")
	r := runCLI(t, srv.URL, envToken("bnc_x"), "work", "submit", dir, "--dry-run")
	if r.exit != ExitValidation {
		t.Fatalf("exit %d", r.exit)
	}
	e := assertErrJSON(t, r.stderr, "E-VERIFY-REJECTS")
	if len(e.Codes) != 1 || len(e.Findings) != 1 || !e.DryRun {
		t.Errorf("codes and findings must reach stderr: %+v", e)
	}
	if r.stdout != "" {
		t.Errorf("stdout = %q", r.stdout)
	}
}

func TestWorkSubmitConflictsAndUsage(t *testing.T) {
	srv, _ := sequenceServer(t, [2]string{"409", `{"code":"E-STALE-BASE","field":"base","message":"m","next":"banco work open eq-1"}`})
	dir := t.TempDir()
	write(t, dir, "item.json", "{}")
	if r := runCLI(t, srv.URL, envToken("bnc_x"), "work", "submit", dir); r.exit != ExitConflict {
		t.Errorf("exit %d", r.exit)
	}
	busy, busySeen := sequenceServer(t, [2]string{"409", `{"code":"E-CHROME-BUSY","field":"chrome","message":"Chrome is busy","next":"retry in 30 s"}`})
	r := runCLI(t, busy.URL, envToken("bnc_x"), "work", "submit", dir, "--dry-run")
	if r.exit != ExitConflict {
		t.Errorf("busy: exit %d", r.exit)
	}
	if e := assertErrJSON(t, r.stderr, "E-CHROME-BUSY"); e.Next != "retry in 30 s" {
		t.Errorf("next = %q", e.Next)
	}
	if len(*busySeen) != 7 {
		t.Errorf("a busy dry run is tried 1+6 times, saw %d", len(*busySeen))
	}
	empty := t.TempDir()
	for _, args := range [][]string{{"work", "submit"}, {"work", "submit", "/no/such/dir"}, {"work", "submit", empty}} {
		if got := runCLI(t, srv.URL, envToken("bnc_x"), args...); got.exit != ExitUsage {
			t.Errorf("%v: exit %d", args, got.exit)
		}
	}
}

func TestWorkStatusWaitPollsUntilSettled(t *testing.T) {
	srv, seen := sequenceServer(t,
		[2]string{"200", `{"revision_id":8,"status":"validating","settled":false}`},
		[2]string{"200", `{"revision_id":8,"status":"error","settled":false}`},
		[2]string{"200", `{"revision_id":8,"status":"passed","settled":true,"codes":[],"instances":24}`})
	e := &env{stdout: &strings.Builder{}, stderr: &strings.Builder{}, getenv: func(k string) string {
		if k == "BANCO_POLL_MS" {
			return "5"
		}
		return ""
	}}
	var out, errb strings.Builder
	e.stdout, e.stderr = &out, &errb
	e.client = func() *client { return &client{baseURL: srv.URL, http: http.DefaultClient, tokens: envToken("bnc_x")} }
	if code := runWith([]string{"work", "status", "8", "--wait"}, e); code != ExitOK {
		t.Fatalf("exit %d: %s", code, errb.String())
	}
	if len(*seen) != 3 {
		t.Errorf("polled %d times, want 3", len(*seen))
	}
	if !strings.Contains(out.String(), `"passed"`) || strings.Count(out.String(), "\n") != 1 {
		t.Errorf("only the final answer is printed: %q", out.String())
	}
}

func TestWorkStatusWaitFailedExitsThree(t *testing.T) {
	srv, _ := sequenceServer(t, [2]string{"200", `{"revision_id":8,"status":"failed","settled":true,"codes":["E-SOLUTION-IN-DISPLAY","E-GEN-POOL"],"findings":[{"code":"E-SOLUTION-IN-DISPLAY"}]}`})
	r := runCLI(t, srv.URL, envToken("bnc_x"), "work", "status", "8", "--wait")
	if r.exit != ExitValidation {
		t.Fatalf("exit %d", r.exit)
	}
	e := assertErrJSON(t, r.stderr, "E-SOLUTION-IN-DISPLAY")
	if len(e.Codes) != 2 || len(e.Findings) != 1 {
		t.Errorf("%+v", e)
	}
	if !strings.Contains(r.stdout, `"failed"`) {
		t.Errorf("the status is still printed: %q", r.stdout)
	}
}

func TestWorkStatusWaitVerifyMissingOnlyPointsAtTheVerifier(t *testing.T) {
	srv, _ := sequenceServer(t, [2]string{"200", `{"revision_id":8,"status":"failed","settled":true,"codes":["E-VERIFY-MISSING"]}`})
	r := runCLI(t, srv.URL, envToken("bnc_x"), "work", "status", "8", "--wait")
	if r.exit != ExitValidation {
		t.Fatalf("exit %d", r.exit)
	}
	e := assertErrJSON(t, r.stderr, "E-VERIFY-MISSING")
	if !strings.Contains(e.Next, "--role verifier") || strings.Contains(e.Next, "fix the files") {
		t.Errorf("next = %q", e.Next)
	}
}

func TestWorkStatusErrorAndTimeoutExitSix(t *testing.T) {
	srv, _ := sequenceServer(t, [2]string{"200", `{"revision_id":8,"status":"error","settled":true}`})
	r := runCLI(t, srv.URL, envToken("bnc_x"), "work", "status", "8", "--wait")
	if r.exit != ExitServer {
		t.Fatalf("exit %d", r.exit)
	}
	assertErrJSON(t, r.stderr, "E-VALIDATION-ERROR")

	slow, _ := sequenceServer(t, [2]string{"200", `{"revision_id":8,"status":"validating","settled":false,"queue_ahead":5}`})
	r = runCLI(t, slow.URL, envToken("bnc_x"), "work", "status", "8", "--wait", "--timeout", "0")
	if r.exit != ExitServer {
		t.Fatalf("timeout exit %d", r.exit)
	}
	assertErrJSON(t, r.stderr, "E-TIMEOUT")
	if !strings.Contains(r.stderr, "5 older revisions are still queued") {
		t.Fatalf("the timeout does not say how many are queued: %s", r.stderr)
	}
}

func TestWorkStatusWithoutWaitJustReads(t *testing.T) {
	srv, seen := sequenceServer(t, [2]string{"200", `{"revision_id":8,"status":"failed","settled":true,"codes":["E-READ"]}`})
	r := runCLI(t, srv.URL, envToken("bnc_x"), "work", "status", "8")
	if r.exit != ExitOK || (*seen)[0].path != "/api/v1/work/revisions/8" {
		t.Fatalf("exit %d, request %+v", r.exit, (*seen)[0])
	}
	for _, args := range [][]string{{"work", "status"}, {"work", "status", "x"}} {
		if got := runCLI(t, srv.URL, envToken("bnc_x"), args...); got.exit != ExitUsage {
			t.Errorf("%v: exit %d", args, got.exit)
		}
	}
}

func TestStatusReadsTheStatus(t *testing.T) {
	srv, seen := sequenceServer(t, [2]string{"200", `{"subjects":[{"key":"math","stage":"drafting"}]}`})
	r := runCLI(t, srv.URL, envToken("bnc_x"), "status", "--json")
	if r.exit != ExitOK || (*seen)[0].path != "/api/v1/status" || !strings.Contains(r.stdout, "drafting") {
		t.Fatalf("exit %d: %s %+v", r.exit, r.stderr, (*seen)[0])
	}
	if got := runCLI(t, srv.URL, envToken("bnc_x"), "status", "extra"); got.exit != ExitUsage {
		t.Errorf("exit %d", got.exit)
	}
}

func TestNoCommandApproves(t *testing.T) {
	for _, c := range commands {
		for _, word := range []string{"approve", "decision", "release", "confirm", "dispose"} {
			if strings.Contains(c.name, word) {
				t.Errorf("%q: no command takes a decision", c.name)
			}
		}
	}
}

func TestWorkSubmitDryRunRetriesBusyThenPasses(t *testing.T) {
	srv, seen := sequenceServer(t,
		[2]string{"409", `{"code":"E-CHROME-BUSY","field":"chrome","message":"Chrome is busy","next":"retry in 30 s"}`},
		[2]string{"409", `{"code":"E-CHROME-BUSY","field":"chrome","message":"Chrome is busy","next":"retry in 30 s"}`},
		[2]string{"200", `{"dry_run":true,"status":"passed","codes":[]}`})
	dir := t.TempDir()
	write(t, dir, "item.json", "{}")
	r := runCLI(t, srv.URL, envToken("bnc_x"), "work", "submit", dir, "--dry-run")
	if r.exit != 0 || len(*seen) != 3 {
		t.Errorf("exit %d after %d tries; stderr %s", r.exit, len(*seen), r.stderr)
	}
}

func TestWorkOpenReopenRemovesFilesTheRevisionDoesNotHave(t *testing.T) {
	srv, _ := sequenceServer(t, [2]string{"200", `{"revision_id":1,"files":{"item.json":"{}"}}`}, [2]string{"200", `{"revision_id":1,"files":{"item.json":"{}"}}`})
	dir := filepath.Join(t.TempDir(), "d")
	if r := runCLI(t, srv.URL, envToken("bnc_x"), "work", "open", "eq-1", "--dir", dir); r.exit != ExitOK {
		t.Fatalf("exit %d: %s", r.exit, r.stderr)
	}
	write(t, dir, "verify.mjs", "stale")
	if r := runCLI(t, srv.URL, envToken("bnc_x"), "work", "open", "eq-1", "--dir", dir); r.exit != ExitOK {
		t.Fatalf("exit %d: %s", r.exit, r.stderr)
	}
	if exists(dir, "verify.mjs") {
		t.Error("a stale verify.mjs survived the reopen")
	}
}

func TestWorkOpenDefaultsToTmpdirNotTheCurrentDirectory(t *testing.T) {
	srv, _ := sequenceServer(t, [2]string{"200", `{"item":"eq-1","revision_id":7,"seq":2,"status":"failed","files":{"item.json":"{}"},"validation":{}}`})
	tmp := t.TempDir()
	t.Setenv("TMPDIR", tmp)
	cwd := t.TempDir()
	t.Chdir(cwd)
	r := runCLI(t, srv.URL, envToken("bnc_x"), "work", "open", "eq-1", "--json")
	if r.exit != ExitOK {
		t.Fatalf("exit %d: %s", r.exit, r.stderr)
	}
	want := filepath.Join(tmp, "banco-work", "eq-1")
	if read(t, want, "item.json") != "{}" {
		t.Errorf("folder %s not written", want)
	}
	if exists(cwd, "eq-1") {
		t.Error("the current directory got a folder")
	}
}

func TestWorkOpenVerifierDefaultsToItsOwnFolderAndRefusesTheAuthors(t *testing.T) {
	srv, _ := sequenceServer(t, [2]string{"200", `{"revision_id":7,"files":{"item.json":"{}","generator.mjs":"g"}}`}, [2]string{"200", `{"revision_id":7,"files":{"item.json":"{}"}}`}, [2]string{"200", `{"revision_id":7,"files":{"item.json":"{}"}}`})
	tmp := t.TempDir()
	t.Setenv("TMPDIR", tmp)
	if r := runCLI(t, srv.URL, envToken("bnc_x"), "work", "open", "eq-1"); r.exit != ExitOK {
		t.Fatalf("exit %d: %s", r.exit, r.stderr)
	}
	if r := runCLI(t, srv.URL, envToken("bnc_x"), "work", "open", "eq-1", "--role", "verifier"); r.exit != ExitOK {
		t.Fatalf("exit %d: %s", r.exit, r.stderr)
	}
	author := filepath.Join(tmp, "banco-work", "eq-1")
	if read(t, author, "generator.mjs") != "g" {
		t.Error("the verifier open touched the author's folder")
	}
	if !exists(filepath.Join(tmp, "banco-work", "eq-1.verifier"), "item.json") {
		t.Error("the verifier folder is missing")
	}
	if r := runCLI(t, srv.URL, envToken("bnc_x"), "work", "open", "eq-1", "--role", "verifier", "--dir", author); r.exit != ExitUsage {
		t.Errorf("a verifier open into the author's folder exited %d", r.exit)
	}
}
