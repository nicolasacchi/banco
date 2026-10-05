package main

import (
	"path/filepath"
	"strings"
	"testing"
)

func TestSubjectCommandsUseTheirPathMethodAndBody(t *testing.T) {
	cases := []struct {
		args   []string
		method string
		path   string
		member string
		dry    string
	}{
		{[]string{"skill-graph", "open", "--subject", "math"}, "GET", "/api/v1/subjects/math/skill-graph", "", ""},
		{[]string{"skill-graph", "coverage", "--subject", "law_economics"}, "GET", "/api/v1/subjects/law_economics/skill-graph/coverage", "", ""},
		{[]string{"skill-graph", "submit", "--subject", "math", "FILE"}, "POST", "/api/v1/subjects/math/skill-graph", "graph", ""},
		{[]string{"skill-graph", "submit", "FILE", "--subject", "math", "--dry-run"}, "POST", "/api/v1/subjects/math/skill-graph", "graph", "1"},
		{[]string{"blueprint", "open", "--subject", "history"}, "GET", "/api/v1/subjects/history/blueprint", "", ""},
		{[]string{"blueprint", "submit", "--subject", "history", "FILE", "--dry-run"}, "POST", "/api/v1/subjects/history/blueprint", "blueprint", "1"},
	}
	for _, c := range cases {
		srv, seen := sequenceServer(t, [2]string{"200", `{"ok":true}`})
		file := writeTemp(t, "doc.json", `{"schema":"x"}`)
		args := append([]string{}, c.args...)
		for i, a := range args {
			if a == "FILE" {
				args[i] = file
			}
		}
		r := runCLI(t, srv.URL, envToken("bnc_x"), args...)
		if r.exit != ExitOK {
			t.Fatalf("%v: exit %d: %s", c.args, r.exit, r.stderr)
		}
		got := (*seen)[0]
		if got.method != c.method || got.path != c.path || got.dry != c.dry {
			t.Errorf("%v: request %+v", c.args, got)
		}
		if c.member != "" {
			doc, _ := got.body[c.member].(map[string]any)
			if doc["schema"] != "x" {
				t.Errorf("%v: the file must travel under %q, body = %v", c.args, c.member, got.body)
			}
		}
	}
}

func TestSubjectCommandsUsageErrors(t *testing.T) {
	srv, _ := sequenceServer(t, [2]string{"200", `{}`})
	file := writeTemp(t, "doc.json", `{}`)
	bad := writeTemp(t, "bad.json", `{not json`)
	for _, args := range [][]string{
		{"skill-graph", "open"},
		{"skill-graph", "open", "--subject", "Math"},
		{"skill-graph", "open", "--subject", "math", "extra"},
		{"skill-graph", "open", "--subject", "math", "--dry-run"},
		{"skill-graph", "submit", "--subject", "math"},
		{"skill-graph", "submit", "--subject", "math", file, file},
		{"skill-graph", "submit", "--subject", "math", filepath.Join(t.TempDir(), "none.json")},
		{"blueprint", "submit", "--subject", "math"},
	} {
		if r := runCLI(t, srv.URL, envToken("bnc_x"), args...); r.exit != ExitUsage {
			t.Errorf("%v: exit %d, want usage", args, r.exit)
		}
	}
	r := runCLI(t, srv.URL, envToken("bnc_x"), "skill-graph", "submit", "--subject", "math", bad)
	if r.exit != ExitValidation {
		t.Errorf("a file that is not JSON: exit %d", r.exit)
	}
	assertErrJSON(t, r.stderr, "E-FILES")
}

func TestGraphCycleDryRunExitsThreeWithTheCode(t *testing.T) {
	body := `{"code":"E-GRAPH-CYCLE","field":"/skills","message":"prerequisite cycle: a -> b -> a","next":"fix","dry_run":true,"codes":["E-GRAPH-CYCLE"],"findings":[{"code":"E-GRAPH-CYCLE"}]}`
	srv, _ := sequenceServer(t, [2]string{"422", body})
	file := writeTemp(t, "g.json", `{}`)
	r := runCLI(t, srv.URL, envToken("bnc_x"), "skill-graph", "submit", "--subject", "math", file, "--dry-run")
	if r.exit != ExitValidation {
		t.Fatalf("exit %d", r.exit)
	}
	e := assertErrJSON(t, r.stderr, "E-GRAPH-CYCLE")
	if !strings.Contains(e.Message, "cycle") || !e.DryRun {
		t.Errorf("%+v", e)
	}
}

