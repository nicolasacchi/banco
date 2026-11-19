package main

import (
	"net/url"
	"strings"
	"testing"

	"banco/contract"
)

// D-375: banco changelog, what changed for the student and the teacher, read-only, for every token role.

func TestChangelogIsInTheContract(t *testing.T) {
	c, err := contract.Parse()
	if err != nil {
		t.Fatal(err)
	}
	for _, cmd := range c.Commands {
		if cmd.Name != "changelog" {
			continue
		}
		if cmd.Local || cmd.Method == nil || cmd.Path == nil || *cmd.Method != "GET" || *cmd.Path != "/api/v1/changelog" || len(cmd.Args) != 0 ||
			strings.Join(cmd.Flags, " ") != "--since --audience --student" || strings.Join(cmd.ErrorCodes, " ") != "E-AUTH E-FILES E-NOT-FOUND" {
			t.Errorf("changelog: %+v", cmd)
		}
		return
	}
	t.Error("changelog is not in the contract")
}

func TestChangelogQuery(t *testing.T) {
	r, seen := runTeacher(t, [][2]string{{"200", `{"audience":"student","entries":[],"content_updates":[]}`}}, "changelog", "--since", "2026-11-17", "--audience", "student",
		"--student", "prova-1", "--json")
	if r.exit != ExitOK || len(seen) != 1 {
		t.Fatalf("exit %d: %s", r.exit, r.stderr)
	}
	q, _ := url.ParseQuery(seen[0].query)
	want := url.Values{"since": {"2026-11-17"}, "audience": {"student"}, "student": {"prova-1"}}
	if seen[0].method != "GET" || seen[0].path != "/api/v1/changelog" || q.Encode() != want.Encode() {
		t.Errorf("%+v", seen[0])
	}
	if !strings.Contains(r.stdout, `"entries"`) {
		t.Errorf("the answer is printed as the server sent it: %q", r.stdout)
	}
}

func TestChangelogDefaultsAndFlagOrder(t *testing.T) {
	r, seen := runTeacher(t, [][2]string{{"200", `{}`}}, "changelog")
	if r.exit != ExitOK || seen[0].query != "" || seen[0].path != "/api/v1/changelog" {
		t.Errorf("the default call sends no query: %+v", seen)
	}
	r, seen = runTeacher(t, [][2]string{{"200", `{}`}}, "changelog", "--audience", "teacher")
	q, _ := url.ParseQuery(seen[0].query)
	if r.exit != ExitOK || q.Get("audience") != "teacher" || len(q) != 1 {
		t.Errorf("audience teacher is sent as given: %+v", seen)
	}
}

func TestChangelogRefusesBadInputBeforeTheNetwork(t *testing.T) {
	for _, args := range [][]string{
		{"changelog", "--since", "yesterday"},
		{"changelog", "--since", "2026-11-17T09:00:00Z"},
		{"changelog", "--audience", "parent"},
		{"changelog", "--student", "prova-1"},
		{"changelog", "--audience", "teacher", "--student", "prova-1"},
		{"changelog", "--audience", "student", "--student", "Not A Key"},
		{"changelog", "extra"},
	} {
		r, seen := runTeacher(t, [][2]string{{"200", `{}`}}, args...)
		if r.exit != ExitUsage || len(seen) != 0 || !strings.Contains(r.stderr, "E-USAGE") {
			t.Errorf("%v: exit %d, %d requests, %q", args, r.exit, len(seen), r.stderr)
		}
	}
}

func TestChangelogServerRefusals(t *testing.T) {
	cases := []struct {
		status, body, code string
		exit               int
	}{
		{"403", `{"code":"E-AUTH","field":"authorization","message":"a ci token cannot be used through the public host","next":"banco schema","reason":"not_public_role"}`, "E-AUTH", ExitAuth},
		{"422", `{"code":"E-FILES","field":"audience","message":"audience is student or teacher","next":"banco changelog"}`, "E-FILES", ExitValidation},
		{"404", `{"code":"E-NOT-FOUND","field":"student","message":"no student","next":"banco status"}`, "E-NOT-FOUND", ExitValidation},
	}
	for _, c := range cases {
		r, _ := runTeacher(t, [][2]string{{c.status, c.body}}, "changelog")
		if r.exit != c.exit {
			t.Errorf("%s: exit %d, want %d", c.status, r.exit, c.exit)
		}
		assertErrJSON(t, r.stderr, c.code)
	}
}
