package main

import (
	"bytes"
	"encoding/json"
	"net/http"
	"net/http/httptest"
	"os"
	"path/filepath"
	"strings"
	"sync"
	"testing"
	"time"

	"banco/contract"
)

// runItemShotsCLI is runCLI with a one-millisecond poll (BANCO_POLL_MS).
func runItemShotsCLI(t *testing.T, baseURL string, args ...string) result {
	t.Helper()
	var out, errb bytes.Buffer
	e := &env{stdout: &out, stderr: &errb, getenv: func(k string) string {
		if k == "BANCO_POLL_MS" {
			return "1"
		}
		return ""
	}}
	e.client = func() *client {
		return &client{baseURL: baseURL, http: &http.Client{Timeout: 5 * time.Second}, tokens: envToken("tok")}
	}
	code := runWith(args, e)
	return result{code, out.String(), errb.String()}
}

func TestContractListsItemShots(t *testing.T) {
	c, err := contract.Parse()
	if err != nil {
		t.Fatal(err)
	}
	for _, cmd := range c.Commands {
		if cmd.Name != "item shots" {
			continue
		}
		if cmd.Local || cmd.Method == nil || cmd.Path == nil || *cmd.Method != "GET" || *cmd.Path != "/api/v1/item-revisions/:revision/shots" || cmd.ErrorCodes[0] != "E-AUTH" {
			t.Errorf("item shots: %+v", cmd)
		}
		return
	}
	t.Fatal("the contract has no item shots")
}

// itemShotsServer plays the server: the list answers a status that moves on with each ask, the POST is recorded.
type itemShotsServer struct {
	mu       sync.Mutex
	statuses []string // the status of each GET of the list, the last one repeats
	asked    int
	posts    []string // method + query of each POST
	postCode int
	sha      string
	gone     string
}

func (s *itemShotsServer) handler(w http.ResponseWriter, req *http.Request) {
	s.mu.Lock()
	defer s.mu.Unlock()
	w.Header().Set("X-Banco-Contract", contract.Digest())
	switch {
	case req.URL.Path == "/api/v1/item-revisions/12/shots" && req.Method == "POST":
		s.posts = append(s.posts, req.URL.RawQuery)
		w.WriteHeader(s.postCode)
		switch s.postCode {
		case 202:
			_, _ = w.Write([]byte(`{"enqueued":true,"status":"queued","render_id":7}`))
		case 200:
			_, _ = w.Write([]byte(`{"enqueued":false,"status":"failed","render_id":8,"why_not":"drawn under the current harness"}`))
		default:
			_, _ = w.Write([]byte(`{"code":"E-AUTH","field":"authorization","message":"a bot_read token only reads","next":"x"}`))
		}
	case req.URL.Path == "/api/v1/item-revisions/12/shots":
		status := s.statuses[min(s.asked, len(s.statuses)-1)]
		s.asked++
		id := 6
		if status == "queued" || len(s.posts) > 0 {
			id = 7
		}
		if status == "passed" || status == "failed" || status == "error" {
			id = 8
		}
		w.Header().Set("Content-Type", "application/json")
		shots := `[]`
		if status == "passed" || status == "failed" {
			shots = `[{"instance":1,"seed":"item-shots|12|1","shown_order":{"options":["o3","o1"]},"viewport":"390x844-cream","width":390,"height":912,"available":true,"path":"/api/v1/item-revisions/12/shots/` + s.sha + `"},` +
				`{"instance":2,"seed":"item-shots|12|2","shown_order":{},"viewport":"390x844-cream","width":390,"height":700,"available":true,"path":"/api/v1/item-revisions/12/shots/` + s.sha + `"},` +
				`{"instance":3,"seed":"item-shots|12|3","shown_order":{},"viewport":"390x844-cream","width":390,"height":700,"available":false,"path":"/api/v1/item-revisions/12/shots/` + s.gone + `"}]`
		}
		_, _ = w.Write([]byte(`{"revision_id":12,"status":"` + status + `","render_id":` + string(rune('0'+id)) + `,"message":"Chrome down","errors":[{"code":"E-ITEM-OVERFLOW","instance":2,"message":"wide"}],"notes":[],"instances":3,"seed_note":"n","shots":` + shots + `}`))
	case req.URL.Path == "/api/v1/item-revisions/12/shots/"+s.sha:
		w.Header().Set("Content-Type", "image/webp")
		_, _ = w.Write([]byte("RIFFxxxxWEBP"))
	default:
		w.WriteHeader(404)
	}
}

