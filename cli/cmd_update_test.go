package main

import (
	"bytes"
	"context"
	"crypto/sha256"
	"encoding/hex"
	"encoding/json"
	"errors"
	"fmt"
	"net/http"
	"net/http/httptest"
	"net/http/httputil"
	"net/url"
	"os"
	"path/filepath"
	"runtime"
	"strings"
	"sync/atomic"
	"testing"
	"time"

	"banco/contract"
)

// updateServer answers /api/v1/updates with a release build of one binary for this platform (sha listed as sha256 of
// listed, the bytes served are served) and serves that binary at /api/v1/cli/<name>. It counts the downloads.
func updateServer(t *testing.T, header, cliVersion string, listed, served []byte) (*httptest.Server, *atomic.Int32) {
	t.Helper()
	name := releaseName(runtime.GOOS, runtime.GOARCH)
	sum := sha256.Sum256(listed)
	downloads := &atomic.Int32{}
	updates := map[string]any{
		"server":          map[string]any{"commit": "abc123", "built_at": "2026-11-14T10:00:00Z"},
		"contract_digest": header,
		"cli": map[string]any{"version": cliVersion, "files": []map[string]any{
			{"name": name, "os": runtime.GOOS, "arch": runtime.GOARCH, "sha256": hex.EncodeToString(sum[:]), "size": len(listed)},
		}},
		"docs":    []map[string]any{{"name": "bot", "sha256": strings.Repeat("a", 64)}},
		"changes": []map[string]any{{"number": "D-330", "date": "2026-11-14", "title": "t", "status": "implemented"}},
	}
	srv := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		w.Header().Set("X-Banco-Contract", header)
		switch r.URL.Path {
		case "/api/v1/updates":
			json.NewEncoder(w).Encode(updates)
		case "/api/v1/cli/" + name:
			downloads.Add(1)
			w.Write(served)
		case "/api/v1/token":
			w.Write([]byte(`{"public_id":"AbCdEfGh","role":"bot_read","renews_on_use":true}`))
		case "/api/v1/docs/bot":
			w.Write([]byte(`{"name":"bot","sha256":"x","text":"# bot"}`))
		default:
			w.WriteHeader(404)
			w.Write([]byte(`{"code":"E-NOT-FOUND","field":"path","message":"m","next":"n"}`))
		}
	}))
	t.Cleanup(srv.Close)
	return srv, downloads
}

// runCLIExe is runCLI with the executable self-update replaces.
func runCLIExe(t *testing.T, baseURL, exe string, args ...string) result {
	t.Helper()
	var out, errb bytes.Buffer
	e := &env{stdout: &out, stderr: &errb, getenv: func(string) string { return "" },
		executable: func() (string, error) { return exe, nil }}
	e.client = func() *client {
		return &client{baseURL: baseURL, http: &http.Client{Timeout: 5 * time.Second}, tokens: envToken("bnc_x")}
	}
	code := runWith(args, e)
	return result{code, out.String(), errb.String()}
}

// fakeExe writes an "old" program into a fresh directory and returns its path.
func fakeExe(t *testing.T) string {
	t.Helper()
	exe := filepath.Join(t.TempDir(), "banco")
	if err := os.WriteFile(exe, []byte("old program"), 0o755); err != nil {
		t.Fatal(err)
	}
	return exe
}

func dirNames(t *testing.T, dir string) []string {
	t.Helper()
	entries, err := os.ReadDir(dir)
	if err != nil {
		t.Fatal(err)
	}
	var names []string
	for _, e := range entries {
		names = append(names, e.Name())
	}
	return names
}

func TestSelfUpdateReplacesTheExecutable(t *testing.T) {
	if runtime.GOOS == "windows" {
		t.Skip("on Windows the update is written beside the program (TestInstallBinaryOnWindowsWritesBeside)")
	}
	newBinary := []byte("new program v2")
	srv, downloads := updateServer(t, contract.Digest(), "9.9.9+new", newBinary, newBinary)
	exe := fakeExe(t)
	if err := os.Chmod(exe, 0o711); err != nil {
		t.Fatal(err)
	}
	r := runCLIExe(t, srv.URL, exe, "self-update")
	if r.exit != ExitOK {
		t.Fatalf("exit %d: %s", r.exit, r.stderr)
	}
	got, _ := os.ReadFile(exe)
	if !bytes.Equal(got, newBinary) {
		t.Fatalf("the executable holds %q", got)
	}
	info, _ := os.Stat(exe)
	if info.Mode().Perm() != 0o711 {
		t.Errorf("mode %v, want the old program's 0711", info.Mode().Perm())
	}
	if names := dirNames(t, filepath.Dir(exe)); len(names) != 1 {
		t.Errorf("a temporary file was left: %v", names)
	}
	var out map[string]any
	if err := json.Unmarshal([]byte(r.stdout), &out); err != nil {
		t.Fatal(err)
	}
	if out["updated"] != true || out["path"] != exe || downloads.Load() != 1 {
		t.Errorf("report %v, downloads %d", out, downloads.Load())
	}
}

