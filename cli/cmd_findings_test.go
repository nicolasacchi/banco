package main

import (
	"net/url"
	"testing"
)

// D-313: the findings of the lesson reviews are listed and answered like the items' ones.

func TestFindingsListLessonFilters(t *testing.T) {
	cases := []struct {
		args  []string
		path  string
		query url.Values
	}{
		{[]string{"--subject", "math", "--kind", "lesson", "--open"}, "/api/v1/subjects/math/findings", url.Values{"kind": {"lesson"}, "open": {"1"}}},
		{[]string{"--subject", "math", "--kind", "item"}, "/api/v1/subjects/math/findings", url.Values{"kind": {"item"}}},
		// The subject is the lesson key's middle part when --subject is not given.
		{[]string{"--lesson", "ponte.biology.cell-basics"}, "/api/v1/subjects/biology/findings", url.Values{"lesson": {"ponte.biology.cell-basics"}}},
		{[]string{"--topic", "ripasso.math.demo", "--all"}, "/api/v1/subjects/math/findings", url.Values{"topic": {"ripasso.math.demo"}, "all": {"1"}}},
		{[]string{"--subject", "math", "--topic", "ripasso.math.demo", "--kind", "lesson"}, "/api/v1/subjects/math/findings", url.Values{"topic": {"ripasso.math.demo"}, "kind": {"lesson"}}},
	}
	for _, c := range cases {
		srv, seen := sequenceServer(t, [2]string{"200", `{"rows":[]}`})
		r := runWithSession(t, srv.URL, "31", append([]string{"findings", "list"}, c.args...)...)
		if r.exit != ExitOK || len(*seen) != 1 {
			t.Fatalf("%v: exit %d: %s", c.args, r.exit, r.stderr)
		}
		got := (*seen)[0]
		q, _ := url.ParseQuery(got.query)
		if got.method != "GET" || got.path != c.path || q.Encode() != c.query.Encode() {
			t.Errorf("%v: %s %s?%s, want %s?%s", c.args, got.method, got.path, got.query, c.path, c.query.Encode())
		}
	}
}

func TestFindingsListLessonUsageErrors(t *testing.T) {
	srv, seen := sequenceServer(t, [2]string{"200", `{"rows":[]}`})
	for _, args := range [][]string{
		{"--lesson", "ripasso.math.a", "--topic", "ripasso.math.b"},
		{"--subject", "math", "--kind", "page"},
		{"--lesson", "ripasso.math.a", "--kind", "item"},
		{"--lesson", "not a key"},
		{"--topic", "Ripasso.math.x"},
		{"--kind", "lesson"},
	} {
		r := runWithSession(t, srv.URL, "31", append([]string{"findings", "list"}, args...)...)
		if r.exit != ExitUsage {
			t.Errorf("%v: exit %d, want usage", args, r.exit)
		}
		assertErrJSON(t, r.stderr, "E-USAGE")
	}
	if len(*seen) != 0 {
		t.Fatal("a usage error must not reach the server")
	}
}

func TestFindingsRespondTakesALessonFindingId(t *testing.T) {
	srv, seen := sequenceServer(t, [2]string{"201", `{"id":1,"finding_id":"L12-3","stance":"lesson_right"}`})
	file := writeTemp(t, "response.json", `{"stance":"lesson_right","note_it":"La lezione è giusta."}`)
	for _, dry := range []bool{false, true} {
		args := []string{"findings", "respond", "L12-3", "--file", file}
		if dry {
			args = append(args, "--dry-run")
		}
		r := runWithSession(t, srv.URL, "31", args...)
		if r.exit != ExitOK {
			t.Fatalf("exit %d: %s", r.exit, r.stderr)
		}
	}
	for i, got := range *seen {
		doc, _ := got.body["response"].(map[string]any)
		if got.method != "POST" || got.path != "/api/v1/findings/L12-3/responses" || doc["stance"] != "lesson_right" {
			t.Errorf("request %d = %+v", i, got)
		}
		if want := map[int]string{0: "", 1: "1"}[i]; got.dry != want {
			t.Errorf("request %d: dry run header %q, want %q", i, got.dry, want)
		}
	}
}

func TestFindingsLessonIdsAreCheckedBeforeAnyRequest(t *testing.T) {
	srv, seen := sequenceServer(t, [2]string{"201", `{}`})
	file := writeTemp(t, "doc.json", `{}`)
	for _, id := range []string{"L0-1", "L12", "L12-0", "12-3", "l12-3", "L12-3-4", "L12-100"} {
		r := runWithSession(t, srv.URL, "31", "findings", "respond", id, "--file", file)
		if r.exit != ExitUsage {
			t.Errorf("respond %s: exit %d, want usage", id, r.exit)
		}
	}
	// A lesson finding has no third reviewer: assess refuses it with its own message.
	r := runWithSession(t, srv.URL, "31", "findings", "assess", "L12-3", "--file", file)
	if r.exit != ExitUsage {
		t.Fatalf("assess L12-3: exit %d", r.exit)
	}
	if e := assertErrJSON(t, r.stderr, "E-USAGE"); e.Next != "banco findings list --subject KEY --kind item --all" {
		t.Errorf("next = %q", e.Next)
	}
	if len(*seen) != 0 {
		t.Fatal("a usage error must not reach the server")
	}
}
