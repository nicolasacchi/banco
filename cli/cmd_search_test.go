package main

import (
	"net/url"
	"testing"
)

func TestSearchSendsTheQueryAndTheFilters(t *testing.T) {
	cases := []struct {
		args  []string
		query map[string]string
	}{
		{[]string{"search", "equazioni"}, map[string]string{"q": "equazioni"}},
		{[]string{"search", "equazioni di primo grado", "--subject", "math"}, map[string]string{"q": "equazioni di primo grado", "subject": "math"}},
		{[]string{"search", "equazioni", "di", "primo", "grado", "--kind", "lesson_card,topic", "--limit", "5"}, map[string]string{"q": "equazioni di primo grado", "kind": "lesson_card,topic", "limit": "5"}},
		{[]string{"search", "--kind", "reference_article", "articolo 3", "--status", "imported", "--json"}, map[string]string{"q": "articolo 3", "kind": "reference_article", "status": "imported"}},
		{[]string{"search", "--like", "item_instance:math-frazioni-1#seed-a", "--limit", "10"}, map[string]string{"like": "item_instance:math-frazioni-1#seed-a", "limit": "10"}},
		{[]string{"search", "--like", "math.powers-properties", "--kind", "item"}, map[string]string{"like": "math.powers-properties", "kind": "item"}},
	}
	for _, c := range cases {
		srv, seen := sequenceServer(t, [2]string{"200", `{"query":"x","semantic":false,"results":[]}`})
		r := runCLI(t, srv.URL, envToken("bnc_x"), c.args...)
		if r.exit != ExitOK {
			t.Fatalf("%v: exit %d: %s", c.args, r.exit, r.stderr)
		}
		got := (*seen)[0]
		if got.method != "GET" || got.path != "/api/v1/search" {
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
	}
}

func TestSearchUsageErrors(t *testing.T) {
	srv, _ := sequenceServer(t, [2]string{"200", `{}`})
	for _, args := range [][]string{
		{"search"},
		{"search", "--subject", "math"},
		{"search", "x", "--subject", "Math"},
		{"search", "x", "--kind", "Lesson Card"},
		{"search", "x", "--limit", "500"},
		{"search", "x", "--limit", "-1"},
		{"search", "x", "--like", "item:abc"},
		{"search", "--like", "two words"},
		{"search", "--like", "item:KEY;rm"},
	} {
		if r := runCLI(t, srv.URL, envToken("bnc_x"), args...); r.exit != ExitUsage {
			t.Errorf("%v: exit %d, want usage", args, r.exit)
		}
	}
}

func TestSearchRefusesAKindTheServerDoesNotKnow(t *testing.T) {
	srv, _ := sequenceServer(t, [2]string{"404", `{"code":"E-NOT-FOUND","field":"kind","message":"no kind","next":"banco search x"}`})
	r := runCLI(t, srv.URL, envToken("bnc_x"), "search", "x", "--kind", "student_answer")
	if r.exit == ExitOK {
		t.Fatalf("exit %d", r.exit)
	}
	assertErrJSON(t, r.stderr, "E-NOT-FOUND")
}