func TestSelfUpdateRefusesAShaMismatchAndReplacesNothing(t *testing.T) {
	srv, _ := updateServer(t, contract.Digest(), "9.9.9+new", []byte("the listed program"), []byte("a tampered program"))
	exe := fakeExe(t)
	r := runCLIExe(t, srv.URL, exe, "self-update")
	if r.exit != ExitServer {
		t.Fatalf("exit %d: %s", r.exit, r.stderr)
	}
	e := assertErrJSON(t, r.stderr, "E-SELF-UPDATE")
	if !strings.Contains(e.Message, "nothing was replaced") {
		t.Errorf("message %q", e.Message)
	}
	got, _ := os.ReadFile(exe)
	if string(got) != "old program" {
		t.Fatalf("the executable was changed: %q", got)
	}
	if names := dirNames(t, filepath.Dir(exe)); len(names) != 1 {
		t.Errorf("a file was left beside the program: %v", names)
	}
}

func TestSelfUpdateCheckOnlyReports(t *testing.T) {
	newBinary := []byte("new program")
	srv, downloads := updateServer(t, contract.Digest(), "9.9.9+new", newBinary, newBinary)
	exe := fakeExe(t)
	r := runCLIExe(t, srv.URL, exe, "self-update", "--check")
	if r.exit != ExitOK {
		t.Fatalf("exit %d: %s", r.exit, r.stderr)
	}
	var out map[string]any
	if err := json.Unmarshal([]byte(r.stdout), &out); err != nil {
		t.Fatal(err)
	}
	if out["update_available"] != true || out["updated"] != false || out["server_cli_version"] != "9.9.9+new" || out["next"] != "banco self-update" {
		t.Errorf("report %v", out)
	}
	if downloads.Load() != 0 {
		t.Error("--check downloaded the binary")
	}
	if got, _ := os.ReadFile(exe); string(got) != "old program" {
		t.Error("--check changed the executable")
	}
}

func TestSelfUpdateDoesNothingWhenCurrent(t *testing.T) {
	srv, downloads := updateServer(t, contract.Digest(), version, []byte("x"), []byte("x"))
	exe := fakeExe(t)
	r := runCLIExe(t, srv.URL, exe, "self-update")
	if r.exit != ExitOK {
		t.Fatalf("exit %d: %s", r.exit, r.stderr)
	}
	if !strings.Contains(r.stdout, `"update_available":false`) || !strings.Contains(r.stdout, `"updated":false`) || downloads.Load() != 0 {
		t.Errorf("stdout %s, downloads %d", r.stdout, downloads.Load())
	}
}

func TestSelfUpdateWithoutAReleaseBuildForThisPlatform(t *testing.T) {
	srv := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		w.Header().Set("X-Banco-Contract", "deadbeef")
		w.Write([]byte(`{"server":{"commit":"c"},"contract_digest":"deadbeef","cli":{"version":null,"files":[]},"docs":[],"changes":[]}`))
	}))
	defer srv.Close()
	exe := fakeExe(t)
	r := runCLIExe(t, srv.URL, exe, "self-update")
	if r.exit != ExitValidation {
		t.Fatalf("exit %d: %s", r.exit, r.stderr)
	}
	assertErrJSON(t, r.stderr, "E-NOT-FOUND")
	if got, _ := os.ReadFile(exe); string(got) != "old program" {
		t.Error("the executable was changed")
	}
}

