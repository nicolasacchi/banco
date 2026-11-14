package main

import (
	"strings"
	"testing"
)

func TestTeacherViewCommandsUseTheirPath(t *testing.T) {
	cases := []struct {
		args  []string
		path  string
		query string
	}{
		{[]string{"teacher", "home"}, "/api/v1/teacher/home", ""},
		{[]string{"teacher", "home", "--student", "prova-1"}, "/api/v1/teacher/home", "student=prova-1"},
		{[]string{"teacher", "course", "geography"}, "/api/v1/teacher/subjects/geography/course", ""},
		{[]string{"teacher", "course", "--only-ready", "law_economics"}, "/api/v1/teacher/subjects/law_economics/course", "only=ready"},
		{[]string{"teacher", "topic", "geography", "ripasso.geography.europe-map"}, "/api/v1/teacher/subjects/geography/topics/ripasso.geography.europe-map", ""},
		{[]string{"teacher", "topic", "geography", "extra.geography.cartography", "--lesson"}, "/api/v1/teacher/subjects/geography/topics/extra.geography.cartography", "lesson=full"},
		{[]string{"teacher", "test", "math"}, "/api/v1/teacher/subjects/math/test", ""},
		{[]string{"progress"}, "/api/v1/students/student/progress", ""},
		{[]string{"progress", "--student", "prova-1"}, "/api/v1/students/prova-1/progress", ""},
	}
	for _, c := range cases {
		srv, seen := sequenceServer(t, [2]string{"200", `{"ok":true}`})
		r := runCLI(t, srv.URL, envToken("bnc_x"), c.args...)
		if r.exit != ExitOK {
			t.Fatalf("%v: exit %d: %s", c.args, r.exit, r.stderr)
		}
		got := (*seen)[0]
		if got.method != "GET" || got.path != c.path || got.query != c.query || got.dry != "" || got.body != nil {
			t.Errorf("%v: request %+v", c.args, got)
		}
		if strings.TrimSpace(r.stdout) != `{"ok":true}` {
			t.Errorf("%v: stdout %q", c.args, r.stdout)
		}
	}
}

func TestTeacherViewCommandsUsageErrors(t *testing.T) {
	srv, seen := sequenceServer(t, [2]string{"200", `{}`})
	for _, args := range [][]string{
		{"teacher", "home", "extra"},
		{"teacher", "home", "--student", "Prova 1"},
		{"teacher", "course"},
		{"teacher", "course", "Geography"},
		{"teacher", "course", "geography", "math"},
		{"teacher", "topic", "geography"},
		{"teacher", "topic", "geography", "not-a-topic"},
		{"teacher", "topic", "Geography", "ripasso.geography.europe-map"},
		{"teacher", "test"},
		{"teacher", "test", "../x"},
		{"progress", "extra"},
		{"progress", "--student", "A/B"},
	} {
		r := runCLI(t, srv.URL, envToken("bnc_x"), args...)
		if r.exit != ExitUsage {
			t.Errorf("%v: exit %d, want usage: %s", args, r.exit, r.stderr)
			continue
		}
		assertErrJSON(t, r.stderr, "E-USAGE")
	}
	if len(*seen) != 0 {
		t.Errorf("a usage error must not reach the server: %+v", *seen)
	}
}

func TestTeacherViewNotFoundIsAValidationExit(t *testing.T) {
	srv, _ := sequenceServer(t, [2]string{"404", `{"code":"E-NOT-FOUND","field":"subject","message":"no subject \"x\"","next":"banco status"}`})
	r := runCLI(t, srv.URL, envToken("bnc_x"), "teacher", "course", "geography")
	if r.exit != ExitValidation {
		t.Fatalf("exit %d: %s", r.exit, r.stderr)
	}
	assertErrJSON(t, r.stderr, "E-NOT-FOUND")
}

