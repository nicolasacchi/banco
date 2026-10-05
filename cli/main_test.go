package main

import (
	"bytes"
	"context"
	"encoding/json"
	"errors"
	"net/http"
	"net/http/httptest"
	"sort"
	"strings"
	"testing"
	"time"

	"banco/contract"
)

func TestCommandsMatchContract(t *testing.T) {
	c, err := contract.Parse()
	if err != nil {
		t.Fatal(err)
	}
	var fromContract, fromTable []string
	for _, cc := range c.Commands {
		fromContract = append(fromContract, cc.Name)
	}
	for _, tc := range commands {
		fromTable = append(fromTable, tc.name)
	}
	sort.Strings(fromContract)
	sort.Strings(fromTable)
	if strings.Join(fromContract, ",") != strings.Join(fromTable, ",") {
		t.Fatalf("dispatch table %v != contract %v", fromTable, fromContract)
	}
	for _, cc := range c.Commands {
		if cc.Local != (cc.Method == nil && cc.Path == nil) {
			t.Errorf("%s: local must mean no method and no path", cc.Name)
		}
	}
}

func TestContractExitCodesMatch(t *testing.T) {
	c, _ := contract.Parse()
	want := map[int]bool{ExitOK: true, ExitUsage: true, ExitValidation: true, ExitAuth: true, ExitConflict: true, ExitServer: true}
	if len(c.ExitCodes) != len(want) {
		t.Fatalf("contract lists %d exit codes, CLI has %d", len(c.ExitCodes), len(want))
	}
}

type result struct {
	exit           int
	stdout, stderr string
}

func runCLI(t *testing.T, baseURL string, tokens tokenSource, args ...string) result {
	t.Helper()
	var out, errb bytes.Buffer
	e := &env{stdout: &out, stderr: &errb, getenv: func(k string) string {
		if k == "BANCO_BUSY_WAIT_MS" {
			return "1"
		}
		return ""
	}}
	e.client = func() *client {
		return &client{baseURL: baseURL, http: &http.Client{Timeout: 5 * time.Second}, tokens: tokens}
	}
	code := runWith(args, e)
	return result{code, out.String(), errb.String()}
}

func envToken(tok string) tokenSource {
	return tokenSource{getenv: func(k string) string {
		if k == "BANCO_TOKEN" {
			return tok
		}
		return ""
	}}
}

func fakeServer(status int, body string, contractHeader string) *httptest.Server {
	return httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		if contractHeader != "" {
			w.Header().Set("X-Banco-Contract", contractHeader)
		}
		w.WriteHeader(status)
		w.Write([]byte(body))
	}))
}

func assertErrJSON(t *testing.T, stderr, code string) CLIError {
	t.Helper()
	var e CLIError
	dec := json.NewDecoder(strings.NewReader(stderr))
	dec.DisallowUnknownFields()
	if err := dec.Decode(&e); err != nil {
		t.Fatalf("stderr is not {code,field,message,next} JSON: %q (%v)", stderr, err)
	}
	if e.Code != code {
		t.Fatalf("error code = %q, want %q (stderr %q)", e.Code, code, stderr)
	}
	return e
}

func TestVersion(t *testing.T) {
	r := runCLI(t, "", envToken(""), "version")
	if r.exit != ExitOK {
		t.Fatalf("exit %d: %s", r.exit, r.stderr)
	}
	var v map[string]any
	if err := json.Unmarshal([]byte(r.stdout), &v); err != nil {
		t.Fatal(err)
	}
	if v["contract_sha256"] != contract.Digest() {
		t.Fatalf("bad digest in %v", v)
	}
}

func TestUsageErrors(t *testing.T) {
	for _, args := range [][]string{{}, {"nope"}, {"version", "extra"}, {"schema", "extra"}, {"version", "--bogus"}} {
		r := runCLI(t, "", envToken(""), args...)
		if r.exit != ExitUsage {
			t.Errorf("%v: exit %d, want %d", args, r.exit, ExitUsage)
		}
		assertErrJSON(t, r.stderr, "E-USAGE")
	}
}

func TestSchemaSuccess(t *testing.T) {
	srv := fakeServer(200, string(contract.Raw), contract.Digest())
	defer srv.Close()
	r := runCLI(t, srv.URL, envToken("bnc_x"), "schema")
	if r.exit != ExitOK {
		t.Fatalf("exit %d: %s", r.exit, r.stderr)
	}
	if strings.TrimSpace(r.stdout) != strings.TrimSpace(string(contract.Raw)) {
		t.Fatal("stdout is not the contract")
	}
}