func newItemShotsServer(t *testing.T, postCode int, statuses ...string) (*httptest.Server, *itemShotsServer) {
	t.Helper()
	s := &itemShotsServer{statuses: statuses, postCode: postCode, sha: strings.Repeat("a", 64), gone: strings.Repeat("b", 64)}
	srv := httptest.NewServer(http.HandlerFunc(s.handler))
	t.Cleanup(srv.Close)
	return srv, s
}

func TestItemShotsAsksAndWritesEveryInstanceOfWhatIsDrawn(t *testing.T) {
	// the CLI always asks: the server alone knows whether a verdict is outdated; here it is current, so nothing is enqueued
	srv, s := newItemShotsServer(t, 200, "failed")
	dir := filepath.Join(t.TempDir(), "figs")
	// the files of an earlier fetch of this revision go; another revision's stay
	write(t, dir, "12/instance-09_390x844.webp", "old")
	write(t, dir, "13/instance-01_390x844.webp", "other")
	res := runItemShotsCLI(t, srv.URL, "item", "shots", "12", "--dir", dir)
	if res.exit != 0 {
		t.Fatalf("item shots: exit %d, stderr %s", res.exit, res.stderr)
	}
	if len(s.posts) != 1 || s.posts[0] != "" {
		t.Errorf("one request, not forced: %v", s.posts)
	}
	for _, name := range []string{"instance-01_390x844.webp", "instance-02_390x844.webp"} {
		if data, err := os.ReadFile(filepath.Join(dir, "12", name)); err != nil || string(data) != "RIFFxxxxWEBP" {
			t.Fatalf("%s: %v %q", name, err, data)
		}
	}
	if _, err := os.Stat(filepath.Join(dir, "12", "instance-09_390x844.webp")); err == nil {
		t.Error("an old file of this revision must go")
	}
	if b, _ := os.ReadFile(filepath.Join(dir, "13", "instance-01_390x844.webp")); string(b) != "other" {
		t.Error("another revision's file was touched")
	}
	var out struct {
		Dir     string           `json:"dir"`
		Status  string           `json:"status"`
		Removed int              `json:"removed_by_purge"`
		Files   []map[string]any `json:"files"`
	}
	if err := json.Unmarshal([]byte(res.stdout), &out); err != nil {
		t.Fatalf("stdout %q: %v", res.stdout, err)
	}
	if out.Dir != filepath.Join(dir, "12") || out.Status != "failed" || out.Removed != 1 || len(out.Files) != 2 || out.Files[0]["seed"] != "item-shots|12|1" || out.Files[0]["file"] != filepath.Join(dir, "12", "instance-01_390x844.webp") {
		t.Fatalf("answer %+v", out)
	}
	if !strings.Contains(res.stdout, `"shown_order":{"options":["o3","o1"]}`) || !strings.Contains(res.stdout, `"E-ITEM-OVERFLOW"`) {
		t.Errorf("shown_order or errors missing: %s", res.stdout)
	}
	if bad := runItemShotsCLI(t, srv.URL, "item", "shots", "abc"); bad.exit != ExitUsage {
		t.Error("a revision that is not a number must be refused")
	}
}

