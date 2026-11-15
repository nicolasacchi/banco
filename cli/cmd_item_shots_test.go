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
		if s.postCode == 202 {
			_, _ = w.Write([]byte(`{"enqueued":true,"status":"queued","render_id":7}`))
		} else {
			_, _ = w.Write([]byte(`{"code":"E-AUTH","field":"authorization","message":"a bot_read token only reads","next":"x"}`))
		}
	case req.URL.Path == "/api/v1/item-revisions/12/shots":
		status := s.statuses[min(s.asked, len(s.statuses)-1)]
		s.asked++
		id := 6
		if status == "queued" || len(s.posts) > 0 {
			id = 7
		}
		if status == "passed" || status == "failed" {
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

func TestItemShotsWritesEveryInstanceWithoutRequestingWhatIsDrawn(t *testing.T) {
	srv, s := newItemShotsServer(t, 202, "failed")
	dir := filepath.Join(t.TempDir(), "figs")
	// the files of an earlier fetch of this revision go; another revision's stay
	write(t, dir, "12/instance-09_390x844.webp", "old")
	write(t, dir, "13/instance-01_390x844.webp", "other")
	res := runItemShotsCLI(t, srv.URL, "item", "shots", "12", "--dir", dir)
	if res.exit != 0 {
		t.Fatalf("item shots: exit %d, stderr %s", res.exit, res.stderr)
	}
	if len(s.posts) != 0 {
		t.Errorf("a revision that has been drawn is not asked for again: %v", s.posts)
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
