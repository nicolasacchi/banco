package main

import (
	"net/url"
	"strings"
	"testing"
)

// D-346: the student's answers (practice, entry test, lesson checks) for the teacher bot (attempts, attempts show) and `search --kind student_answer`.

func TestAttemptsCommandsUseTheirPathAndFilters(t *testing.T) {
	cases := []struct {
		args  []string
		path  string
		query map[string]string
	}{
		{[]string{"attempts"}, "/api/v1/students/student/attempts", map[string]string{}},
		{[]string{"attempts", "--student", "prova-1"}, "/api/v1/students/prova-1/attempts", map[string]string{}},
		{[]string{"attempts", "--student", "student", "--since", "2026-11-16", "--outcome", "typical_error"}, "/api/v1/students/student/attempts",
			map[string]string{"since": "2026-11-16", "outcome": "typical_error"}},
		{[]string{"attempts", "--subject", "math", "--topic", "ripasso.math.demo", "--skill", "math.linear-equation-integer", "--item", "demo-item-1",
			"--since", "2026-11-16T09:00:00Z", "--until", "2026-11-17", "--serve", "12", "--comment", "17", "--limit", "50", "--after", "9", "--json"},
			"/api/v1/students/student/attempts",
			map[string]string{"subject": "math", "topic": "ripasso.math.demo", "skill": "math.linear-equation-integer", "item": "demo-item-1",
				"since": "2026-11-16T09:00:00Z", "until": "2026-11-17", "serve": "12", "comment": "17", "limit": "50", "after": "9"}},
		{[]string{"attempts", "--kind", "diagnosis,lesson", "--outcome", "wrong", "--after", "diagnosis-4"}, "/api/v1/students/student/attempts",
			map[string]string{"kind": "diagnosis,lesson", "outcome": "wrong", "after": "diagnosis-4"}},
		{[]string{"attempts", "show", "52"}, "/api/v1/students/student/attempts/52", map[string]string{}},
		{[]string{"attempts", "show", "diagnosis-7"}, "/api/v1/students/student/attempts/diagnosis-7", map[string]string{}},
		{[]string{"attempts", "show", "lesson-31", "--student", "prova-1"}, "/api/v1/students/prova-1/attempts/lesson-31", map[string]string{}},
		{[]string{"attempts", "show", "52", "--student", "prova-1", "--comment", "17"}, "/api/v1/students/prova-1/attempts/52", map[string]string{"comment": "17"}},
		{[]string{"attempts", "show", "--comment", "18", "7"}, "/api/v1/students/student/attempts/7", map[string]string{"comment": "18"}},
	}
	for _, c := range cases {
		srv, seen := sequenceServer(t, [2]string{"200", `{"ok":true}`})
		r := runCLI(t, srv.URL, envToken("bnc_x"), c.args...)
		if r.exit != ExitOK {
			t.Fatalf("%v: exit %d: %s", c.args, r.exit, r.stderr)
		}
		got := (*seen)[0]
		if got.method != "GET" || got.path != c.path || got.dry != "" || got.body != nil {
			t.Errorf("%v: request %+v", c.args, got)
		}
		values, _ := url.ParseQuery(got.query)
		if len(values) != len(c.query) {
			t.Errorf("%v: query %v", c.args, values)
		}
		for k, v := range c.query {
			if values.Get(k) != v {
				t.Errorf("%v: %s = %q, want %q", c.args, k, values.Get(k), v)
			}
		}
		if strings.TrimSpace(r.stdout) != `{"ok":true}` {
			t.Errorf("%v: stdout %q", c.args, r.stdout)
		}
	}
}

func TestAttemptsUsageErrorsNeverReachTheServer(t *testing.T) {
	srv, seen := sequenceServer(t, [2]string{"200", `{}`})
	for _, args := range [][]string{
		{"attempts", "extra"},
		{"attempts", "52"},
		{"attempts", "--student", "A/B"},
		{"attempts", "--subject", "Math"},
		{"attempts", "--topic", "not-a-topic"},
		{"attempts", "--skill", "Math Skill"},
		{"attempts", "--item", "A B"},
		{"attempts", "--since", "yesterday"},
		{"attempts", "--until", "16/11/2026"},
		{"attempts", "--outcome", "Wrong"},
		{"attempts", "--kind", "warmup"},
		{"attempts", "--kind", "practice,"},
		{"attempts", "--after", "other-3"},
		{"attempts", "--serve", "x"},
		{"attempts", "--comment", "0"},
		{"attempts", "--after", "-1"},
		{"attempts", "--limit", "501"},
		{"attempts", "--limit", "0"},
		{"attempts", "show"},
		{"attempts", "show", "x"},
		{"attempts", "show", "warmup-3"},
		{"attempts", "show", "practice-0"},
		{"attempts", "show", "1", "2"},
		{"attempts", "show", "1", "--student", "A/B"},
		{"attempts", "show", "1", "--comment", "x"},
		{"search", "x", "--kind", "student_answer", "--student", "A/B"},
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

func TestAttemptsOutcomesAreSent(t *testing.T) {
	for _, outcome := range []string{"correct", "correct_aided", "typical_error", "unrecognised", "form", "near_miss", "undetermined", "contested", "not_a_try", "ungraded", "wrong", "right", "undetermined"} {
		srv, seen := sequenceServer(t, [2]string{"200", `{}`})
		r := runCLI(t, srv.URL, envToken("bnc_x"), "attempts", "--outcome", outcome)
		if r.exit != ExitOK {
			t.Fatalf("%s: exit %d: %s", outcome, r.exit, r.stderr)
		}
		if values, _ := url.ParseQuery((*seen)[0].query); values.Get("outcome") != outcome {
			t.Errorf("%s: query %v", outcome, values)
		}
	}
}

func TestAttemptsRefusalsKeepTheirExit(t *testing.T) {
	srv, _ := sequenceServer(t, [2]string{"403", `{"code":"E-AUTH","field":"authorization","message":"a bot_read token cannot use this command: it needs a teacher token","next":"banco schema","reason":"token_role"}`})
	r := runCLI(t, srv.URL, envToken("bnc_x"), "attempts")
	if r.exit != ExitAuth {
		t.Fatalf("exit %d: %s", r.exit, r.stderr)
	}
	assertErrJSON(t, r.stderr, "E-AUTH")

	srv, _ = sequenceServer(t, [2]string{"404", `{"code":"E-NOT-FOUND","field":"id","message":"no attempt 9","next":"banco attempts"}`})
	r = runCLI(t, srv.URL, envToken("bnc_x"), "attempts", "show", "9")
	if r.exit != ExitValidation {
		t.Fatalf("exit %d: %s", r.exit, r.stderr)
	}
	assertErrJSON(t, r.stderr, "E-NOT-FOUND")
}

func TestSearchSendsTheStudentOfTheAnswersKind(t *testing.T) {
	srv, seen := sequenceServer(t, [2]string{"200", `{"results":[]}`})
	r := runCLI(t, srv.URL, envToken("bnc_x"), "search", "sette", "--kind", "student_answer", "--student", "prova-1")
	if r.exit != ExitOK {
		t.Fatalf("exit %d: %s", r.exit, r.stderr)
	}
	values, _ := url.ParseQuery((*seen)[0].query)
	if values.Get("q") != "sette" || values.Get("kind") != "student_answer" || values.Get("student") != "prova-1" || len(values) != 3 {
		t.Errorf("query %v", values)
	}
}