func TestItemShotsRequestsTheRenderAndWaitsForIt(t *testing.T) {
	srv, s := newItemShotsServer(t, 202, "none", "queued", "queued", "passed")
	dir := t.TempDir()
	res := runItemShotsCLI(t, srv.URL, "item", "shots", "12", "--dir", dir, "--wait")
	if res.exit != 0 {
		t.Fatalf("exit %d, stderr %s", res.exit, res.stderr)
	}
	if len(s.posts) != 1 || s.posts[0] != "" {
		t.Errorf("one request, not forced: %v", s.posts)
	}
	if _, err := os.Stat(filepath.Join(dir, "12", "instance-01_390x844.webp")); err != nil {
		t.Fatalf("image not written: %v", err)
	}
	if !strings.Contains(res.stdout, `"requested":true`) || !strings.Contains(res.stdout, `"enqueued":true`) {
		t.Errorf("answer: %s", res.stdout)
	}
}

func TestItemShotsAnOutdatedVerdictIsDrawnAgainAndWaitedFor(t *testing.T) {
	// the list shows a verdict, but the server enqueues a new render (the verdict was drawn under another harness): the CLI waits for the new one
	srv, s := newItemShotsServer(t, 202, "failed", "queued", "passed")
	dir := t.TempDir()
	res := runItemShotsCLI(t, srv.URL, "item", "shots", "12", "--dir", dir, "--wait", "--timeout", "5")
	if res.exit != 0 {
		t.Fatalf("exit %d, stderr %s", res.exit, res.stderr)
	}
	if len(s.posts) != 1 || s.posts[0] != "" {
		t.Errorf("one request, not forced: %v", s.posts)
	}
	if !strings.Contains(res.stdout, `"status":"passed"`) {
		t.Errorf("the new verdict, not the outdated one: %s", res.stdout)
	}
}

func TestItemShotsWithoutWaitReportsAndPrintsTheCommand(t *testing.T) {
	srv, s := newItemShotsServer(t, 202, "none")
	res := runItemShotsCLI(t, srv.URL, "item", "shots", "12", "--dir", filepath.Join(t.TempDir(), "d"))
	if res.exit != 0 || len(s.posts) != 1 {
		t.Fatalf("exit %d posts %v stderr %s", res.exit, s.posts, res.stderr)
	}
	if !strings.Contains(res.stdout, `"status":"queued"`) || !strings.Contains(res.stdout, "banco item shots 12 --dir ") || !strings.Contains(res.stdout, "--wait") {
		t.Errorf("answer: %s", res.stdout)
	}
}

func TestItemShotsForceAsksAgainAndTakesTheNewVerdict(t *testing.T) {
	srv, s := newItemShotsServer(t, 202, "passed", "queued", "passed")
	dir := t.TempDir()
	// the first list (an old verdict) is not what is wanted: the request's own render is
	res := runItemShotsCLI(t, srv.URL, "item", "shots", "12", "--dir", dir, "--wait", "--force")
	if res.exit != 0 {
		t.Fatalf("exit %d, stderr %s", res.exit, res.stderr)
	}
	if len(s.posts) != 1 || s.posts[0] != "force=1" {
		t.Errorf("forced request: %v", s.posts)
	}
	if s.asked < 3 {
		t.Errorf("waited for the new verdict, asked %d times", s.asked)
	}
}

func TestItemShotsErrorAndTimeoutAreFailures(t *testing.T) {
	srv, _ := newItemShotsServer(t, 202, "none", "error")
	res := runItemShotsCLI(t, srv.URL, "item", "shots", "12", "--dir", t.TempDir(), "--wait")
	if res.exit != ExitServer || !strings.Contains(res.stderr, "E-CHROME-UNAVAILABLE") {
		t.Fatalf("error status: exit %d stderr %s", res.exit, res.stderr)
	}
	srv2, _ := newItemShotsServer(t, 202, "queued")
	res = runItemShotsCLI(t, srv2.URL, "item", "shots", "12", "--dir", t.TempDir(), "--wait", "--timeout", "1")
	if res.exit != ExitServer || !strings.Contains(res.stderr, "E-TIMEOUT") {
		t.Fatalf("timeout: exit %d stderr %s", res.exit, res.stderr)
	}
	// the error says how to wait longer, and the default wait covers a busy Chrome lane (20 minutes)
	if !strings.Contains(res.stderr, "--timeout 2") || !strings.Contains(res.stderr, "default 1200") {
		t.Errorf("the timeout error does not say how to wait longer: %s", res.stderr)
	}
	if defaultItemShotsTimeout != 1200 {
		t.Errorf("default wait %d s, want 1200", defaultItemShotsTimeout)
	}
}