// The four commands of D-330 answer when the server's contract differs; every other command still refuses it.
func TestStayingCurrentCommandsAreExemptFromContractDrift(t *testing.T) {
	newBinary := []byte("new program")
	srv, _ := updateServer(t, "deadbeef", "9.9.9+new", newBinary, newBinary)
	for _, args := range [][]string{{"token"}, {"changes", "--since", "D-327"}, {"docs", "show", "bot"}, {"self-update", "--check"}} {
		r := runCLI(t, srv.URL, envToken("bnc_x"), args...)
		if r.exit != ExitOK {
			t.Errorf("%v: exit %d: %s", args, r.exit, r.stderr)
		}
	}
	r := runCLI(t, srv.URL, envToken("bnc_x"), "self-update", "--check")
	if !strings.Contains(r.stdout, `"update_available":true`) {
		t.Errorf("a different contract is an update: %s", r.stdout)
	}
	r = runCLI(t, srv.URL, envToken("bnc_x"), "teacher", "home")
	if r.exit != ExitServer {
		t.Fatalf("teacher home: exit %d", r.exit)
	}
	if e := assertErrJSON(t, r.stderr, "E-CONTRACT"); e.Next != "banco self-update" {
		t.Errorf("next = %q", e.Next)
	}
}

func TestChangesPassesSinceAndPrintsTheRows(t *testing.T) {
	var query string
	srv := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		query = r.URL.RawQuery
		w.Header().Set("X-Banco-Contract", contract.Digest())
		w.Write([]byte(`{"server":{"commit":"c1"},"contract_digest":"x","cli":{"files":[]},"docs":[],"changes":[{"number":"D-330"}]}`))
	}))
	defer srv.Close()
	r := runCLI(t, srv.URL, envToken("bnc_x"), "changes", "--since", "D-329")
	if r.exit != ExitOK {
		t.Fatalf("exit %d: %s", r.exit, r.stderr)
	}
	if query != "since=D-329" {
		t.Errorf("query %q", query)
	}
	var out struct {
		Since   string            `json:"since"`
		Commit  string            `json:"server_commit"`
		Changes []json.RawMessage `json:"changes"`
	}
	if err := json.Unmarshal([]byte(r.stdout), &out); err != nil || out.Since != "D-329" || out.Commit != "c1" || len(out.Changes) != 1 {
		t.Errorf("stdout %s (%v)", r.stdout, err)
	}
}

func TestStayingCurrentUsageErrorsSendNothing(t *testing.T) {
	var hits atomic.Int32
	srv := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) { hits.Add(1) }))
	defer srv.Close()
	for _, args := range [][]string{{"docs", "show"}, {"docs", "show", "decisions"}, {"docs", "show", "../api"}, {"changes", "--since", "327"},
		{"changes", "--since", "D-1"}, {"token", "x"}, {"self-update", "now"}} {
		r := runCLI(t, srv.URL, envToken("bnc_x"), args...)
		if r.exit != ExitUsage {
			t.Errorf("%v: exit %d", args, r.exit)
		}
		assertErrJSON(t, r.stderr, "E-USAGE")
	}
	if hits.Load() != 0 {
		t.Errorf("%d requests sent", hits.Load())
	}
}

// The same HTTPS rule as every command: the token never crosses a network in clear.
func TestSelfUpdateRefusesHTTPOffLoopback(t *testing.T) {
	var out, errb bytes.Buffer
	code := run([]string{"self-update", "--check"}, &out, &errb, func(k string) string {
		return map[string]string{"BANCO_URL": "http://api.example.org", "BANCO_TOKEN": "bnc_x"}[k]
	})
	if code != ExitUsage {
		t.Fatalf("exit %d: %s", code, errb.String())
	}
	assertErrJSON(t, errb.String(), "E-URL")
}

// listedAs is the server's line for data.
func listedAs(name string, data []byte) cliFile {
	sum := sha256.Sum256(data)
	return cliFile{Name: name, SHA256: hex.EncodeToString(sum[:]), Size: int64(len(data))}
}

func TestInstallBinaryOnWindowsWritesBeside(t *testing.T) {
	dir := t.TempDir()
	exe := filepath.Join(dir, "banco.exe")
	if err := os.WriteFile(exe, []byte("old"), 0o755); err != nil {
		t.Fatal(err)
	}
	target, err := installBinary(exe, strings.NewReader("new"), listedAs("banco-windows-amd64.exe", []byte("new")), "windows")
	if err != nil {
		t.Fatal(err)
	}
	if target != filepath.Join(dir, "banco.new.exe") {
		t.Errorf("target %s", target)
	}
	if got, _ := os.ReadFile(target); string(got) != "new" {
		t.Errorf("banco.new.exe holds %q", got)
	}
	if got, _ := os.ReadFile(exe); string(got) != "old" {
		t.Errorf("banco.exe was changed: %q", got)
	}
	if names := dirNames(t, dir); fmt.Sprint(names) != "[banco.exe banco.new.exe]" {
		t.Errorf("files %v", names)
	}
}

