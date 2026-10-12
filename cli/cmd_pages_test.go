package main

import (
	"encoding/base64"
	"net/http"
	"net/http/httptest"
	"os"
	"path/filepath"
	"strings"
	"testing"

	"banco/contract"
)

func TestContractListsThePageCommands(t *testing.T) {
	c, err := contract.Parse()
	if err != nil {
		t.Fatal(err)
	}
	want := map[string][2]string{
		"pages list":         {"GET", "/api/v1/subjects/:subject/pages"},
		"page open":          {"GET", "/api/v1/pages/:key"},
		"page submit":        {"POST", "/api/v1/pages/submit"},
		"page status":        {"GET", "/api/v1/page-revisions/:revision"},
		"page shots":         {"GET", "/api/v1/page-revisions/:revision/shots"},
		"page diff":          {"GET", "/api/v1/page-revisions/:revision/diff"},
		"page-review open":   {"GET", "/api/v1/page-revisions/:revision/review"},
		"page-review submit": {"POST", "/api/v1/page-revisions/:revision/review"},
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
		if strings.Contains(cmd.Name, "approve") || strings.Contains(cmd.Name, "decide") {
			t.Errorf("%s decides", cmd.Name)
		}
	}
	if seen != len(want) {
		t.Errorf("the contract lists %d of %d page commands", seen, len(want))
	}
}

func TestPageCommandsTakeTheirArguments(t *testing.T) {
	srv, r := recordingServer(t)
	cases := []struct {
		args   []string
		method string
		path   string
	}{
		{[]string{"pages", "list", "--subject", "math"}, "GET", "/api/v1/subjects/math/pages"},
		{[]string{"page", "status", "12"}, "GET", "/api/v1/page-revisions/12"},
		{[]string{"page", "diff", "12"}, "GET", "/api/v1/page-revisions/12/diff"},
		{[]string{"page-review", "open", "12"}, "GET", "/api/v1/page-revisions/12/review"},
	}
	for _, c := range cases {
		*r = recorded{}
		res := runCLI(t, srv.URL, envToken("tok"), c.args...)
		if res.exit != 0 || r.method != c.method || r.path != c.path {
			t.Errorf("%v: exit %d, sent %s %s, stderr %s", c.args, res.exit, r.method, r.path, res.stderr)
		}
	}
	for _, args := range [][]string{{"pages", "list"}, {"page", "status", "abc"}, {"page", "open", "Math.X"}, {"page", "submit"}, {"page-review", "submit", "12"}} {
		*r = recorded{}
		res := runCLI(t, srv.URL, envToken("tok"), args...)
		if res.exit == 0 || r.method != "" {
			t.Errorf("%v: exit %d, reached the server %q", args, res.exit, r.method)
		}
	}
}