func TestItemShotsATokenThatCannotRequestFailsUnlessARenderIsPending(t *testing.T) {
	srv, _ := newItemShotsServer(t, 403, "none")
	res := runItemShotsCLI(t, srv.URL, "item", "shots", "12", "--dir", t.TempDir())
	if res.exit != ExitAuth {
		t.Fatalf("exit %d stderr %s", res.exit, res.stderr)
	}
	srv2, _ := newItemShotsServer(t, 403, "queued", "passed")
	res = runItemShotsCLI(t, srv2.URL, "item", "shots", "12", "--dir", t.TempDir(), "--wait")
	if res.exit != 0 || !strings.Contains(res.stdout, `"requested":false`) {
		t.Fatalf("a pending render is waited for: exit %d stdout %s stderr %s", res.exit, res.stdout, res.stderr)
	}
}

// A bilingual item has a second picture of instance 1 with the Italian translation open (state "tr", D-402): it is written beside the first, not over it.
func TestItemShotsTheTranslationPictureIsAFileOfItsOwn(t *testing.T) {
	sha := strings.Repeat("c", 64)
	srv := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, req *http.Request) {
		w.Header().Set("X-Banco-Contract", contract.Digest())
		switch {
		case req.Method == "POST":
			w.WriteHeader(200)
			_, _ = w.Write([]byte(`{"enqueued":false,"status":"passed","render_id":8}`))
		case req.URL.Path == "/api/v1/item-revisions/12/shots":
			_, _ = w.Write([]byte(`{"revision_id":12,"status":"passed","render_id":8,"errors":[],"notes":[],"instances":1,"seed_note":"n","shots":[` +
				`{"instance":1,"seed":"s","shown_order":{},"viewport":"390x844-cream","width":390,"height":700,"available":true,"path":"/api/v1/item-revisions/12/shots/` + sha + `"},` +
				`{"instance":1,"state":"tr","seed":"s","shown_order":{},"viewport":"390x844-cream","width":390,"height":820,"available":true,"path":"/api/v1/item-revisions/12/shots/` + sha + `"}]}`))
		default:
			_, _ = w.Write([]byte("RIFFxxxxWEBP"))
		}
	}))
	t.Cleanup(srv.Close)
	dir := t.TempDir()
	res := runItemShotsCLI(t, srv.URL, "item", "shots", "12", "--dir", dir)
	if res.exit != 0 {
		t.Fatalf("item shots: exit %d, stderr %s", res.exit, res.stderr)
	}
	for _, name := range []string{"instance-01_390x844.webp", "instance-01-tr_390x844.webp"} {
		if _, err := os.Stat(filepath.Join(dir, "12", name)); err != nil {
			t.Errorf("%s: %v", name, err)
		}
	}
	if !strings.Contains(res.stdout, `"state":"tr"`) {
		t.Errorf("the file entry of the translation picture says its state: %s", res.stdout)
	}
}

