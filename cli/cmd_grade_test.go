package main

import (
	"encoding/json"
	"io"
	"net/http"
	"net/http/httptest"
	"os"
	"path/filepath"
	"reflect"
	"strings"
	"testing"

	"banco/contract"
)

// gradeServer records the one POST of a grade command and answers with the given status and body.
type gradeServer struct {
	method, path string
	body         map[string]any
	calls        int
}

func newGradeServer(t *testing.T, status int, answer string) (*httptest.Server, *gradeServer) {
	t.Helper()
	g := &gradeServer{}
	srv := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		g.calls++
		g.method, g.path = r.Method, r.URL.Path
		raw, _ := io.ReadAll(r.Body)
		_ = json.Unmarshal(raw, &g.body)
		w.Header().Set("X-Banco-Contract", contract.Digest())
		w.Header().Set("Content-Type", "application/json")
		w.WriteHeader(status)
		_, _ = w.Write([]byte(answer))
	}))
	t.Cleanup(srv.Close)
	return srv, g
}

func TestContractListsTheGradeCommands(t *testing.T) {
	c, err := contract.Parse()
	if err != nil {
		t.Fatal(err)
	}
	want := map[string]string{"item grade": "/api/v1/item-revisions/:revision/grade", "lesson grade": "/api/v1/lesson-revisions/:revision/grade"}
	for _, cmd := range c.Commands {
		path, ok := want[cmd.Name]
		if !ok {
			continue
		}
		delete(want, cmd.Name)
		if cmd.Local || cmd.Method == nil || *cmd.Method != "POST" || cmd.Path == nil || *cmd.Path != path || !contains(cmd.Flags, "--answer") || !contains(cmd.Flags, "--answers-file") || !contains(cmd.ErrorCodes, "E-NOT-FOUND") {
			t.Errorf("%s: %+v", cmd.Name, cmd)
		}
	}
	if len(want) > 0 {
		t.Fatalf("the contract lacks %v", want)
	}
}

func TestItemGradePostsEveryAnswerForTheInstanceAndPrintsTheServersAnswer(t *testing.T) {
	answer := `{"revision_id":12,"read_only":true,"results":[{"instance":3,"verdict":"correct","matched":{"kind":"key","value":"is scared"}}]}`
	srv, g := newGradeServer(t, 200, answer)
	res := runItemShotsCLI(t, srv.URL, "item", "grade", "12", "--instance", "3", "--answer", "'s scared", "--answer", "is scared")
	if res.exit != 0 {
		t.Fatalf("exit %d, stderr %s", res.exit, res.stderr)
	}
	if g.method != "POST" || g.path != "/api/v1/item-revisions/12/grade" || g.calls != 1 {
		t.Errorf("one POST to the grade route: %s %s (%d calls)", g.method, g.path, g.calls)
	}
	want := map[string]any{"answers": []any{
		map[string]any{"instance": float64(3), "answer": "'s scared"},
		map[string]any{"instance": float64(3), "answer": "is scared"},
	}}
	if !reflect.DeepEqual(g.body, want) {
		t.Errorf("body %v, want %v", g.body, want)
	}
	if strings.TrimSpace(res.stdout) != answer {
		t.Errorf("stdout is the server's answer: %q", res.stdout)
	}
}

func TestItemGradeTakesAnAnswersFileWithOneArray(t *testing.T) {
	srv, g := newGradeServer(t, 200, `{"results":[]}`)
	file := filepath.Join(t.TempDir(), "answers.json")
	if err := os.WriteFile(file, []byte(`[{"instance":1,"answer":"está"},{"instance":2,"answer":["o1","o2"]}]`), 0o600); err != nil {
		t.Fatal(err)
	}
	res := runItemShotsCLI(t, srv.URL, "item", "grade", "12", "--answers-file", file)
	if res.exit != 0 {
		t.Fatalf("exit %d, stderr %s", res.exit, res.stderr)
	}
	list, _ := g.body["answers"].([]any)
	if len(list) != 2 || !reflect.DeepEqual(list[1], map[string]any{"instance": float64(2), "answer": []any{"o1", "o2"}}) {
		t.Errorf("the file's entries go as they are: %v", g.body)
	}
	// the file and --answer together, a file that is not an array of entries, an entry without its answer: usage errors, nothing sent
	bad := filepath.Join(t.TempDir(), "bad.json")
	for _, content := range []string{`{"instance":1,"answer":"x"}`, `[]`, `[{"instance":1}]`, `[{"answer":"x"}]`} {
		if err := os.WriteFile(bad, []byte(content), 0o600); err != nil {
			t.Fatal(err)
		}
		g.calls = 0
		res = runItemShotsCLI(t, srv.URL, "item", "grade", "12", "--answers-file", bad)
		if res.exit != ExitUsage || !strings.Contains(res.stderr, "answers-file") || g.calls != 0 {
			t.Errorf("%s: exit %d stderr %s calls %d", content, res.exit, res.stderr, g.calls)
		}
	}
	res = runItemShotsCLI(t, srv.URL, "item", "grade", "12", "--answers-file", file, "--answer", "x")
	if res.exit != ExitUsage {
		t.Errorf("--answers-file with --answer: exit %d", res.exit)
	}
}