func TestPageOpenWritesTheFolderAndSubmitReadsItBack(t *testing.T) {
	png := []byte("\x89PNG\r\n\x1a\nfake")
	var got struct{ method, path, dry, body string }
	srv := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, req *http.Request) {
		w.Header().Set("X-Banco-Contract", contract.Digest())
		w.Header().Set("Content-Type", "application/json")
		if req.Method == "GET" {
			_, _ = w.Write([]byte(`{"page":"math.demo-page","subject":"math","exists":true,"latest":{"revision_id":41,"seq":2},"files":{"page.json":"{\"key\":\"math.demo-page\"}","main.mjs":"export const a = 1\n","assets/a.png":{"base64":"` + base64.StdEncoding.EncodeToString(png) + `"}},"card":{"title_it":"Scheda"},"libs":["three"]}`))
			return
		}
		buf := make([]byte, 1<<16)
		n, _ := req.Body.Read(buf)
		got.method, got.path, got.dry, got.body = req.Method, req.URL.Path, req.Header.Get("X-Banco-Dry-Run"), string(buf[:n])
		w.WriteHeader(201)
		_, _ = w.Write([]byte(`{"page":"math.demo-page","revision_id":42,"seq":3,"replayed":false,"warnings":[]}`))
	}))
	t.Cleanup(srv.Close)
	dir := filepath.Join(t.TempDir(), "page")
	res := runCLI(t, srv.URL, envToken("tok"), "page", "open", "math.demo-page", "--dir", dir)
	if res.exit != 0 {
		t.Fatalf("page open: exit %d, stderr %s", res.exit, res.stderr)
	}
	if data, err := os.ReadFile(filepath.Join(dir, "assets/a.png")); err != nil || string(data) != string(png) {
		t.Fatalf("the image was not written back to bytes: %v %q", err, data)
	}
	if base, _ := os.ReadFile(filepath.Join(dir, ".base")); strings.TrimSpace(string(base)) != "41" {
		t.Errorf(".base = %q, want 41", base)
	}
	if card, _ := os.ReadFile(filepath.Join(dir, "CARD.md")); !strings.Contains(string(card), "Scheda") {
		t.Errorf("CARD.md = %q", card)
	}
	res = runCLI(t, srv.URL, envToken("tok"), "page", "submit", dir, "--dry-run")
	if res.exit != 0 || got.method != "POST" || got.path != "/api/v1/pages/submit" || got.dry != "1" {
		t.Fatalf("dry run: exit %d, sent %+v, stderr %s", res.exit, got, res.stderr)
	}
	for _, want := range []string{`"page":"math.demo-page"`, `"base":41`, `"main.mjs":"export const a = 1\n"`, `"base64":"` + base64.StdEncoding.EncodeToString(png) + `"`} {
		if !strings.Contains(got.body, want) {
			t.Errorf("body lacks %s: %s", want, got.body)
		}
	}
	if strings.Contains(got.body, "CARD.md") || strings.Contains(got.body, ".base") {
		t.Errorf("the card and the base file are not sent: %s", got.body)
	}
	res = runCLI(t, srv.URL, envToken("tok"), "page", "submit", dir)
	if res.exit != 0 {
		t.Fatalf("submit: exit %d, stderr %s", res.exit, res.stderr)
	}
	if base, _ := os.ReadFile(filepath.Join(dir, ".base")); strings.TrimSpace(string(base)) != "42" {
		t.Errorf(".base = %q after the submit, want 42", base)
	}
}

func TestPageShotsNamesTheFiles(t *testing.T) {
	srv := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, req *http.Request) {
		w.Header().Set("X-Banco-Contract", contract.Digest())
		if strings.HasSuffix(req.URL.Path, "/shots") {
			w.Header().Set("Content-Type", "application/json")
			_, _ = w.Write([]byte(`{"status":"passed","errors":[],"shots":[{"kind":"ready","seed_index":0,"width":1280,"available":true,"path":"/api/v1/page-revisions/7/shots/aa"},{"kind":"session","seed_index":1,"width":1280,"action":20,"available":true,"path":"/api/v1/page-revisions/7/shots/bb"},{"kind":"ready","seed_index":2,"width":390,"available":false,"path":""}]}`))
			return
		}
		_, _ = w.Write([]byte("WEBP"))
	}))
	t.Cleanup(srv.Close)
	dir := filepath.Join(t.TempDir(), "shots")
	res := runCLI(t, srv.URL, envToken("tok"), "page", "shots", "7", "--dir", dir)
	if res.exit != 0 {
		t.Fatalf("exit %d, stderr %s", res.exit, res.stderr)
	}
	for _, name := range []string{"ready_seed1_1280.webp", "session_seed2_1280_action20.webp"} {
		if _, err := os.Stat(filepath.Join(dir, name)); err != nil {
			t.Errorf("%s: %v", name, err)
		}
	}
	if !strings.Contains(res.stdout, `"removed_by_purge":1`) {
		t.Errorf("stdout: %s", res.stdout)
	}
}