// On Windows the program is not replaced: the report says staged, never updated.
func TestWindowsReportSaysStagedNotUpdated(t *testing.T) {
	report := map[string]any{"updated": false}
	finishReport(report, `C:\bin\banco.new.exe`, `C:\bin\banco.exe`, "windows")
	if report["staged"] != true || report["updated"] != false || report["path"] != `C:\bin\banco.new.exe` {
		t.Errorf("report %v", report)
	}
	report = map[string]any{"updated": false}
	finishReport(report, "/usr/local/bin/banco", "/usr/local/bin/banco", "linux")
	if report["updated"] != true || report["staged"] != nil {
		t.Errorf("report %v", report)
	}
}

func TestInstallBinaryLeavesNothingWhenItCannotWrite(t *testing.T) {
	if runtime.GOOS == "windows" || os.Geteuid() == 0 {
		t.Skip("needs a directory the user cannot write")
	}
	dir := t.TempDir()
	exe := filepath.Join(dir, "banco")
	if err := os.WriteFile(exe, []byte("old"), 0o755); err != nil {
		t.Fatal(err)
	}
	if err := os.Chmod(dir, 0o555); err != nil {
		t.Fatal(err)
	}
	defer os.Chmod(dir, 0o755)
	if _, err := installBinary(exe, strings.NewReader("new"), listedAs("banco", []byte("new")), runtime.GOOS); err == nil {
		t.Fatal("wrote into a read-only directory")
	}
	if got, _ := os.ReadFile(exe); string(got) != "old" {
		t.Errorf("the executable was changed: %q", got)
	}
}

// endless is a download that never ends.
type endless struct{ read int64 }

func (e *endless) Read(p []byte) (int, error) {
	for i := range p {
		p[i] = 'x'
	}
	e.read += int64(len(p))
	return len(p), nil
}

// A download longer than the listed size is read only to size+1 bytes and refused; nothing is replaced or left.
func TestInstallBinaryReadsAtMostOneByteMoreThanListed(t *testing.T) {
	exe := fakeExe(t)
	src := &endless{}
	_, err := installBinary(exe, src, listedAs("banco", []byte("12345")), runtime.GOOS)
	if ce, ok := err.(*CLIError); !ok || ce.Code != "E-SELF-UPDATE" || ce.Field != "sha256" {
		t.Fatalf("err %v", err)
	}
	if src.read > 64*1024 {
		t.Errorf("read %d bytes of an endless download", src.read)
	}
	if got, _ := os.ReadFile(exe); string(got) != "old program" {
		t.Errorf("the executable was changed: %q", got)
	}
	if names := dirNames(t, filepath.Dir(exe)); len(names) != 1 {
		t.Errorf("files left: %v", names)
	}
}

// A listed size above the cap is refused before anything is downloaded.
func TestSelfUpdateRefusesAnOversizedListing(t *testing.T) {
	var downloads atomic.Int32
	name := releaseName(runtime.GOOS, runtime.GOARCH)
	srv := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		w.Header().Set("X-Banco-Contract", "deadbeef")
		if r.URL.Path != "/api/v1/updates" {
			downloads.Add(1)
			return
		}
		fmt.Fprintf(w, `{"server":{"commit":"c"},"contract_digest":"deadbeef","cli":{"version":"9","files":[{"name":%q,"sha256":"%s","size":%d}]},"docs":[],"changes":[]}`,
			name, strings.Repeat("a", 64), int64(maxBinarySize)+1)
	}))
	defer srv.Close()
	exe := fakeExe(t)
	r := runCLIExe(t, srv.URL, exe, "self-update")
	if r.exit != ExitServer {
		t.Fatalf("exit %d: %s", r.exit, r.stderr)
	}
	if e := assertErrJSON(t, r.stderr, "E-SELF-UPDATE"); e.Field != "size" {
		t.Errorf("field %q", e.Field)
	}
	if downloads.Load() != 0 {
		t.Error("downloaded an oversized binary")
	}
}

