package main

import (
	"net/url"
	"strings"
	"testing"

	"banco/contract"
)

// D-368: banco grading review, where the grader may be wrong (the exercises to check and the not-right tries with their signals), read-only.

func TestGradingReviewIsInTheContract(t *testing.T) {
	c, err := contract.Parse()
	if err != nil {
		t.Fatal(err)
	}
	for _, cmd := range c.Commands {
		if cmd.Name != "grading review" {
			continue
		}
		if cmd.Local || cmd.Method == nil || cmd.Path == nil || *cmd.Method != "GET" || *cmd.Path != "/api/v1/grading/review" || len(cmd.Args) != 0 ||
			strings.Join(cmd.Flags, " ") != "--since --subject --student" || strings.Join(cmd.ErrorCodes, " ") != "E-AUTH E-FILES E-NOT-FOUND" {
			t.Errorf("grading review: %+v", cmd)
		}
		return
	}
	t.Error("grading review is not in the contract")
}

func TestGradingReviewQuery(t *testing.T) {
	r, seen := runTeacher(t, [][2]string{{"200", `{"items":[],"tries":[]}`}}, "grading", "review", "--since", "2026-11-16", "--subject", "english", "--student", "prova-1", "--json")
	if r.exit != ExitOK || len(seen) != 1 {
		t.Fatalf("exit %d: %s", r.exit, r.stderr)
	}
	q, _ := url.ParseQuery(seen[0].query)
	want := url.Values{"since": {"2026-11-16"}, "subject": {"english"}, "student": {"prova-1"}}
	if seen[0].method != "GET" || seen[0].path != "/api/v1/grading/review" || q.Encode() != want.Encode() {
		t.Errorf("%+v", seen[0])
	}
	if !strings.Contains(r.stdout, `"items"`) {
		t.Errorf("the answer is printed as the server sent it: %q", r.stdout)
	}
}

func TestGradingReviewDefaultsAndTimes(t *testing.T) {
	r, seen := runTeacher(t, [][2]string{{"200", `{}`}}, "grading", "review")
	if r.exit != ExitOK || seen[0].query != "" {
		t.Errorf("the default review sends no query: %+v", seen)
	}
	r, seen = runTeacher(t, [][2]string{{"200", `{}`}}, "grading", "review", "--since", "2026-11-16T09:30:00+01:00")
	q, _ := url.ParseQuery(seen[0].query)
	if r.exit != ExitOK || q.Get("since") != "2026-11-16T09:30:00+01:00" {
		t.Errorf("since is sent as given: %+v", seen)
	}
	// --json is the default output and is accepted
	r, seen = runTeacher(t, [][2]string{{"200", `{}`}}, "grading", "review", "--json", "--subject", "math")
	if r.exit != ExitOK || len(seen) != 1 {
		t.Fatalf("exit %d: %s", r.exit, r.stderr)
	}
}

func TestGradingReviewRefusesBadValuesBeforeAnyRequest(t *testing.T) {
	for _, args := range [][]string{{"--since", "yesterday"}, {"--since", "16/11/2026"}, {"--subject", "Math!"}, {"--student", "Prova 1"}, {"7"}} {
		r, seen := runTeacher(t, [][2]string{{"200", `{}`}}, append([]string{"grading", "review"}, args...)...)
		if r.exit != ExitUsage || len(seen) != 0 {
			t.Errorf("%v: exit %d, %d requests", args, r.exit, len(seen))
		}
		if r.exit == ExitUsage {
			assertErrJSON(t, r.stderr, "E-USAGE")
		}
	}
}

func TestGradingReviewServerRefusals(t *testing.T) {
	cases := []struct {
		status, body, code string
		exit               int
	}{
		{"403", `{"code":"E-AUTH","field":"authorization","message":"a agent_omp token cannot use this command: it needs a bot_read or teacher token","next":"banco schema","reason":"token_role"}`, "E-AUTH", ExitAuth},
		{"422", `{"code":"E-FILES","field":"since","message":"since is an ISO 8601 date or moment","next":"banco grading review --since 2026-11-16"}`, "E-FILES", ExitValidation},
		{"404", `{"code":"E-NOT-FOUND","field":"subject","message":"no subject \"history\"","next":"banco status"}`, "E-NOT-FOUND", ExitValidation},
	}
	for _, c := range cases {
		r, _ := runTeacher(t, [][2]string{{c.status, c.body}}, "grading", "review")
		if r.exit != c.exit {
			t.Errorf("%s: exit %d, want %d", c.status, r.exit, c.exit)
		}
		assertErrJSON(t, r.stderr, c.code)
	}
}