func TestItemGradeUsageErrorsSendNothing(t *testing.T) {
	srv, g := newGradeServer(t, 200, `{}`)
	for _, args := range [][]string{
		{"item", "grade"}, {"item", "grade", "abc", "--instance", "1", "--answer", "x"}, {"item", "grade", "12", "--answer", "x"},
		{"item", "grade", "12", "--instance", "1"}, {"item", "grade", "12", "--instance", "0", "--answer", "x"}, {"item", "grade", "12", "--instance", "one", "--answer", "x"},
	} {
		res := runItemShotsCLI(t, srv.URL, args...)
		if res.exit != ExitUsage {
			t.Errorf("%v: exit %d stderr %s", args, res.exit, res.stderr)
		}
	}
	if g.calls != 0 {
		t.Errorf("a usage error sends nothing: %d calls", g.calls)
	}
}

func TestItemGradeReportsAnUnknownInstanceWithItsCode(t *testing.T) {
	srv, _ := newGradeServer(t, 404, `{"code":"E-NOT-FOUND","field":"answers/0/instance","message":"revision 12 has no instance 9","next":"banco review open 12"}`)
	res := runItemShotsCLI(t, srv.URL, "item", "grade", "12", "--instance", "9", "--answer", "x")
	if res.exit != ExitValidation || !strings.Contains(res.stderr, "E-NOT-FOUND") || !strings.Contains(res.stderr, "no instance 9") {
		t.Fatalf("exit %d stderr %s", res.exit, res.stderr)
	}
}

func TestLessonGradePostsTheCheckIdWithEveryAnswer(t *testing.T) {
	srv, g := newGradeServer(t, 200, `{"results":[{"check":"3.2","verdict":"right"}]}`)
	res := runItemShotsCLI(t, srv.URL, "lesson", "grade", "40", "--check", "3.2.ex1.2", "--answer", "está", "--answer", "esta")
	if res.exit != 0 {
		t.Fatalf("exit %d, stderr %s", res.exit, res.stderr)
	}
	if g.method != "POST" || g.path != "/api/v1/lesson-revisions/40/grade" {
		t.Errorf("%s %s", g.method, g.path)
	}
	want := map[string]any{"answers": []any{
		map[string]any{"check": "3.2.ex1.2", "answer": "está"},
		map[string]any{"check": "3.2.ex1.2", "answer": "esta"},
	}}
	if !reflect.DeepEqual(g.body, want) {
		t.Errorf("body %v, want %v", g.body, want)
	}
	file := filepath.Join(t.TempDir(), "answers.json")
	if err := os.WriteFile(file, []byte(`[{"check":"1.1","answer":"a"},{"check":"2.3.step4","answer":"b"}]`), 0o600); err != nil {
		t.Fatal(err)
	}
	res = runItemShotsCLI(t, srv.URL, "lesson", "grade", "40", "--answers-file", file)
	if list, _ := g.body["answers"].([]any); res.exit != 0 || len(list) != 2 {
		t.Errorf("answers file: exit %d body %v stderr %s", res.exit, g.body, res.stderr)
	}
	// the lesson command takes --check, not --instance; the check is a string, never a number
	for _, args := range [][]string{{"lesson", "grade", "40", "--answer", "x"}, {"lesson", "grade", "40", "--instance", "1", "--answer", "x"}, {"lesson", "grade", "x", "--check", "1.1", "--answer", "x"}} {
		if res = runItemShotsCLI(t, srv.URL, args...); res.exit != ExitUsage {
			t.Errorf("%v: exit %d", args, res.exit)
		}
	}
}