// No request follows a redirect: the token never reaches another address (Go forwards Authorization to the same host
// on another scheme or port). Both the CLI's own client and any client a caller hands in.
func TestRedirectsAreNeverFollowed(t *testing.T) {
	var elsewhere atomic.Int32
	other := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		elsewhere.Add(1)
		w.Header().Set("X-Banco-Contract", contract.Digest())
		w.Write([]byte(`{}`))
	}))
	defer other.Close()
	srv := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		http.Redirect(w, r, other.URL+r.URL.Path, http.StatusFound)
	}))
	defer srv.Close()

	t.Setenv("BANCO_TOKEN", "bnc_x") // the CLI's own token source reads the process environment
	var out, errb bytes.Buffer
	code := run([]string{"status"}, &out, &errb, func(k string) string {
		return map[string]string{"BANCO_URL": srv.URL, "BANCO_TOKEN": "bnc_x"}[k]
	})
	if code != ExitServer {
		t.Fatalf("exit %d: %s", code, errb.String())
	}
	if e := assertErrJSON(t, errb.String(), "E-NETWORK"); !strings.Contains(e.Message, "redirect") {
		t.Errorf("message %q", e.Message)
	}
	r := runCLI(t, srv.URL, envToken("bnc_x"), "self-update", "--check")
	if r.exit != ExitServer {
		t.Fatalf("exit %d: %s", r.exit, r.stderr)
	}
	assertErrJSON(t, r.stderr, "E-NETWORK")
	if elsewhere.Load() != 0 {
		t.Errorf("a redirect was followed %d times", elsewhere.Load())
	}
}

// D-333: changes, changes show, docs show and self-update work with no token and send none.

// authRequest is what a server saw of one request, with its Authorization header.
type authRequest struct{ method, path, query, auth string }

// authServer answers every request with (status, body) and the contract header, and records what came in.
func authServer(t *testing.T, status int, body string) (*httptest.Server, *[]authRequest) {
	t.Helper()
	var seen []authRequest
	srv := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		seen = append(seen, authRequest{r.Method, r.URL.Path, r.URL.RawQuery, r.Header.Get("Authorization")})
		w.Header().Set("X-Banco-Contract", contract.Digest())
		w.WriteHeader(status)
		w.Write([]byte(body))
	}))
	t.Cleanup(srv.Close)
	return srv, &seen
}

// noTokenAnywhere is a token source with neither BANCO_TOKEN nor a working pass-cli: any command that asks it fails
// with E-TOKEN.
func noTokenAnywhere() tokenSource {
	return tokenSource{
		getenv: func(string) string { return "" },
		run: func(context.Context, []string, string, ...string) ([]byte, error) {
			return nil, errors.New("no pass-cli")
		},
	}
}

// runCLINoToken is runCLIExe on a machine with no token.
func runCLINoToken(t *testing.T, baseURL, exe string, args ...string) result {
	t.Helper()
	var out, errb bytes.Buffer
	e := &env{stdout: &out, stderr: &errb, getenv: func(string) string { return "" },
		executable: func() (string, error) { return exe, nil }}
	e.client = func() *client {
		return &client{baseURL: baseURL, http: &http.Client{Timeout: 5 * time.Second}, tokens: noTokenAnywhere()}
	}
	code := runWith(args, e)
	return result{code, out.String(), errb.String()}
}

