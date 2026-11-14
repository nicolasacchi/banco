package main

import (
	"net/url"
	"reflect"
	"strconv"
	"strings"
	"testing"
)

// D-327: the public API's commands for the teacher token (decide, decisions, comments, answers pending).

func runTeacher(t *testing.T, answers [][2]string, args ...string) (result, []request) {
	t.Helper()
	srv, seen := sequenceServer(t, answers...)
	r := runCLI(t, srv.URL, envToken("bnc_x"), args...)
	return r, *seen
}

func TestDecideIsADryRunUnlessConfirmed(t *testing.T) {
	r, seen := runTeacher(t, [][2]string{{"200", `{"recorded":false,"dry_run":true}`}}, "decide", "approve_skill_graph", "--params", `{"subject":"math"}`)
	if r.exit != ExitOK || len(seen) != 1 {
		t.Fatalf("exit %d: %s", r.exit, r.stderr)
	}
	got := seen[0]
	if got.method != "POST" || got.path != "/api/v1/decisions" || got.dry != "" {
		t.Errorf("request %+v", got)
	}
	if got.body["kind"] != "approve_skill_graph" || got.body["confirm"] != false {
		t.Errorf("body %v", got.body)
	}
	if !reflect.DeepEqual(got.body["params"], map[string]any{"subject": "math"}) {
		t.Errorf("params %v", got.body["params"])
	}
	if _, ok := got.body["reason_it"]; ok {
		t.Errorf("no reason was given: %v", got.body)
	}
	if !strings.Contains(r.stdout, `"dry_run":true`) {
		t.Errorf("stdout %q", r.stdout)
	}
}

func TestDecideConfirmReasonAttestAndParamsFile(t *testing.T) {
	file := writeTemp(t, "params.json", `{"revision_id": 12}`)
	r, seen := runTeacher(t, [][2]string{{"201", `{"recorded":true}`}}, "decide", "approve_topic", "--params-file", file, "--reason", "Va bene.", "--attest", "Letta fuori dall'app.", "--confirm")
	if r.exit != ExitOK {
		t.Fatalf("exit %d: %s", r.exit, r.stderr)
	}
	b := seen[0].body
	if b["confirm"] != true || b["reason_it"] != "Va bene." || b["attest_it"] != "Letta fuori dall'app." {
		t.Errorf("body %v", b)
	}
	if !reflect.DeepEqual(b["params"], map[string]any{"revision_id": float64(12)}) {
		t.Errorf("params %v", b["params"])
	}
	// the flags may come before the kind
	r, seen = runTeacher(t, [][2]string{{"201", `{}`}}, "decide", "--confirm", "release_diagnosis")
	if r.exit != ExitOK || seen[0].body["kind"] != "release_diagnosis" || seen[0].body["confirm"] != true {
		t.Errorf("exit %d %v", r.exit, seen)
	}
	if _, ok := seen[0].body["params"]; ok {
		t.Errorf("no params were given: %v", seen[0].body)
	}
}

func TestDecideUsageErrorsNeverReachTheServer(t *testing.T) {
	file := writeTemp(t, "p.json", `{}`)
	for _, args := range [][]string{
		{},
		{"Approve"},
		{"approve_topic", "extra"},
		{"approve_topic", "--params", "{}", "--params-file", file},
		{"approve_topic", "--params", "not json"},
		{"approve_topic", "--params", `["a"]`},
		{"approve_topic", "--params", "null"},
		{"approve_topic", "--params-file", "/nonexistent/params.json"},
	} {
		r, seen := runTeacher(t, [][2]string{{"200", `{}`}}, append([]string{"decide"}, args...)...)
		if r.exit != ExitUsage {
			t.Errorf("%v: exit %d, want usage", args, r.exit)
		}
		assertErrJSON(t, r.stderr, "E-USAGE")
		if len(seen) != 0 {
			t.Errorf("%v reached the server", args)
		}
	}
}