// A tiles or ordering answer is a list of ids: the CLI sends it untouched (the server reads the shown ids and the tile ids, D-403), so a comma list stays one
// string on --answer and a JSON array of --answers-file stays an array.
func TestLessonGradeSendsATileListAsWritten(t *testing.T) {
	srv, g := newGradeServer(t, 200, `{"results":[]}`)
	res := runItemShotsCLI(t, srv.URL, "lesson", "grade", "40", "--check", "1.1", "--answer", "t1,t2,t3", "--answer", `["e2","e1","e3"]`)
	if res.exit != 0 {
		t.Fatalf("exit %d, stderr %s", res.exit, res.stderr)
	}
	want := map[string]any{"answers": []any{
		map[string]any{"check": "1.1", "answer": "t1,t2,t3"},
		map[string]any{"check": "1.1", "answer": `["e2","e1","e3"]`},
	}}
	if !reflect.DeepEqual(g.body, want) {
		t.Errorf("body %v, want %v", g.body, want)
	}
	file := filepath.Join(t.TempDir(), "answers.json")
	if err := os.WriteFile(file, []byte(`[{"check":"1.1","answer":["t1","t2","t3"]}]`), 0o600); err != nil {
		t.Fatal(err)
	}
	if res = runItemShotsCLI(t, srv.URL, "lesson", "grade", "40", "--answers-file", file); res.exit != 0 {
		t.Fatalf("exit %d, stderr %s", res.exit, res.stderr)
	}
	if list, _ := g.body["answers"].([]any); len(list) != 1 || !reflect.DeepEqual(list[0], map[string]any{"check": "1.1", "answer": []any{"t1", "t2", "t3"}}) {
		t.Errorf("a JSON array goes as an array: %v", g.body)
	}
}

func TestLessonGradeReportsAnUnknownCheckWithItsCode(t *testing.T) {
	srv, _ := newGradeServer(t, 404, `{"code":"E-NOT-FOUND","field":"answers/0/check","message":"revision 40 has no check \"9.9\"","next":"a check id is CARD.BLOCK"}`)
	res := runItemShotsCLI(t, srv.URL, "lesson", "grade", "40", "--check", "9.9", "--answer", "x")
	if res.exit != ExitValidation || !strings.Contains(res.stderr, "E-NOT-FOUND") {
		t.Fatalf("exit %d stderr %s", res.exit, res.stderr)
	}
}

// D-403, round 9: a repeated --instance (or --check) would grade every answer against the last one; it is refused before anything is sent.
func TestGradeRefusesARepeatedTargetFlag(t *testing.T) {
	srv, g := newGradeServer(t, 200, `{}`)
	for _, args := range [][]string{
		{"item", "grade", "12", "--instance", "1", "--answer", "a", "--instance", "2", "--answer", "b"},
		{"item", "grade", "12", "--instance", "1", "--instance", "1", "--answer", "a"},
		{"lesson", "grade", "40", "--check", "1.1", "--answer", "a", "--check", "1.2", "--answer", "b"},
	} {
		res := runItemShotsCLI(t, srv.URL, args...)
		if res.exit != ExitUsage || !strings.Contains(res.stderr, "E-USAGE") || !strings.Contains(res.stderr, "answers-file") {
			t.Errorf("%v: exit %d stderr %s", args, res.exit, res.stderr)
		}
	}
	if g.calls != 0 {
		t.Errorf("a usage error sends nothing: %d calls", g.calls)
	}
	// one --instance with several --answer stays valid, and so does a file that pairs each answer with its own instance
	if res := runItemShotsCLI(t, srv.URL, "item", "grade", "12", "--instance", "2", "--answer", "a", "--answer", "b"); res.exit != 0 || g.calls != 1 {
		t.Errorf("one --instance: exit %d calls %d stderr %s", res.exit, g.calls, res.stderr)
	}
}