func TestTokenlessCommandsSendNoAuthorizationAndNeedNoToken(t *testing.T) {
	const decision = `{"number":"D-332","date":"2026-11-15","title":"t","status":"implemented","text":"## D-332 · t\n\nbody\n"}`
	cases := []struct {
		args  []string
		body  string
		path  string
		query string
	}{
		{[]string{"changes"}, `{"server":{"commit":"c"},"changes":[]}`, "/api/v1/updates", ""},
		{[]string{"changes", "--since", "D-330"}, `{"server":{"commit":"c"},"changes":[]}`, "/api/v1/updates", "since=D-330"},
		{[]string{"changes", "show", "D-332"}, decision, "/api/v1/updates/decisions/D-332", ""},
		{[]string{"changes", "show", "332"}, decision, "/api/v1/updates/decisions/D-332", ""},
		{[]string{"changes", "show", "D-332", "--text"}, decision, "/api/v1/updates/decisions/D-332", ""},
		{[]string{"docs", "show", "bot"}, `{"name":"bot","sha256":"x","text":"# bot"}`, "/api/v1/docs/bot", ""},
		{[]string{"self-update", "--check"}, `{"server":{"commit":"c"},"contract_digest":"x","cli":{"version":null,"files":[]},"docs":[],"changes":[]}`, "/api/v1/updates", ""},
	}
	for _, c := range cases {
		srv, seen := authServer(t, 200, c.body)
		r := runCLINoToken(t, srv.URL, fakeExe(t), c.args...)
		if r.exit != ExitOK {
			t.Errorf("%v: exit %d: %s", c.args, r.exit, r.stderr)
			continue
		}
		if len(*seen) != 1 {
			t.Errorf("%v: %d requests", c.args, len(*seen))
			continue
		}
		got := (*seen)[0]
		if got.method != "GET" || got.path != c.path || got.query != c.query || got.auth != "" {
			t.Errorf("%v: request %+v (no Authorization header expected)", c.args, got)
		}
	}
}

// With a token in the environment the tokenless commands still send none; the commands that read student data do.
func TestTokenlessCommandsIgnoreAnExistingToken(t *testing.T) {
	srv, seen := authServer(t, 200, `{"server":{"commit":"c"},"changes":[]}`)
	r := runCLI(t, srv.URL, envToken("bnc_x"), "changes")
	if r.exit != ExitOK || len(*seen) != 1 || (*seen)[0].auth != "" {
		t.Errorf("changes: exit %d, requests %+v", r.exit, *seen)
	}
	for _, args := range [][]string{{"token"}, {"teacher", "home"}, {"next"}} {
		srv, seen := authServer(t, 200, `{"ok":true}`)
		r := runCLI(t, srv.URL, envToken("bnc_x"), args...)
		if r.exit != ExitOK || len(*seen) != 1 || (*seen)[0].auth != "Bearer bnc_x" {
			t.Errorf("%v: exit %d, requests %+v (the token must be sent)", args, r.exit, *seen)
		}
	}
}

// The commands that need a token still fail on a machine with none, before any request.
func TestOtherCommandsStillNeedAToken(t *testing.T) {
	srv, seen := authServer(t, 200, `{}`)
	for _, args := range [][]string{{"token"}, {"teacher", "home"}, {"digest"}, {"activity"}, {"view-link", "revoke", "--all"}} {
		r := runCLINoToken(t, srv.URL, fakeExe(t), args...)
		if r.exit != ExitAuth {
			t.Errorf("%v: exit %d, want %d: %s", args, r.exit, ExitAuth, r.stderr)
			continue
		}
		assertErrJSON(t, r.stderr, "E-TOKEN")
	}
	if len(*seen) != 0 {
		t.Errorf("requests %+v", *seen)
	}
}

// A whole self-update (the list and the download) on a machine with no token: neither request carries Authorization.
func TestSelfUpdateWorksWithNoTokenAndSendsNone(t *testing.T) {
	if runtime.GOOS == "windows" {
		t.Skip("on Windows the update is written beside the program")
	}
	newBinary := []byte("new program v3")
	backend, downloads := updateServer(t, contract.Digest(), "9.9.9+new", newBinary, newBinary)
	target, _ := url.Parse(backend.URL)
	var auths []string
	proxy := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		auths = append(auths, r.Method+" "+r.URL.Path+" "+r.Header.Get("Authorization"))
		httputil.NewSingleHostReverseProxy(target).ServeHTTP(w, r)
	}))
	defer proxy.Close()
	exe := fakeExe(t)
	r := runCLINoToken(t, proxy.URL, exe, "self-update")
	if r.exit != ExitOK {
		t.Fatalf("exit %d: %s", r.exit, r.stderr)
	}
	if got, _ := os.ReadFile(exe); !bytes.Equal(got, newBinary) || downloads.Load() != 1 {
		t.Fatalf("executable %q, downloads %d", got, downloads.Load())
	}
	name := releaseName(runtime.GOOS, runtime.GOARCH)
	want := []string{"GET /api/v1/updates ", "GET /api/v1/cli/" + name + " "}
	if fmt.Sprint(auths) != fmt.Sprint(want) {
		t.Errorf("requests %q, want %q (an empty Authorization)", auths, want)
	}
}