func TestRefusedTokenIsExplained(t *testing.T) {
	// A wrong, an expired and a revoked token all come back 401 E-AUTH.
	srv, _ := sequenceServer(t, [2]string{"401", `{"code":"E-AUTH","field":"authorization","message":"token missing or invalid","next":"banco schema"}`})
	r := runCLI(t, srv.URL, envToken("bnc_x"), "teacher", "home")
	if r.exit != ExitAuth {
		t.Fatalf("exit %d", r.exit)
	}
	e := assertErrJSON(t, r.stderr, "E-AUTH")
	if !strings.Contains(e.Message, "expired") || !strings.Contains(e.Message, "revoked") || !strings.Contains(e.Next, "banco:token:issue") {
		t.Errorf("the refusal must name expiry and say where to get a new token: %+v", e)
	}
}

func TestReadOnlyTokenWritingIsExplained(t *testing.T) {
	srv, seen := sequenceServer(t, [2]string{"403", `{"code":"E-AUTH","field":"authorization","message":"this token is read-only","next":"use a token with a write role","reason":"read_only_token"}`})
	file := writeTemp(t, "doc.json", `{"schema":"x"}`)
	r := runCLI(t, srv.URL, envToken("bnc_x"), "skill-graph", "submit", "--subject", "math", file)
	if r.exit != ExitAuth {
		t.Fatalf("exit %d: %s", r.exit, r.stderr)
	}
	e := assertErrJSON(t, r.stderr, "E-AUTH")
	if e.Reason != "read_only_token" || !strings.Contains(e.Message, "read-only") || !strings.Contains(e.Next, "writing role") {
		t.Errorf("%+v", e)
	}
	if len(*seen) != 1 {
		t.Errorf("requests %+v", *seen)
	}
}

func TestBaseURLForms(t *testing.T) {
	for in, want := range map[string]string{
		"":                              defaultURL,
		"https://api.banco.scc.im":      "https://api.banco.scc.im",
		"https://api.banco.scc.im/":     "https://api.banco.scc.im",
		"api.banco.scc.im":              "https://api.banco.scc.im",
		"api.banco.scc.im:8443":         "https://api.banco.scc.im:8443",
		" https://api.banco.scc.im// ":  "https://api.banco.scc.im",
		"http://127.0.0.1:3100":         "http://127.0.0.1:3100",
		"127.0.0.1:3941":                "http://127.0.0.1:3941",
		"localhost:3941":                "http://localhost:3941",
		"localhost":                     "http://localhost",
		"https://example.test/banco/":   "https://example.test/banco",
		"https://api.banco.scc.im:443/": "https://api.banco.scc.im:443",
		"https://[::1]:3100":            "https://[::1]:3100",
		"HTTPS://api.banco.scc.im":      "https://api.banco.scc.im",
		"api.banco.scc.im/banco":        "https://api.banco.scc.im/banco",
	} {
		got, err := normalizeBaseURL(in)
		if err != nil || got != want {
			t.Errorf("%q: got %q, %v; want %q", in, got, err, want)
		}
	}
	for _, in := range []string{"ftp://api.banco.scc.im", "https://", "https://u:p@api.banco.scc.im", "https://api.banco.scc.im?x=1", "https://api.banco.scc.im#f", "http://exa mple.test"} {
		if _, err := normalizeBaseURL(in); err == nil {
			t.Errorf("%q must be refused", in)
		} else if ce, ok := err.(*CLIError); !ok || ce.Code != "E-URL" || ce.exit != ExitUsage {
			t.Errorf("%q: %v", in, err)
		}
	}
}

func TestRefusedBaseURLIsReportedByTheFirstRequest(t *testing.T) {
	c := newClient(func(k string) string {
		if k == "BANCO_URL" {
			return "ftp://example.test"
		}
		return ""
	})
	c.tokens = envToken("bnc_x")
	_, err := c.do("teacher home", "GET", "/api/v1/teacher/home")
	if ce, ok := err.(*CLIError); !ok || ce.Code != "E-URL" {
		t.Fatalf("%v", err)
	}
}
