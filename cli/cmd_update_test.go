package main

import (
	"bytes"
	"crypto/sha256"
	"encoding/hex"
	"encoding/json"
	"fmt"
	"net/http"
	"net/http/httptest"
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