// --file grades a local body: the CLI sends the files and the answers to the draft route, with no revision id, and the server stores nothing.
func TestItemGradeFileSendsTheLocalItemToTheDraftRoute(t *testing.T) {
	srv, g := newGradeServer(t, 200, `{"draft":true,"read_only":true,"results":[{"instance":1,"verdict":"correct"}]}`)
	dir := t.TempDir()
	write := func(name, text string) {
		t.Helper()
		path := filepath.Join(dir, name)
		if err := os.MkdirAll(filepath.Dir(path), 0o755); err != nil {
			t.Fatal(err)
		}
		if err := os.WriteFile(path, []byte(text), 0o600); err != nil {
			t.Fatal(err)
		}
	}
	write("item.json", `{"subject":"english"}`)
	write("generator.mjs", "export default {}")
	write("verify.mjs", "export default {}")
	write("variant.json", `{"subject":"english","variant":true}`)
	write("notes.txt", "not sent")

	res := runItemShotsCLI(t, srv.URL, "item", "grade", "--file", dir, "--instance", "2", "--answer", "'s scared")
	if res.exit != 0 {
		t.Fatalf("exit %d, stderr %s", res.exit, res.stderr)
	}
	if g.method != "POST" || g.path != "/api/v1/item-grade" || g.calls != 1 {
		t.Errorf("one POST to the draft route: %s %s (%d calls)", g.method, g.path, g.calls)
	}
	want := map[string]any{
		"files":   map[string]any{"item.json": `{"subject":"english"}`, "generator.mjs": "export default {}"},
		"answers": []any{map[string]any{"instance": float64(2), "answer": "'s scared"}},
	}
	if !reflect.DeepEqual(g.body, want) {
		t.Errorf("body %v, want %v", g.body, want)
	}
	if !strings.Contains(res.stdout, `"draft":true`) {
		t.Errorf("stdout is the server's answer: %q", res.stdout)
	}

	// a lone JSON file is the item.json of the variant; the generator comes from its folder
	if res = runItemShotsCLI(t, srv.URL, "item", "grade", "--file", filepath.Join(dir, "variant.json"), "--instance", "1", "--answer", "x"); res.exit != 0 {
		t.Fatalf("variant: exit %d, stderr %s", res.exit, res.stderr)
	}
	files, _ := g.body["files"].(map[string]any)
	if files["item.json"] != `{"subject":"english","variant":true}` || files["generator.mjs"] != "export default {}" || files["verify.mjs"] != nil {
		t.Errorf("variant files %v", files)
	}

	// with --answers-file, and refused when a revision id is given too or the folder holds no item
	answers := filepath.Join(dir, "answers.json")
	write("answers.json", `[{"instance":1,"answer":"a"},{"instance":2,"answer":"b"}]`)
	if res = runItemShotsCLI(t, srv.URL, "item", "grade", "--file", dir, "--answers-file", answers); res.exit != 0 {
		t.Fatalf("answers-file: exit %d, stderr %s", res.exit, res.stderr)
	}
	if list, _ := g.body["answers"].([]any); len(list) != 2 {
		t.Errorf("answers %v", g.body["answers"])
	}
	calls := g.calls
	for _, args := range [][]string{
		{"item", "grade", "12", "--file", dir, "--instance", "1", "--answer", "x"},
		{"item", "grade", "--file", t.TempDir(), "--instance", "1", "--answer", "x"},
		{"item", "grade", "--file", filepath.Join(dir, "missing.json"), "--instance", "1", "--answer", "x"},
		{"item", "grade", "--instance", "1", "--answer", "x"},
	} {
		if res = runItemShotsCLI(t, srv.URL, args...); res.exit != ExitUsage {
			t.Errorf("%v: exit %d stderr %s", args, res.exit, res.stderr)
		}
	}
	if g.calls != calls {
		t.Errorf("a usage error sends nothing: %d calls", g.calls-calls)
	}
}

func TestLessonGradeFileSendsTheLessonMdToTheDraftRoute(t *testing.T) {
	srv, g := newGradeServer(t, 200, `{"draft":true,"read_only":true,"results":[]}`)
	dir := t.TempDir()
	file := filepath.Join(dir, "lesson.md")
	if err := os.WriteFile(file, []byte("---\nschema: banco.lesson/2\n---\n"), 0o600); err != nil {
		t.Fatal(err)
	}
	want := map[string]any{
		"files":   map[string]any{"lesson.md": "---\nschema: banco.lesson/2\n---\n"},
		"answers": []any{map[string]any{"check": "1.2", "answer": "porque", "ids": "lesson"}},
	}
	for _, target := range []string{file, dir} {
		g.calls = 0
		res := runItemShotsCLI(t, srv.URL, "lesson", "grade", "--file", target, "--check", "1.2", "--answer", "porque", "--ids", "lesson")
		if res.exit != 0 {
			t.Fatalf("%s: exit %d, stderr %s", target, res.exit, res.stderr)
		}
		if g.method != "POST" || g.path != "/api/v1/lesson-grade" || g.calls != 1 || !reflect.DeepEqual(g.body, want) {
			t.Errorf("%s: %s %s (%d calls) body %v, want %v", target, g.method, g.path, g.calls, g.body, want)
		}
	}
	g.calls = 0
	for _, args := range [][]string{
		{"lesson", "grade", "40", "--file", file, "--check", "1.1", "--answer", "x"},
		{"lesson", "grade", "--file", filepath.Join(dir, "none.md"), "--check", "1.1", "--answer", "x"},
		{"lesson", "grade", "--file", file, "--check", "1.1", "--answer", "x", "--ids", "both"},
		{"lesson", "grade", "40", "--check", "1.1", "--answer", "x", "--answers-file", file, "--ids", "shown"},
		{"item", "grade", "12", "--instance", "1", "--answer", "x", "--ids", "lesson"},
	} {
		if res := runItemShotsCLI(t, srv.URL, args...); res.exit != ExitUsage {
			t.Errorf("%v: exit %d stderr %s", args, res.exit, res.stderr)
		}
	}
	if g.calls != 0 {
		t.Errorf("a usage error sends nothing: %d calls", g.calls)
	}
}