func TestExitCodesFromStatus(t *testing.T) {
	cases := []struct {
		status int
		exit   int
	}{{401, ExitAuth}, {403, ExitAuth}, {400, ExitValidation}, {422, ExitValidation}, {409, ExitConflict}, {500, ExitServer}, {404, ExitValidation}}
	for _, c := range cases {
		srv := fakeServer(c.status, `{"code":"E-X","field":"f","message":"m","next":"n"}`, contract.Digest())
		r := runCLI(t, srv.URL, envToken("bnc_x"), "schema")
		srv.Close()
		if r.exit != c.exit {
			t.Errorf("status %d: exit %d, want %d", c.status, r.exit, c.exit)
		}
		e := assertErrJSON(t, r.stderr, "E-X")
		if e.Field != "f" || e.Next != "n" {
			t.Errorf("server error fields lost: %+v", e)
		}
	}
}

func TestNonJSONErrorBody(t *testing.T) {
	srv := fakeServer(502, "<html>bad gateway</html>", contract.Digest())
	defer srv.Close()
	r := runCLI(t, srv.URL, envToken("bnc_x"), "schema")
	if r.exit != ExitServer {
		t.Fatalf("exit %d", r.exit)
	}
	assertErrJSON(t, r.stderr, "E-HTTP-502")
}

func TestContractMismatchExitsSixWithBuildHint(t *testing.T) {
	for _, header := range []string{"deadbeef"} {
		srv := fakeServer(200, "{}", header)
		r := runCLI(t, srv.URL, envToken("bnc_x"), "schema")
		srv.Close()
		if r.exit != ExitServer {
			t.Fatalf("header %q: exit %d", header, r.exit)
		}
		e := assertErrJSON(t, r.stderr, "E-CONTRACT")
		if e.Next != "go build -o bin/banco ./cli" {
			t.Errorf("next = %q", e.Next)
		}
	}
}

func TestMissingContractHeaderIsNetworkNotContract(t *testing.T) {
	srv := fakeServer(200, "{}", "")
	defer srv.Close()
	r := runCLI(t, srv.URL, envToken("bnc_x"), "schema")
	if r.exit != ExitServer {
		t.Fatalf("exit %d", r.exit)
	}
	e := assertErrJSON(t, r.stderr, "E-NETWORK")
	if e.Next == "go build -o bin/banco ./cli" {
		t.Errorf("next must not suggest a rebuild: %q", e.Next)
	}
}

func TestNetworkFailureExitsSix(t *testing.T) {
	srv := fakeServer(200, "{}", contract.Digest())
	url := srv.URL
	srv.Close()
	r := runCLI(t, url, envToken("bnc_x"), "schema")
	if r.exit != ExitServer {
		t.Fatalf("exit %d", r.exit)
	}
	assertErrJSON(t, r.stderr, "E-NETWORK")
}

func TestTokenFromEnvNeverCallsPassCLI(t *testing.T) {
	ts := tokenSource{
		getenv: func(k string) string {
			if k == "BANCO_TOKEN" {
				return " bnc_env "
			}
			return ""
		},
		run: func(context.Context, []string, string, ...string) ([]byte, error) {
			t.Fatal("pass-cli must not run when BANCO_TOKEN is set")
			return nil, nil
		},
	}
	tok, err := ts.token("schema")
	if err != nil || tok != "bnc_env" {
		t.Fatalf("got %q, %v", tok, err)
	}
}

func TestTokenFromPassCLI(t *testing.T) {
	var gotName string
	var gotArgs, gotEnv []string
	ts := tokenSource{
		getenv: func(k string) string {
			if k == "BANCO_AGENT_KIND" {
				return "omp"
			}
			return ""
		},
		run: func(ctx context.Context, env []string, name string, args ...string) ([]byte, error) {
			if _, ok := ctx.Deadline(); !ok {
				t.Error("pass-cli call must have a timeout")
			}
			gotName, gotArgs, gotEnv = name, args, env
			return []byte("bnc_pass\n"), nil
		},
	}
	tok, err := ts.token("work open")
	if err != nil || tok != "bnc_pass" {
		t.Fatalf("got %q, %v", tok, err)
	}
	joined := strings.Join(gotArgs, " ")
	if gotName != "pass-cli" || !strings.Contains(joined, "--item-title banco-agent-omp") || !strings.Contains(joined, "--field token") {
		t.Errorf("unexpected call: %s %s", gotName, joined)
	}
	if len(gotEnv) != 1 || gotEnv[0] != "PROTON_PASS_AGENT_REASON=banco work open" {
		t.Errorf("reason env = %v", gotEnv)
	}
}

