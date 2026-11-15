package main

import (
	"strconv"
	"strings"
	"testing"

	"banco/contract"
)

// D-332: the view-link commands.

func TestViewLinkCommandsAreInTheContract(t *testing.T) {
	c, err := contract.Parse()
	if err != nil {
		t.Fatal(err)
	}
	byName := map[string]contract.Command{}
	for _, cmd := range c.Commands {
		byName[cmd.Name] = cmd
	}
	want := map[string]struct{ method, path string }{
		"view-link new":    {"POST", "/api/v1/view-links"},
		"view-link list":   {"GET", "/api/v1/view-links"},
		"view-link revoke": {"POST", "/api/v1/view-links/:id/revoke"},
		// D-333: `view-link revoke --all` is this entry (the contract gives one path per command).
		"view-link revoke-all": {"POST", "/api/v1/view-links/revoke-all"},
	}
	for name, w := range want {
		cmd, ok := byName[name]
		if !ok {
			t.Errorf("%q is not in the contract", name)
			continue
		}
		if cmd.Local || cmd.Method == nil || cmd.Path == nil || *cmd.Method != w.method || *cmd.Path != w.path {
			t.Errorf("%s: %+v", name, cmd)
		}
		if !contains(cmd.ErrorCodes, "E-AUTH") {
			t.Errorf("%s: E-AUTH missing from %v", name, cmd.ErrorCodes)
		}
	}
	if got := byName["view-link new"]; strings.Join(got.Flags, " ") != "--path --minutes" || hasFlag(got, "--confirm") {
		t.Errorf("view-link new flags %v: --path and --minutes, no --confirm", got.Flags)
	}
	if got := byName["view-link revoke"]; strings.Join(got.Args, " ") != "id" || strings.Join(got.Flags, " ") != "--all" {
		t.Errorf("view-link revoke args %v flags %v", got.Args, got.Flags)
	}
	if got := byName["view-link revoke-all"]; len(got.Args) != 0 || len(got.Flags) != 0 {
		t.Errorf("view-link revoke-all takes nothing: args %v flags %v", got.Args, got.Flags)
	}
	for _, code := range []string{"E-VIEW-DISABLED", "E-VIEW-PATH", "E-VIEW-LIMIT"} {
		if !contains(byName["view-link new"].ErrorCodes, code) {
			t.Errorf("view-link new: %s missing from %v", code, byName["view-link new"].ErrorCodes)
		}
	}
	if !contains(byName["view-link revoke"].ErrorCodes, "E-NOT-FOUND") {
		t.Errorf("view-link revoke error codes %v", byName["view-link revoke"].ErrorCodes)
	}
}

func TestViewLinkNewSendsOnlyTheFlagsGiven(t *testing.T) {
	const answer = `{"id":7,"url":"https://api.banco.scc.im/v?view_token=abc","path":"/teacher","expires_at":"2026-11-15T12:00:00Z","minutes":60}`
	cases := []struct {
		args []string
		body map[string]any
	}{
		{[]string{"view-link", "new"}, map[string]any{}},
		{[]string{"view-link", "new", "--path", "/teacher/subjects/math/course"}, map[string]any{"path": "/teacher/subjects/math/course"}},
		{[]string{"view-link", "new", "--minutes", "30"}, map[string]any{"minutes": float64(30)}},
		{[]string{"view-link", "new", "--minutes", "90", "--path", "/teacher"}, map[string]any{"path": "/teacher", "minutes": float64(90)}},
	}
	for _, c := range cases {
		r, seen := runTeacher(t, [][2]string{{"201", answer}}, c.args...)
		if r.exit != ExitOK || len(seen) != 1 {
			t.Fatalf("%v: exit %d: %s", c.args, r.exit, r.stderr)
		}
		got := seen[0]
		if got.method != "POST" || got.path != "/api/v1/view-links" || got.query != "" || got.dry != "" {
			t.Errorf("%v: request %+v", c.args, got)
		}
		if len(got.body) != len(c.body) {
			t.Errorf("%v: body %v, want %v", c.args, got.body, c.body)
		}
		for k, v := range c.body {
			if got.body[k] != v {
				t.Errorf("%v: body[%s] = %v, want %v", c.args, k, got.body[k], v)
			}
		}
		if strings.TrimSpace(r.stdout) != answer {
			t.Errorf("%v: stdout %q", c.args, r.stdout)
		}
	}
}

