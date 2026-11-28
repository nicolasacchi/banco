package main

import (
	"net/url"
	"strings"
	"testing"

	"banco/contract"
)

// D-407: banco writings list|show, the texts the student wrote himself and the teacher's corrections, read-only (no command corrects a text).

func TestWritingsCommandsAreInTheContract(t *testing.T) {
	c, err := contract.Parse()
	if err != nil {
		t.Fatal(err)
	}
	want := map[string]struct {
		path, flags, args, codes string
	}{
		"writings list": {"/api/v1/writings", "--status --subject --topic --student --limit", "", "E-AUTH E-FILES E-NOT-FOUND"},
		"writings show": {"/api/v1/writings/:id", "", "id", "E-AUTH E-NOT-FOUND"},
	}
	found := 0
	for _, cmd := range c.Commands {
		w, ok := want[cmd.Name]
		if !ok {
			continue
		}
		found++
		flags := strings.Join(cmd.Flags, " ")
		if cmd.Local || cmd.Method == nil || cmd.Path == nil || *cmd.Method != "GET" || *cmd.Path != w.path || strings.Join(cmd.Args, " ") != w.args ||
			flags != w.flags || strings.Join(cmd.ErrorCodes, " ") != w.codes {
			t.Errorf("%s: %+v", cmd.Name, cmd)
		}
	}
	if found != 2 {
		t.Errorf("found %d of the 2 writings commands in the contract", found)
	}
	for _, cmd := range c.Commands {
		if strings.HasPrefix(cmd.Name, "writings") && cmd.Method != nil && *cmd.Method != "GET" {
			t.Errorf("%s writes: a correction is the teacher's own words, never a command", cmd.Name)
		}
	}
}

func TestWritingsListQuery(t *testing.T) {
	r, seen := runTeacher(t, [][2]string{{"200", `{"writings":[]}`}}, "writings", "list", "--status", "pending", "--subject", "italian", "--topic", "lezione.italian.narrative-text",
		"--student", "prova-1", "--limit", "20", "--json")
	if r.exit != ExitOK || len(seen) != 1 {
		t.Fatalf("exit %d: %s", r.exit, r.stderr)
	}
	q, _ := url.ParseQuery(seen[0].query)
	want := url.Values{"status": {"pending"}, "subject": {"italian"}, "topic": {"lezione.italian.narrative-text"}, "student": {"prova-1"}, "limit": {"20"}}
	if seen[0].method != "GET" || seen[0].path != "/api/v1/writings" || q.Encode() != want.Encode() {
		t.Errorf("%+v", seen[0])
	}
	if !strings.Contains(r.stdout, `"writings"`) {
		t.Errorf("the answer is printed as the server sent it: %q", r.stdout)
	}
	r, seen = runTeacher(t, [][2]string{{"200", `{}`}}, "writings", "list")
	if r.exit != ExitOK || seen[0].query != "" {
		t.Errorf("the default list sends no query: %+v", seen)
	}
}

func TestWritingsShowPath(t *testing.T) {
	r, seen := runTeacher(t, [][2]string{{"200", `{"writing":{"id":7}}`}}, "writings", "show", "7")
	if r.exit != ExitOK || len(seen) != 1 || seen[0].method != "GET" || seen[0].path != "/api/v1/writings/7" {
		t.Fatalf("exit %d: %s %+v", r.exit, r.stderr, seen)
	}
}

func TestWritingsRefuseBadValuesBeforeAnyRequest(t *testing.T) {
	for _, args := range [][]string{
		{"list", "--status", "done"}, {"list", "--subject", "Italian!"}, {"list", "--topic", "racconto"}, {"list", "--student", "Prova 1"}, {"list", "--limit", "0"},
		{"list", "--limit", "501"}, {"list", "extra"}, {"show"}, {"show", "x"}, {"show", "0"}, {"show", "1", "2"},
	} {
		r, seen := runTeacher(t, [][2]string{{"200", `{}`}}, append([]string{"writings"}, args...)...)
		if r.exit != ExitUsage || len(seen) != 0 {
			t.Errorf("%v: exit %d, %d requests", args, r.exit, len(seen))
		}
		if r.exit == ExitUsage {
			assertErrJSON(t, r.stderr, "E-USAGE")
		}
	}
}

func TestWritingsServerRefusals(t *testing.T) {
	cases := []struct {
		status, body, code string
		exit               int
	}{
		{"403", `{"code":"E-AUTH","field":"authorization","message":"a agent_omp token cannot use this command: it needs a bot_read or teacher token","next":"banco schema","reason":"token_role"}`, "E-AUTH", ExitAuth},
		{"422", `{"code":"E-FILES","field":"status","message":"status is one of pending, corrected","next":"banco writings list"}`, "E-FILES", ExitValidation},
		{"404", `{"code":"E-NOT-FOUND","field":"id","message":"no writing \"9\"","next":"banco writings list"}`, "E-NOT-FOUND", ExitValidation},
	}
	for _, c := range cases {
		r, _ := runTeacher(t, [][2]string{{c.status, c.body}}, "writings", "show", "9")
		if r.exit != c.exit {
			t.Errorf("%s: exit %d, want %d", c.status, r.exit, c.exit)
		}
		assertErrJSON(t, r.stderr, c.code)
	}
}

// D-407: a topic that pins writing tasks is submitted as it is: the CLI adds nothing and drops nothing from the document (the server's checks decide), and the
// CLI has no command that records a correction.
func TestTopicSubmitSendsTheWritingPinsUnchanged(t *testing.T) {
	doc := `{"schema":"banco.topic/1","schema_version":1,"subject":"italian","key":"lezione.italian.narrative-text","lesson_revision":"latest",` +
		`"practice":[{"skill":"italian.narrative","items":[{"item":"it-p-1","revision":"latest"},{"item":"it-p-2","revision":"latest"}]}],` +
		`"writing":[{"item":"it-write-1","revision":"latest"}]}`
	file := writeTemp(t, "topic.json", doc)
	r, seen := runTeacher(t, [][2]string{{"200", `{"dry_run":true,"status":"passed"}`}}, "topic", "submit", file, "--dry-run")
	if r.exit != ExitOK || len(seen) != 1 {
		t.Fatalf("exit %d: %s", r.exit, r.stderr)
	}
	topic, _ := seen[0].body["topic"].(map[string]any)
	writing, _ := topic["writing"].([]any)
	if seen[0].path != "/api/v1/topics/lezione.italian.narrative-text" || len(writing) != 1 || writing[0].(map[string]any)["item"] != "it-write-1" {
		t.Errorf("%+v", seen[0])
	}
	for _, name := range []string{"writings correct", "writings reply"} {
		r, seen := runTeacher(t, [][2]string{{"200", `{}`}}, strings.Fields(name)...)
		if r.exit == ExitOK || len(seen) != 0 {
			t.Errorf("%s must not exist: exit %d, %d requests", name, r.exit, len(seen))
		}
	}
}