func TestChangesShowPrintsTheJSONOrOnlyTheText(t *testing.T) {
	const decision = `{"number":"D-332","date":"2026-11-15","title":"View links","status":"implemented","text":"## D-332 · View links\n\nThe body."}`
	srv, _ := authServer(t, 200, decision)
	r := runCLINoToken(t, srv.URL, fakeExe(t), "changes", "show", "D-332")
	if r.exit != ExitOK || strings.TrimSpace(r.stdout) != decision {
		t.Errorf("json: exit %d, stdout %q, stderr %s", r.exit, r.stdout, r.stderr)
	}
	r = runCLINoToken(t, srv.URL, fakeExe(t), "changes", "show", "--text", "332")
	if r.exit != ExitOK || r.stdout != "## D-332 · View links\n\nThe body.\n" {
		t.Errorf("text: exit %d, stdout %q, stderr %s", r.exit, r.stdout, r.stderr)
	}
}

func TestChangesShowUnknownNumberIsNotFound(t *testing.T) {
	srv, _ := authServer(t, 404, `{"code":"E-NOT-FOUND","field":"number","message":"no decision D-999","next":"banco changes"}`)
	r := runCLINoToken(t, srv.URL, fakeExe(t), "changes", "show", "D-999")
	if r.exit != ExitValidation {
		t.Fatalf("exit %d: %s", r.exit, r.stderr)
	}
	if e := assertErrJSON(t, r.stderr, "E-NOT-FOUND"); e.Field != "number" {
		t.Errorf("field %q", e.Field)
	}
}

func TestChangesShowUsageErrorsSendNothing(t *testing.T) {
	srv, seen := authServer(t, 200, `{}`)
	for _, args := range [][]string{{"changes", "show"}, {"changes", "show", "D-1"}, {"changes", "show", "abc"}, {"changes", "show", "../x"},
		{"changes", "show", "D-332", "D-333"}, {"changes", "show", "D-D-332"}} {
		r := runCLINoToken(t, srv.URL, fakeExe(t), args...)
		if r.exit != ExitUsage {
			t.Errorf("%v: exit %d", args, r.exit)
			continue
		}
		if e := assertErrJSON(t, r.stderr, "E-USAGE"); e.Field != "number" {
			t.Errorf("%v: field %q", args, e.Field)
		}
	}
	if len(*seen) != 0 {
		t.Errorf("requests %+v", *seen)
	}
}

// changes show stays usable when the server's contract differs (it is how a stale CLI catches up).
func TestChangesShowIsExemptFromContractDrift(t *testing.T) {
	srv := fakeServer(200, `{"number":"D-332","text":"t"}`, "deadbeef")
	defer srv.Close()
	r := runCLINoToken(t, srv.URL, fakeExe(t), "changes", "show", "D-332")
	if r.exit != ExitOK {
		t.Errorf("exit %d: %s", r.exit, r.stderr)
	}
}

// D-333: banco token warns on stderr when the token expires in under 7 days; stdout stays the server's JSON.
func TestTokenWarnsOnStderrWhenExpiringSoon(t *testing.T) {
	cases := []struct {
		name, body, warning string
	}{
		{"expiring", `{"role":"teacher","expires_at":"2026-11-18T09:30:00Z","renews_on_use":false,"expires_in_days":3,"expiring_soon":true}`,
			"warning: this token expires in 3 days (2026-11-18); ask the operator for a new one\n"},
		{"expiring and renewing", `{"role":"bot_read","expires_at":"2026-11-20T09:30:00Z","renews_on_use":true,"expires_in_days":5,"expiring_soon":true}`,
			"warning: this token expires in 5 days (2026-11-20); using it renews it\n"},
		{"not expiring", `{"role":"teacher","expires_at":"2027-02-01T09:30:00Z","renews_on_use":false,"expires_in_days":78,"expiring_soon":false}`, ""},
		{"an older server's answer", `{"role":"teacher","expires_at":"2026-11-16T09:30:00Z","renews_on_use":false}`, ""},
	}
	for _, c := range cases {
		srv, seen := sequenceServer(t, [2]string{"200", c.body})
		r := runCLI(t, srv.URL, envToken("bnc_x"), "token")
		if r.exit != ExitOK {
			t.Fatalf("%s: exit %d: %s", c.name, r.exit, r.stderr)
		}
		if r.stderr != c.warning {
			t.Errorf("%s: stderr %q, want %q", c.name, r.stderr, c.warning)
		}
		if strings.TrimSpace(r.stdout) != c.body {
			t.Errorf("%s: stdout %q", c.name, r.stdout)
		}
		if len(*seen) != 1 || (*seen)[0].method != "GET" || (*seen)[0].path != "/api/v1/token" {
			t.Errorf("%s: requests %+v", c.name, *seen)
		}
	}
}