// The listing says which picture is which: the one as drawn has no state, the one with the translation open says "tr", and both files exist for instance 1
// (the file of the second is never the first's name). The list the server sends is the one the CLI saves, in order.
func TestItemShotsListingNamesTheStateOfEachFile(t *testing.T) {
	sha := strings.Repeat("d", 64)
	srv := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, req *http.Request) {
		w.Header().Set("X-Banco-Contract", contract.Digest())
		switch {
		case req.Method == "POST":
			_, _ = w.Write([]byte(`{"enqueued":false,"status":"passed","render_id":8}`))
		case req.URL.Path == "/api/v1/item-revisions/12/shots":
			_, _ = w.Write([]byte(`{"revision_id":12,"status":"passed","render_id":8,"errors":[],"notes":[],"instances":2,"seed_note":"n","shots":[` +
				`{"instance":1,"seed":"s1","shown_order":{},"viewport":"390x844-cream","width":390,"height":700,"available":true,"path":"/api/v1/item-revisions/12/shots/` + sha + `"},` +
				`{"instance":1,"state":"tr","seed":"s1","shown_order":{},"viewport":"390x844-cream","width":390,"height":820,"available":true,"path":"/api/v1/item-revisions/12/shots/` + sha + `"},` +
				`{"instance":2,"seed":"s2","shown_order":{},"viewport":"390x844-cream","width":390,"height":700,"available":true,"path":"/api/v1/item-revisions/12/shots/` + sha + `"}]}`))
		default:
			_, _ = w.Write([]byte("RIFFxxxxWEBP"))
		}
	}))
	t.Cleanup(srv.Close)
	dir := t.TempDir()
	// a picture of an earlier fetch goes, the -tr one too
	write(t, dir, "12/instance-01-tr_390x844.webp", "old")
	res := runItemShotsCLI(t, srv.URL, "item", "shots", "12", "--dir", dir)
	if res.exit != 0 {
		t.Fatalf("item shots: exit %d, stderr %s", res.exit, res.stderr)
	}
	var out struct {
		Files []map[string]any `json:"files"`
	}
	if err := json.Unmarshal([]byte(res.stdout), &out); err != nil {
		t.Fatalf("stdout %q: %v", res.stdout, err)
	}
	type entry struct {
		instance float64
		file     string
		state    any
	}
	var got []entry
	for _, f := range out.Files {
		got = append(got, entry{f["instance"].(float64), filepath.Base(f["file"].(string)), f["state"]})
	}
	want := []entry{{1, "instance-01_390x844.webp", nil}, {1, "instance-01-tr_390x844.webp", "tr"}, {2, "instance-02_390x844.webp", nil}}
	if len(got) != len(want) {
		t.Fatalf("files %+v", got)
	}
	for i := range want {
		if got[i] != want[i] {
			t.Errorf("file %d: got %+v, want %+v", i, got[i], want[i])
		}
	}
	for _, e := range want {
		if _, err := os.Stat(filepath.Join(dir, "12", e.file)); err != nil {
			t.Errorf("%s: %v", e.file, err)
		}
	}
}

// Two pictures that would be the same file (the server listed instance 1 twice with no state) are an error, not a silent overwrite.
func TestItemShotsRefusesTwoPicturesForOneFile(t *testing.T) {
	sha := strings.Repeat("e", 64)
	srv := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, req *http.Request) {
		w.Header().Set("X-Banco-Contract", contract.Digest())
		switch {
		case req.Method == "POST":
			_, _ = w.Write([]byte(`{"enqueued":false,"status":"passed","render_id":8}`))
		case req.URL.Path == "/api/v1/item-revisions/12/shots":
			shot := `{"instance":1,"seed":"s","shown_order":{},"viewport":"390x844-cream","width":390,"height":700,"available":true,"path":"/api/v1/item-revisions/12/shots/` + sha + `"}`
			_, _ = w.Write([]byte(`{"revision_id":12,"status":"passed","render_id":8,"errors":[],"notes":[],"instances":1,"seed_note":"n","shots":[` + shot + `,` + shot + `]}`))
		default:
			_, _ = w.Write([]byte("RIFFxxxxWEBP"))
		}
	}))
	t.Cleanup(srv.Close)
	res := runItemShotsCLI(t, srv.URL, "item", "shots", "12", "--dir", t.TempDir())
	if res.exit == 0 || !strings.Contains(res.stderr, "instance-01_390x844.webp") {
		t.Errorf("exit %d, stderr %s", res.exit, res.stderr)
	}
}
