package main

import (
	"net/url"
	"reflect"
	"strings"
	"testing"

	"banco/contract"
)

// D-333 and D-334: next, digest and activity.

func TestBotCommandsAreInTheContract(t *testing.T) {
	c, err := contract.Parse()
	if err != nil {
		t.Fatal(err)
	}
	byName := map[string]contract.Command{}
	for _, cmd := range c.Commands {
		byName[cmd.Name] = cmd
	}
	want := map[string]struct {
		path  string
		flags string
		codes string
	}{
		"next":     {"/api/v1/students/:student/next", "--student --subject", "E-AUTH E-NOT-FOUND"},
		"digest":   {"/api/v1/digest", "--student", "E-AUTH E-NOT-FOUND"},
		"activity": {"/api/v1/activity", "--since --actor --limit", "E-AUTH E-FILES"},
	}
	for name, w := range want {
		cmd, ok := byName[name]
		if !ok {
			t.Errorf("%q is not in the contract", name)
			continue
		}
		if cmd.Local || cmd.Method == nil || cmd.Path == nil || *cmd.Method != "GET" || *cmd.Path != w.path ||
			len(cmd.Args) != 0 || strings.Join(cmd.Flags, " ") != w.flags || strings.Join(cmd.ErrorCodes, " ") != w.codes {
			t.Errorf("%s: %+v", name, cmd)
		}
	}
	// The tokenless commands list no E-AUTH: the server never reads Authorization for them.
	for _, name := range []string{"changes", "changes show", "docs show", "self-update"} {
		cmd, ok := byName[name]
		if !ok {
			t.Errorf("%q is not in the contract", name)
			continue
		}
		if contains(cmd.ErrorCodes, "E-AUTH") || !tokenless[name] || !contractExempt[name] {
			t.Errorf("%s: error codes %v, tokenless %v, exempt %v", name, cmd.ErrorCodes, tokenless[name], contractExempt[name])
		}
	}
	if got := byName["changes show"]; got.Method == nil || *got.Method != "GET" || *got.Path != "/api/v1/updates/decisions/:number" ||
		strings.Join(got.Args, " ") != "number" || strings.Join(got.Flags, " ") != "--text" {
		t.Errorf("changes show: %+v", got)
	}
	if tokenless["token"] || !contractExempt["token"] {
		t.Error("token needs its token and is exempt from contract drift")
	}
}

func TestNextDigestActivityRequests(t *testing.T) {
	cases := []struct {
		args  []string
		path  string
		query url.Values
	}{
		{[]string{"next"}, "/api/v1/students/student/next", url.Values{}},
		{[]string{"next", "--subject", "math"}, "/api/v1/students/student/next", url.Values{"subject": {"math"}}},
		{[]string{"next", "--student", "prova-1", "--subject", "law_economics"}, "/api/v1/students/prova-1/next", url.Values{"subject": {"law_economics"}}},
		{[]string{"digest"}, "/api/v1/digest", url.Values{"student": {"student"}}},
		{[]string{"digest", "--student", "prova-1"}, "/api/v1/digest", url.Values{"student": {"prova-1"}}},
		{[]string{"activity"}, "/api/v1/activity", url.Values{}},
		{[]string{"activity", "--actor", "silvia@scc.im"}, "/api/v1/activity", url.Values{"actor": {"silvia@scc.im"}}},
		{[]string{"activity", "--limit", "20"}, "/api/v1/activity", url.Values{"limit": {"20"}}},
		{[]string{"activity", "--limit", "200"}, "/api/v1/activity", url.Values{"limit": {"200"}}},
		// A date is the UTC midnight; an ISO time passes as it is (in UTC).
		{[]string{"activity", "--since", "2026-11-15"}, "/api/v1/activity", url.Values{"since": {"2026-11-15T00:00:00Z"}}},
		{[]string{"activity", "--since", "2026-11-15T09:30:00Z"}, "/api/v1/activity", url.Values{"since": {"2026-11-15T09:30:00Z"}}},
		{[]string{"activity", "--since", "2026-11-15T10:30:00+01:00"}, "/api/v1/activity", url.Values{"since": {"2026-11-15T09:30:00Z"}}},
		{[]string{"activity", "--since", "2026-11-01", "--actor", "nik", "--limit", "5"}, "/api/v1/activity",
			url.Values{"since": {"2026-11-01T00:00:00Z"}, "actor": {"nik"}, "limit": {"5"}}},
	}
	for _, c := range cases {
		srv, seen := sequenceServer(t, [2]string{"200", `{"ok":true}`})
		r := runCLI(t, srv.URL, envToken("bnc_x"), c.args...)
		if r.exit != ExitOK || len(*seen) != 1 {
			t.Fatalf("%v: exit %d: %s", c.args, r.exit, r.stderr)
		}
		got := (*seen)[0]
		query, err := url.ParseQuery(got.query)
		if err != nil {
			t.Fatal(err)
		}
		if got.method != "GET" || got.path != c.path || got.dry != "" || got.body != nil || !reflect.DeepEqual(query, c.query) {
			t.Errorf("%v: request %+v (query %v, want %v)", c.args, got, query, c.query)
		}
		if strings.TrimSpace(r.stdout) != `{"ok":true}` {
			t.Errorf("%v: stdout %q", c.args, r.stdout)
		}
	}
}