func TestViewLinkListIsAGet(t *testing.T) {
	const answer = `{"links":[{"id":7,"path":"/teacher","created_at":"2026-11-15T11:00:00Z","expires_at":"2026-11-15T12:00:00Z","active":true,"revoked":false,"redemptions":1}]}`
	r, seen := runTeacher(t, [][2]string{{"200", answer}}, "view-link", "list")
	if r.exit != ExitOK || len(seen) != 1 {
		t.Fatalf("exit %d: %s", r.exit, r.stderr)
	}
	if seen[0].method != "GET" || seen[0].path != "/api/v1/view-links" || seen[0].query != "" || len(seen[0].body) != 0 {
		t.Errorf("request %+v", seen[0])
	}
	if strings.TrimSpace(r.stdout) != answer {
		t.Errorf("stdout %q", r.stdout)
	}
}

func TestViewLinkRevokePostsToTheLink(t *testing.T) {
	const answer = `{"id":7,"revoked":true,"revoked_at":"2026-11-15T11:30:00Z"}`
	r, seen := runTeacher(t, [][2]string{{"200", answer}}, "view-link", "revoke", "7")
	if r.exit != ExitOK || len(seen) != 1 {
		t.Fatalf("exit %d: %s", r.exit, r.stderr)
	}
	if seen[0].method != "POST" || seen[0].path != "/api/v1/view-links/7/revoke" || seen[0].query != "" || seen[0].dry != "" {
		t.Errorf("request %+v", seen[0])
	}
	if strings.TrimSpace(r.stdout) != answer {
		t.Errorf("stdout %q", r.stdout)
	}
}

// D-333: --all ends every active link of the token, through POST /api/v1/view-links/revoke-all; so does the command
// view-link revoke-all of the contract.
func TestViewLinkRevokeAllPostsOnce(t *testing.T) {
	const answer = `{"revoked":[7,9],"count":2}`
	for _, args := range [][]string{{"view-link", "revoke", "--all"}, {"view-link", "revoke-all"}} {
		r, seen := runTeacher(t, [][2]string{{"200", answer}}, args...)
		if r.exit != ExitOK || len(seen) != 1 {
			t.Fatalf("%v: exit %d: %s", args, r.exit, r.stderr)
		}
		got := seen[0]
		if got.method != "POST" || got.path != "/api/v1/view-links/revoke-all" || got.query != "" || got.dry != "" || len(got.body) != 0 {
			t.Errorf("%v: request %+v", args, got)
		}
		if strings.TrimSpace(r.stdout) != answer {
			t.Errorf("%v: stdout %q", args, r.stdout)
		}
	}
}