func TestDecideShowsTheServersRefusals(t *testing.T) {
	cases := []struct {
		status int
		body   string
		code   string
		exit   int
	}{
		{403, `{"code":"E-AUTH","field":"authorization","message":"a bot_read token only reads: POST is refused","next":"use a teacher token","reason":"read_only_token"}`, "E-AUTH", ExitAuth},
		{403, `{"code":"E-TEACHER-REFUSED","field":"authorization","message":"refused: disabled","next":"ask the operator"}`, "E-TEACHER-REFUSED", ExitAuth},
		{422, `{"code":"E-DECISION-INVALID","field":"params","message":"revision 3 is already approved","next":"fix","reasons":["revision 3 is already approved"]}`, "E-DECISION-INVALID", ExitValidation},
	}
	for _, c := range cases {
		r, _ := runTeacher(t, [][2]string{{strconv.Itoa(c.status), c.body}}, "decide", "approve_skill_graph", "--confirm")
		if r.exit != c.exit {
			t.Errorf("%s: exit %d, want %d", c.code, r.exit, c.exit)
		}
		assertErrJSON(t, r.stderr, c.code)
	}
}

func TestDecisionsQuery(t *testing.T) {
	cases := []struct {
		args  []string
		query url.Values
	}{
		{nil, url.Values{}},
		{[]string{"--since", "0"}, url.Values{"since": {"0"}}},
		{[]string{"--since", "41", "--limit", "20", "--kind", "approve_topic"}, url.Values{"since": {"41"}, "limit": {"20"}, "kind": {"approve_topic"}}},
	}
	for _, c := range cases {
		r, seen := runTeacher(t, [][2]string{{"200", `{"decisions":[]}`}}, append([]string{"decisions"}, c.args...)...)
		if r.exit != ExitOK || len(seen) != 1 {
			t.Fatalf("%v: exit %d: %s", c.args, r.exit, r.stderr)
		}
		q, _ := url.ParseQuery(seen[0].query)
		if seen[0].method != "GET" || seen[0].path != "/api/v1/decisions" || q.Encode() != c.query.Encode() {
			t.Errorf("%v: %+v", c.args, seen[0])
		}
	}
	for _, args := range [][]string{{"--since", "abc"}, {"--since", "-1"}, {"--limit", "0"}, {"--kind", "Bad Kind"}, {"extra"}} {
		r, seen := runTeacher(t, [][2]string{{"200", `{}`}}, append([]string{"decisions"}, args...)...)
		if r.exit != ExitUsage || len(seen) != 0 {
			t.Errorf("%v: exit %d, %d requests", args, r.exit, len(seen))
		}
	}
}

func TestCommentsListQuery(t *testing.T) {
	r, seen := runTeacher(t, [][2]string{{"200", `{"comments":[]}`}}, "comments", "list", "--state", "all", "--subject", "math", "--who", "trial", "--reason", "error", "--kind", "lesson", "--limit", "10")
	if r.exit != ExitOK || len(seen) != 1 {
		t.Fatalf("exit %d: %s", r.exit, r.stderr)
	}
	q, _ := url.ParseQuery(seen[0].query)
	want := url.Values{"state": {"all"}, "subject": {"math"}, "who": {"trial"}, "reason": {"error"}, "kind": {"lesson"}, "limit": {"10"}}
	if seen[0].path != "/api/v1/comments" || q.Encode() != want.Encode() {
		t.Errorf("%+v", seen[0])
	}
	r, seen = runTeacher(t, [][2]string{{"200", `{}`}}, "comments", "list")
	if r.exit != ExitOK || seen[0].query != "" {
		t.Errorf("the default list sends no query: %+v", seen)
	}
	for _, args := range [][]string{{"--state", "maybe"}, {"--who", "nobody"}, {"--subject", "Math!"}, {"--limit", "x"}, {"7"}} {
		r, seen := runTeacher(t, [][2]string{{"200", `{}`}}, append([]string{"comments", "list"}, args...)...)
		if r.exit != ExitUsage || len(seen) != 0 {
			t.Errorf("%v: exit %d, %d requests", args, r.exit, len(seen))
		}
	}
}