func TestSyllabusLinesBuildsTheRangeQuery(t *testing.T) {
	srv, seen := sequenceServer(t, [2]string{"200", `{"rows":[]}`})
	r := runCLI(t, srv.URL, envToken("bnc_x"), "syllabus", "lines", "--source", "prima-test", "--from", "3", "--to", "9")
	if r.exit != ExitOK {
		t.Fatalf("exit %d: %s", r.exit, r.stderr)
	}
	got := (*seen)[0]
	if got.method != "GET" || got.path != "/api/v1/syllabus/prima-test/lines" || got.query != "from=3&to=9" {
		t.Errorf("request = %+v", got)
	}
	r = runCLI(t, srv.URL, envToken("bnc_x"), "syllabus", "lines", "--source", "prima-test")
	if r.exit != ExitOK || (*seen)[1].query != "" {
		t.Errorf("no range: exit %d, query %q", r.exit, (*seen)[1].query)
	}
	for _, args := range [][]string{{"syllabus", "lines"}, {"syllabus", "lines", "--source", "Bad Key"}, {"syllabus", "lines", "--source", "a", "extra"}} {
		if got := runCLI(t, srv.URL, envToken("bnc_x"), args...); got.exit != ExitUsage {
			t.Errorf("%v: exit %d", args, got.exit)
		}
	}
}

func TestReferenceCommandsBuildTheRequest(t *testing.T) {
	srv, seen := sequenceServer(t, [2]string{"200", `{"rows":[]}`}, [2]string{"200", `{}`})
	if r := runCLI(t, srv.URL, envToken("bnc_x"), "reference", "list"); r.exit != ExitOK {
		t.Fatalf("list: exit %d: %s", r.exit, r.stderr)
	}
	if r := runCLI(t, srv.URL, envToken("bnc_x"), "reference", "show", "--key", "brano-prova"); r.exit != ExitOK {
		t.Fatalf("show: exit %d: %s", r.exit, r.stderr)
	}
	if (*seen)[0].path != "/api/v1/references" || (*seen)[1].path != "/api/v1/references/brano-prova" {
		t.Errorf("requests = %+v", *seen)
	}
	for _, args := range [][]string{{"reference", "show"}, {"reference", "show", "--key", "Bad Key"}, {"reference", "list", "x"}} {
		if got := runCLI(t, srv.URL, envToken("bnc_x"), args...); got.exit != ExitUsage {
			t.Errorf("%v: exit %d", args, got.exit)
		}
	}
}

func TestItemsListBuildsTheRequest(t *testing.T) {
	srv, seen := sequenceServer(t, [2]string{"200", `{"rows":[]}`}, [2]string{"200", `{"rows":[]}`})
	if r := runCLI(t, srv.URL, envToken("bnc_x"), "items", "list", "--subject", "math", "--current"); r.exit != ExitOK {
		t.Fatalf("list: exit %d: %s", r.exit, r.stderr)
	}
	if r := runCLI(t, srv.URL, envToken("bnc_x"), "items", "list"); r.exit != ExitOK {
		t.Fatalf("list all: exit %d: %s", r.exit, r.stderr)
	}
	if (*seen)[0].path != "/api/v1/items" || (*seen)[0].query != "current=1&subject=math" || (*seen)[1].query != "" {
		t.Errorf("requests = %+v", *seen)
	}
	for _, args := range [][]string{{"items", "list", "--subject", "Bad Key"}, {"items", "list", "x"}} {
		if got := runCLI(t, srv.URL, envToken("bnc_x"), args...); got.exit != ExitUsage {
			t.Errorf("%v: exit %d", args, got.exit)
		}
	}
}