func TestNextDigestActivityUsageErrorsSendNothing(t *testing.T) {
	srv, seen := sequenceServer(t, [2]string{"200", `{}`})
	for _, args := range [][]string{
		{"next", "extra"},
		{"next", "--student", "A/B"},
		{"next", "--subject", "Math"},
		{"next", "--subject", "../x"},
		{"digest", "extra"},
		{"digest", "--student", "Prova 1"},
		{"activity", "extra"},
		{"activity", "--since", "yesterday"},
		{"activity", "--since", "15/11/2026"},
		{"activity", "--since", ""},
		{"activity", "--actor", ""},
		{"activity", "--actor", "  "},
		{"activity", "--limit", "0"},
		{"activity", "--limit", "201"},
		{"activity", "--limit", "-1"},
		{"activity", "--limit", "abc"},
		{"activity", "--limit", ""},
	} {
		r := runCLI(t, srv.URL, envToken("bnc_x"), args...)
		if r.exit != ExitUsage {
			t.Errorf("%v: exit %d, want %d (%s)", args, r.exit, ExitUsage, r.stderr)
			continue
		}
		assertErrJSON(t, r.stderr, "E-USAGE")
	}
	if len(*seen) != 0 {
		t.Errorf("a usage error must not reach the server: %+v", *seen)
	}
}

func TestActivityUsageErrorNamesTheField(t *testing.T) {
	srv, _ := sequenceServer(t, [2]string{"200", `{}`})
	for flag, value := range map[string]string{"since": "soon", "limit": "500", "actor": ""} {
		r := runCLI(t, srv.URL, envToken("bnc_x"), "activity", "--"+flag, value)
		if e := assertErrJSON(t, r.stderr, "E-USAGE"); e.Field != flag || e.Next == "" {
			t.Errorf("--%s: %+v", flag, e)
		}
	}
}

func TestNextDigestActivityServerErrorsPassThrough(t *testing.T) {
	cases := []struct {
		args  []string
		body  string
		code  string
		field string
		exit  int
		http  string
	}{
		{[]string{"next", "--student", "nessuno"}, `{"code":"E-NOT-FOUND","field":"student","message":"no student","next":"banco status"}`, "E-NOT-FOUND", "student", ExitValidation, "404"},
		{[]string{"digest"}, `{"code":"E-AUTH","field":"authorization","message":"token role","reason":"token_role","next":"banco token"}`, "E-AUTH", "authorization", ExitAuth, "403"},
		{[]string{"activity", "--limit", "10"}, `{"code":"E-FILES","field":"since","message":"bad since","next":"banco activity"}`, "E-FILES", "since", ExitValidation, "422"},
	}
	for _, c := range cases {
		srv, seen := sequenceServer(t, [2]string{c.http, c.body})
		r := runCLI(t, srv.URL, envToken("bnc_x"), c.args...)
		if r.exit != c.exit {
			t.Errorf("%v: exit %d, want %d (%s)", c.args, r.exit, c.exit, r.stderr)
		}
		if e := assertErrJSON(t, r.stderr, c.code); e.Field != c.field {
			t.Errorf("%v: field %q, want %q", c.args, e.Field, c.field)
		}
		if len(*seen) != 1 || r.stdout != "" {
			t.Errorf("%v: seen %d requests, stdout %q", c.args, len(*seen), r.stdout)
		}
	}
}

func TestBotCommandsAppearInHelp(t *testing.T) {
	r := runCLI(t, "http://unused.invalid", envToken("bnc_x"), "--help")
	if r.exit != ExitOK {
		t.Fatalf("exit %d: %s", r.exit, r.stderr)
	}
	for _, name := range []string{"next", "digest", "activity", "changes show", "view-link revoke-all"} {
		if !strings.Contains(r.stdout, `"name":"`+name+`"`) {
			t.Errorf("help lacks %q", name)
		}
	}
}