func TestCommentsShowAndActions(t *testing.T) {
	r, seen := runTeacher(t, [][2]string{{"200", `{"comment":{}}`}}, "comments", "show", "7")
	if r.exit != ExitOK || seen[0].method != "GET" || seen[0].path != "/api/v1/comments/7" {
		t.Fatalf("show: exit %d %+v", r.exit, seen)
	}
	cases := []struct {
		args []string
		path string
		body map[string]any
	}{
		{[]string{"comments", "reply", "7", "--text", "Guarda la scheda 2."}, "/api/v1/comments/7/reply", map[string]any{"text_it": "Guarda la scheda 2.", "confirm": false}},
		{[]string{"comments", "reply", "7", "--text", "Ok.", "--confirm"}, "/api/v1/comments/7/reply", map[string]any{"text_it": "Ok.", "confirm": true}},
		{[]string{"comments", "resolve", "7"}, "/api/v1/comments/7/resolve", map[string]any{"confirm": false}},
		{[]string{"comments", "resolve", "7", "--reason", "Detto a voce.", "--confirm"}, "/api/v1/comments/7/resolve", map[string]any{"reason_it": "Detto a voce.", "confirm": true}},
		{[]string{"comments", "reopen", "7", "--confirm"}, "/api/v1/comments/7/reopen", map[string]any{"confirm": true}},
		{[]string{"comments", "read", "--confirm", "7"}, "/api/v1/comments/7/read", map[string]any{"confirm": true}},
	}
	for _, c := range cases {
		r, seen := runTeacher(t, [][2]string{{"201", `{"recorded":true}`}}, c.args...)
		if r.exit != ExitOK || len(seen) != 1 {
			t.Fatalf("%v: exit %d: %s", c.args, r.exit, r.stderr)
		}
		if seen[0].method != "POST" || seen[0].path != c.path || !reflect.DeepEqual(seen[0].body, c.body) {
			t.Errorf("%v: %+v, want %s %v", c.args, seen[0], c.path, c.body)
		}
	}
}

func TestCommentsUsageErrorsNeverReachTheServer(t *testing.T) {
	for _, args := range [][]string{
		{"comments", "show"},
		{"comments", "show", "abc"},
		{"comments", "show", "0"},
		{"comments", "reply", "7"},
		{"comments", "reply", "7", "--text", "  "},
		{"comments", "reply", "7", "--text", "x", "--reason", "y"},
		{"comments", "resolve", "7", "--text", "x"},
		{"comments", "reopen"},
		{"comments", "read", "7", "--reason", "x"},
		{"comments", "read", "7", "8"},
	} {
		r, seen := runTeacher(t, [][2]string{{"200", `{}`}}, args...)
		if r.exit != ExitUsage || len(seen) != 0 {
			t.Errorf("%v: exit %d, %d requests", args, r.exit, len(seen))
		}
		assertErrJSON(t, r.stderr, "E-USAGE")
	}
}

func TestAnswersPendingQuery(t *testing.T) {
	r, seen := runTeacher(t, [][2]string{{"200", `{"answers":[]}`}}, "answers", "pending", "--subject", "math", "--student", "prova-1")
	if r.exit != ExitOK || len(seen) != 1 {
		t.Fatalf("exit %d: %s", r.exit, r.stderr)
	}
	q, _ := url.ParseQuery(seen[0].query)
	if seen[0].method != "GET" || seen[0].path != "/api/v1/answers/pending" || q.Get("subject") != "math" || q.Get("student") != "prova-1" {
		t.Errorf("%+v", seen[0])
	}
	r, seen = runTeacher(t, [][2]string{{"200", `{}`}}, "answers", "pending")
	if r.exit != ExitOK || seen[0].query != "" {
		t.Errorf("plain: %+v", seen)
	}
	for _, args := range [][]string{{"--subject", "Math"}, {"--student", "A B"}, {"extra"}} {
		r, seen := runTeacher(t, [][2]string{{"200", `{}`}}, append([]string{"answers", "pending"}, args...)...)
		if r.exit != ExitUsage || len(seen) != 0 {
			t.Errorf("%v: exit %d, %d requests", args, r.exit, len(seen))
		}
	}
}

// The edge answers 429 itself, without the contract header: the CLI names it instead of "the server did not answer as banco".
func TestTheEdgesRateLimitIsNamed(t *testing.T) {
	srv := fakeServer(429, "Too Many Requests", "")
	defer srv.Close()
	r := runCLI(t, srv.URL, envToken("bnc_x"), "status")
	if r.exit != ExitServer {
		t.Fatalf("exit %d", r.exit)
	}
	assertErrJSON(t, r.stderr, "E-RATE-LIMIT")
}
