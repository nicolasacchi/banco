package main

import (
	"net/url"
	"strings"
	"testing"

	"banco/contract"
)

// D-365: banco ratings list, the student's stars and comments on exercises and lessons, read-only.

func TestRatingsListIsInTheContract(t *testing.T) {
	c, err := contract.Parse()
	if err != nil {
		t.Fatal(err)
	}
	for _, cmd := range c.Commands {
		if cmd.Name != "ratings list" {
			continue
		}
		if cmd.Local || cmd.Method == nil || cmd.Path == nil || *cmd.Method != "GET" || *cmd.Path != "/api/v1/ratings" || len(cmd.Args) != 0 ||
			strings.Join(cmd.Flags, " ") != "--subject --topic --kind --target --since --student --limit" ||
			strings.Join(cmd.ErrorCodes, " ") != "E-AUTH E-FILES E-NOT-FOUND" {
			t.Errorf("ratings list: %+v", cmd)
		}
		return
	}
	t.Error("ratings list is not in the contract")
}

func TestRatingsListQuery(t *testing.T) {
	r, seen := runTeacher(t, [][2]string{{"200", `{"ratings":[],"summaries":[]}`}}, "ratings", "list", "--subject", "math", "--topic", "ripasso.math.linear-equations-integer",
		"--kind", "item", "--target", "lin-eq-3", "--since", "2026-11-16", "--student", "prova-1", "--limit", "20", "--json")
	if r.exit != ExitOK || len(seen) != 1 {
		t.Fatalf("exit %d: %s", r.exit, r.stderr)
	}
	q, _ := url.ParseQuery(seen[0].query)
	want := url.Values{"subject": {"math"}, "topic": {"ripasso.math.linear-equations-integer"}, "kind": {"item"}, "target": {"lin-eq-3"}, "since": {"2026-11-16"},
		"student": {"prova-1"}, "limit": {"20"}}
	if seen[0].method != "GET" || seen[0].path != "/api/v1/ratings" || q.Encode() != want.Encode() {
		t.Errorf("%+v", seen[0])
	}
	if !strings.Contains(r.stdout, `"ratings"`) {
		t.Errorf("the answer is printed as the server sent it: %q", r.stdout)
	}
}

func TestRatingsListDefaultsAndTimes(t *testing.T) {
	r, seen := runTeacher(t, [][2]string{{"200", `{}`}}, "ratings", "list")
	if r.exit != ExitOK || seen[0].query != "" {
		t.Errorf("the default list sends no query: %+v", seen)
	}
	r, seen = runTeacher(t, [][2]string{{"200", `{}`}}, "ratings", "list", "--since", "2026-11-16T09:30:00+01:00", "--kind", "lesson")
	q, _ := url.ParseQuery(seen[0].query)
	if r.exit != ExitOK || q.Get("since") != "2026-11-16T09:30:00+01:00" || q.Get("kind") != "lesson" {
		t.Errorf("since is sent as given: %+v", seen)
	}
	// the flags may come before or after the command's words, as for every command
	r, seen = runTeacher(t, [][2]string{{"200", `{}`}}, "ratings", "list", "--kind", "item", "--student", "student")
	if r.exit != ExitOK || len(seen) != 1 {
		t.Fatalf("exit %d: %s", r.exit, r.stderr)
	}
}

func TestRatingsListRefusesBadValuesBeforeAnyRequest(t *testing.T) {
	for _, args := range [][]string{
		{"--kind", "page"}, {"--subject", "Math!"}, {"--topic", "equazioni"}, {"--topic", "ripasso.Math.x"}, {"--target", "Bad Key"}, {"--target", "-x"},
		{"--since", "yesterday"}, {"--since", "16/11/2026"}, {"--student", "Prova 1"}, {"--limit", "0"}, {"--limit", "501"}, {"--limit", "x"}, {"7"},
	} {
		r, seen := runTeacher(t, [][2]string{{"200", `{}`}}, append([]string{"ratings", "list"}, args...)...)
		if r.exit != ExitUsage || len(seen) != 0 {
			t.Errorf("%v: exit %d, %d requests", args, r.exit, len(seen))
		}
		if r.exit == ExitUsage {
			assertErrJSON(t, r.stderr, "E-USAGE")
		}
	}
}

func TestRatingsListServerRefusals(t *testing.T) {
	cases := []struct {
		status, body, code string
		exit               int
	}{
		{"403", `{"code":"E-AUTH","field":"authorization","message":"a agent_omp token cannot use this command: it needs a bot_read or teacher token","next":"banco schema","reason":"token_role"}`, "E-AUTH", ExitAuth},
		{"422", `{"code":"E-FILES","field":"kind","message":"kind is one of item, lesson","next":"banco ratings list"}`, "E-FILES", ExitValidation},
		{"404", `{"code":"E-NOT-FOUND","field":"subject","message":"no subject \"history\"","next":"banco status"}`, "E-NOT-FOUND", ExitValidation},
	}
	for _, c := range cases {
		r, _ := runTeacher(t, [][2]string{{c.status, c.body}}, "ratings", "list")
		if r.exit != c.exit {
			t.Errorf("%s: exit %d, want %d", c.status, r.exit, c.exit)
		}
		assertErrJSON(t, r.stderr, c.code)
	}
}