// A refused token prints no warning, only the error.
func TestTokenErrorPrintsNoWarning(t *testing.T) {
	srv, _ := sequenceServer(t, [2]string{"401", `{"code":"E-AUTH","field":"authorization","message":"m","next":"n"}`})
	r := runCLI(t, srv.URL, envToken("bnc_x"), "token")
	if r.exit != ExitAuth || r.stdout != "" || strings.Contains(r.stderr, "warning:") {
		t.Errorf("exit %d, stdout %q, stderr %q", r.exit, r.stdout, r.stderr)
	}
}

// `banco version` also reads the server's commit from the public GET /api/v1/updates (no token), and says it when the server does not answer.
func TestVersionShowsTheServerCommit(t *testing.T) {
	srv, seen := authServer(t, 200, `{"server":{"commit":"abc123def456","built_at":"2026-11-20T10:00:00Z"},"changes":[]}`)
	r := runCLINoToken(t, srv.URL, fakeExe(t), "version")
	if r.exit != ExitOK {
		t.Fatalf("exit %d: %s", r.exit, r.stderr)
	}
	var v map[string]any
	if err := json.Unmarshal([]byte(r.stdout), &v); err != nil {
		t.Fatal(err)
	}
	if v["server_commit"] != "abc123def456" || v["server_built_at"] != "2026-11-20T10:00:00Z" || v["cli_version"] != version {
		t.Errorf("version: %v", v)
	}
	if len(*seen) != 1 || (*seen)[0].path != "/api/v1/updates" || (*seen)[0].auth != "" {
		t.Errorf("requests %+v (one public GET /api/v1/updates, no Authorization)", *seen)
	}
}

func TestVersionNamesTheCLICommitOfAReleaseBuild(t *testing.T) {
	saved := version
	t.Cleanup(func() { version = saved })
	version = "0.1.0+0123456789ab.dirty"
	srv, _ := authServer(t, 200, `{"server":{"commit":"c"},"changes":[]}`)
	r := runCLINoToken(t, srv.URL, fakeExe(t), "version")
	var v map[string]any
	if err := json.Unmarshal([]byte(r.stdout), &v); err != nil {
		t.Fatal(err)
	}
	if v["cli_commit"] != "0123456789ab.dirty" || v["cli_version"] != "0.1.0+0123456789ab.dirty" {
		t.Errorf("version: %v", v)
	}
	version = "0.1.0"
	r = runCLINoToken(t, srv.URL, fakeExe(t), "version")
	v = map[string]any{}
	_ = json.Unmarshal([]byte(r.stdout), &v)
	if _, has := v["cli_commit"]; has {
		t.Errorf("a build with no commit has no cli_commit: %v", v)
	}
}

func TestVersionStillWorksWhenTheServerDoesNotAnswer(t *testing.T) {
	srv, _ := authServer(t, 500, `{}`)
	r := runCLINoToken(t, srv.URL, fakeExe(t), "version")
	if r.exit != ExitOK {
		t.Fatalf("exit %d: %s", r.exit, r.stderr)
	}
	var v map[string]any
	if err := json.Unmarshal([]byte(r.stdout), &v); err != nil {
		t.Fatal(err)
	}
	if v["server_commit"] != nil || v["server_error"] == nil || v["contract_sha256"] != contract.Digest() {
		t.Errorf("version: %v", v)
	}
}

func TestTopicOpenSaysWhyARevisionNumberIsNotAKey(t *testing.T) {
	srv, seen := authServer(t, 200, `{}`)
	r := runCLI(t, srv.URL, envToken("bnc_x"), "topic", "open", "4855")
	if r.exit != ExitUsage || !strings.Contains(r.stderr, "revision") || len(*seen) != 0 {
		t.Errorf("exit %d, stderr %s, requests %+v", r.exit, r.stderr, *seen)
	}
}