// Exactly one of an id and --all: both, or neither, is a usage error and nothing is sent.
func TestViewLinkRevokeNeedsExactlyOneOfIDAndAll(t *testing.T) {
	srv, seen := sequenceServer(t, [2]string{"200", `{}`})
	for _, args := range [][]string{
		{"view-link", "revoke", "7", "--all"},
		{"view-link", "revoke", "--all", "7"},
		{"view-link", "revoke"},
		{"view-link", "revoke", "--json"},
		{"view-link", "revoke-all", "7"},
		{"view-link", "revoke-all", "--all"},
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
	// The one-id form is unchanged: an id and no --all still goes to the link.
	r, got := runTeacher(t, [][2]string{{"200", `{"id":7,"revoked":true}`}}, "view-link", "revoke", "7")
	if r.exit != ExitOK || len(got) != 1 || got[0].path != "/api/v1/view-links/7/revoke" {
		t.Errorf("exit %d, requests %+v", r.exit, got)
	}
}

func TestViewLinkUsageErrorsSendNothing(t *testing.T) {
	srv, seen := sequenceServer(t, [2]string{"200", `{}`})
	for _, args := range [][]string{
		{"view-link", "new", "--minutes", "0"},
		{"view-link", "new", "--minutes", "-5"},
		{"view-link", "new", "--minutes", "abc"},
		{"view-link", "new", "--minutes", "1.5"},
		{"view-link", "new", "--minutes", ""},
		{"view-link", "new", "--path", ""},
		{"view-link", "new", "extra"},
		{"view-link", "new", "--confirm"},
		{"view-link", "list", "extra"},
		{"view-link", "revoke"},
		{"view-link", "revoke", "0"},
		{"view-link", "revoke", "-3"},
		{"view-link", "revoke", "abc"},
		{"view-link", "revoke", "7", "8"},
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

func TestViewLinkUsageErrorNamesTheField(t *testing.T) {
	srv, _ := sequenceServer(t, [2]string{"200", `{}`})
	r := runCLI(t, srv.URL, envToken("bnc_x"), "view-link", "new", "--minutes", "0")
	if e := assertErrJSON(t, r.stderr, "E-USAGE"); e.Field != "minutes" || e.Next == "" {
		t.Errorf("%+v", e)
	}
	r = runCLI(t, srv.URL, envToken("bnc_x"), "view-link", "revoke", "x")
	if e := assertErrJSON(t, r.stderr, "E-USAGE"); e.Field != "id" || e.Next == "" {
		t.Errorf("%+v", e)
	}
}

func TestViewLinkServerErrorsPassThrough(t *testing.T) {
	cases := []struct {
		status int
		body   string
		code   string
		field  string
		exit   int
		args   []string
	}{
		{503, `{"code":"E-VIEW-DISABLED","field":"view_links","message":"view links are off","next":"banco health"}`, "E-VIEW-DISABLED", "view_links", ExitServer, []string{"view-link", "new"}},
		{422, `{"code":"E-VIEW-PATH","field":"path","message":"path must be under /teacher","next":"banco view-link new --path /teacher"}`, "E-VIEW-PATH", "path", ExitValidation, []string{"view-link", "new", "--path", "/student"}},
		{422, `{"code":"E-VIEW-PATH","field":"minutes","message":"minutes must be 5..1440","next":"banco view-link new --minutes 60"}`, "E-VIEW-PATH", "minutes", ExitValidation, []string{"view-link", "new", "--minutes", "2"}},
		// banco's own 429 carries the contract header: it is not the edge's rate limit.
		{429, `{"code":"E-VIEW-LIMIT","field":"view_links","message":"20 active links","next":"banco view-link list"}`, "E-VIEW-LIMIT", "view_links", ExitServer, []string{"view-link", "new"}},
		{404, `{"code":"E-NOT-FOUND","field":"id","message":"no view link 9","next":"banco view-link list"}`, "E-NOT-FOUND", "id", ExitValidation, []string{"view-link", "revoke", "9"}},
		{403, `{"code":"E-AUTH","field":"authorization","message":"token role","reason":"token_role","next":"banco token"}`, "E-AUTH", "authorization", ExitAuth, []string{"view-link", "list"}},
	}
	for _, c := range cases {
		srv, seen := sequenceServer(t, [2]string{strconv.Itoa(c.status), c.body})
		r := runCLI(t, srv.URL, envToken("bnc_x"), c.args...)
		if r.exit != c.exit {
			t.Errorf("%v: exit %d, want %d (%s)", c.args, r.exit, c.exit, r.stderr)
		}
		e := assertErrJSON(t, r.stderr, c.code)
		if e.Field != c.field {
			t.Errorf("%v: field %q, want %q", c.args, e.Field, c.field)
		}
		if len(*seen) != 1 || r.stdout != "" {
			t.Errorf("%v: seen %d requests, stdout %q", c.args, len(*seen), r.stdout)
		}
	}
}

func TestViewLinkHelpNamesTheGroup(t *testing.T) {
	r := runCLI(t, "http://unused.invalid", envToken("bnc_x"), "view-link", "--help")
	if r.exit != ExitOK {
		t.Fatalf("exit %d: %s", r.exit, r.stderr)
	}
	for _, name := range []string{"view-link new", "view-link list", "view-link revoke", "view-link revoke-all"} {
		if !strings.Contains(r.stdout, `"`+name+`"`) {
			t.Errorf("help lacks %q: %s", name, r.stdout)
		}
	}
}