func TestTokenFailureExitsFourWithNext(t *testing.T) {
	ts := tokenSource{
		getenv: func(string) string { return "" },
		run:    func(context.Context, []string, string, ...string) ([]byte, error) { return nil, errors.New("boom") },
	}
	r := runCLI(t, "http://127.0.0.1:1", ts, "schema")
	if r.exit != ExitAuth {
		t.Fatalf("exit %d", r.exit)
	}
	e := assertErrJSON(t, r.stderr, "E-TOKEN")
	if e.Next != "pass-cli info" {
		t.Errorf("next = %q", e.Next)
	}
}

func TestFirstPositionalIsLifted(t *testing.T) {
	fs := newTestFlagSet()
	pos, err := parseFlags(fs, []string{"REV1", "--json", "REV2"})
	if err != nil {
		t.Fatal(err)
	}
	if strings.Join(pos, ",") != "REV1,REV2" {
		t.Fatalf("positionals = %v", pos)
	}
}

func TestBriefShowSuccess(t *testing.T) {
	var gotPath, gotAuth string
	srv := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		gotPath, gotAuth = r.URL.Path, r.Header.Get("Authorization")
		w.Header().Set("X-Banco-Contract", contract.Digest())
		w.Write([]byte(`{"name":"diagnosis-item","version":1,"sha256":"x","body":"b"}`))
	}))
	defer srv.Close()
	for _, args := range [][]string{{"brief", "show", "diagnosis-item", "--json"}, {"brief", "show", "--json", "diagnosis-item"}} {
		r := runCLI(t, srv.URL, envToken("bnc_x"), args...)
		if r.exit != ExitOK {
			t.Fatalf("%v: exit %d: %s", args, r.exit, r.stderr)
		}
		var b map[string]any
		if err := json.Unmarshal([]byte(r.stdout), &b); err != nil || b["version"] != float64(1) {
			t.Fatalf("stdout = %q (%v)", r.stdout, err)
		}
		if gotPath != "/api/v1/briefs/diagnosis-item" || gotAuth != "Bearer bnc_x" {
			t.Errorf("request = %s, %s", gotPath, gotAuth)
		}
	}
}

func TestBriefShowUnknownBriefExitsValidation(t *testing.T) {
	srv := fakeServer(404, `{"code":"E-BRIEF-UNKNOWN","field":"name","message":"m","next":"available: x"}`, contract.Digest())
	defer srv.Close()
	r := runCLI(t, srv.URL, envToken("bnc_x"), "brief", "show", "nope")
	if r.exit != ExitValidation {
		t.Fatalf("exit %d", r.exit)
	}
	assertErrJSON(t, r.stderr, "E-BRIEF-UNKNOWN")
}

func TestBriefShowUsage(t *testing.T) {
	for _, args := range [][]string{{"brief"}, {"brief", "show"}, {"brief", "show", "a", "b"}, {"brief", "list"}, {"brief", "show", "../../etc/passwd"}, {"brief", "show", "Bad"}} {
		r := runCLI(t, "", envToken(""), args...)
		if r.exit != ExitUsage {
			t.Errorf("%v: exit %d, want %d", args, r.exit, ExitUsage)
		}
		assertErrJSON(t, r.stderr, "E-USAGE")
	}
}

func TestBriefShowRejectsPathLikeNamesWithoutARequest(t *testing.T) {
	called := false
	srv := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		called = true
	}))
	defer srv.Close()
	r := runCLI(t, srv.URL, envToken("bnc_x"), "brief", "show", "../schema")
	if called || r.exit != ExitUsage {
		t.Errorf("called=%v exit=%d", called, r.exit)
	}
}

func TestHelpListsContractCommands(t *testing.T) {
	for _, a := range [][]string{{"--help"}, {"-h"}, {"help"}, {"work", "--help"}} {
		var out, errb bytes.Buffer
		if code := run(a, &out, &errb, func(string) string { return "" }); code != 0 {
			t.Fatalf("%s: exit %d: %s", a, code, errb.String())
		}
		if !strings.Contains(out.String(), `"skill-graph submit"`) || !strings.Contains(out.String(), `"brief show"`) {
			t.Errorf("%s: missing commands: %s", a, out.String())
		}
	}
}

func TestHelpForOneCommand(t *testing.T) {
	var out, errb bytes.Buffer
	if code := run([]string{"session", "new", "--help"}, &out, &errb, func(string) string { return "" }); code != 0 {
		t.Fatalf("exit %d: %s", code, errb.String())
	}
	for _, want := range []string{`"command":"session new"`, `"--role"`, `"error_codes"`} {
		if !strings.Contains(out.String(), want) {
			t.Errorf("missing %s: %s", want, out.String())
		}
	}
}
