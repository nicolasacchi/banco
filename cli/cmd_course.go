package main

import (
	"encoding/json"
	"flag"
	"io"
	"net/url"
	"os"
	"path/filepath"
	"regexp"
	"strconv"
	"strings"
)

// The course formats of Phase 1b (D-223..D-232): course maps, lessons, lesson reviews, topics and
// the practice progress. None of these commands decides anything: the teacher approves topics and
// opens the course in the browser (firm rule 2). The contract lists all twelve.

var lessonKeyRe = regexp.MustCompile(`^(ripasso|ponte|lezione)\.[a-z_]+\.[a-z0-9]+(-[a-z0-9]+)*$`)

func runCourseOpen(e *env, a []string) error {
	return runSubject(e, subjectCommands["course open"], a)
}
func runCourseSubmit(e *env, a []string) error {
	return runSubject(e, subjectCommands["course submit"], a)
}
func runLessonsList(e *env, a []string) error {
	return runSubject(e, subjectCommands["lessons list"], a)
}
func runTopicsList(e *env, a []string) error {
	return runSubject(e, subjectCommands["topics list"], a)
}

// A lesson folder holds lesson.md and .base (the revision it is based on). `lesson open` writes both;
// `lesson submit` reads them and, after a stored revision, writes the new .base.
const lessonFile = "lesson.md"
const baseFile = ".base"

var frontKeyRe = regexp.MustCompile(`(?m)^key:\s*["']?([^"'\s]+)["']?\s*$`)

func runLessonOpen(e *env, args []string) error {
	fs := flag.NewFlagSet("lesson open", flag.ContinueOnError)
	fs.SetOutput(io.Discard)
	dir := fs.String("dir", "", "folder for lesson.md (default $TMPDIR/banco-work/lesson-KEY)")
	fs.Bool("json", false, "JSON output (the default)")
	pos, err := parseFlags(fs, args)
	if err != nil {
		return err
	}
	const next = "banco lesson open ripasso.math.linear-equations-integer"
	if len(pos) != 1 || !lessonKeyRe.MatchString(pos[0]) {
		return newErr(ExitUsage, "E-USAGE", "lesson", "lesson open takes one lesson key such as ripasso.math.linear-equations-integer", next)
	}
	key := pos[0]
	target := *dir
	if target == "" {
		target = filepath.Join(os.TempDir(), "banco-work", "lesson-"+key)
	}
	if entries, err := os.ReadDir(target); err == nil {
		for _, ent := range entries {
			if ent.Name() != lessonFile && ent.Name() != baseFile {
				return newErr(ExitUsage, "E-USAGE", "dir", target+" holds "+ent.Name()+" and is not a lesson folder", "banco lesson open "+key+" --dir OTHER")
			}
		}
	}
	body, err := e.client().do("lesson open", "GET", "/api/v1/lessons/"+url.PathEscape(key))
	if err != nil {
		return err
	}
	var answer struct {
		Lesson   string            `json:"lesson"`
		Kind     string            `json:"kind"`
		Subject  string            `json:"subject"`
		Files    map[string]string `json:"files"`
		Latest   json.RawMessage   `json:"latest"`
		Reviews  json.RawMessage   `json:"reviews"`
		Comments json.RawMessage   `json:"teacher_comments"`
		Next     string            `json:"next"`
	}
	if err := json.Unmarshal(body, &answer); err != nil {
		return newErr(ExitServer, "E-HTTP", "", "the server's answer is not JSON: "+err.Error(), "banco health")
	}
	text, ok := answer.Files[lessonFile]
	if !ok {
		return newErr(ExitServer, "E-HTTP", "files", "the server sent no lesson.md", "banco health")
	}
	var latest struct {
		RevisionID int `json:"revision_id"`
	}
	_ = json.Unmarshal(answer.Latest, &latest)
	if err := writeFile(filepath.Join(target, lessonFile), []byte(text)); err != nil {
		return err
	}
	if err := writeFile(filepath.Join(target, baseFile), []byte(strconv.Itoa(latest.RevisionID)+"\n")); err != nil {
		return err
	}
	out := map[string]any{
		"lesson": answer.Lesson, "kind": answer.Kind, "subject": answer.Subject, "dir": target, "latest": answer.Latest,
		"reviews": answer.Reviews, "teacher_comments": answer.Comments,
		"next": "edit " + filepath.Join(target, lessonFile) + ", then banco lesson submit " + target + " --dry-run",
	}
	if root := gitRootAbove(target); root != "" {
		out["warning"] = "the folder " + target + " is inside the git work tree " + root + ": nothing of the work may be committed there; use --dir OUTSIDE/lesson and delete this folder"
	}
	return json.NewEncoder(e.stdout).Encode(out)
}

func runLessonSubmit(e *env, args []string) error {
	fs := flag.NewFlagSet("lesson submit", flag.ContinueOnError)
	fs.SetOutput(io.Discard)
	baseFlag := fs.String("base", "", "the revision the folder is based on (default: DIR/.base)")
	dry := fs.Bool("dry-run", false, "validate and store nothing")
	fs.Bool("json", false, "JSON output (the default)")
	pos, err := parseFlags(fs, args)
	if err != nil {
		return err
	}
	const next = "banco lesson submit DIR --dry-run"
	if len(pos) != 1 {
		return newErr(ExitUsage, "E-USAGE", "dir", "lesson submit takes exactly one folder with lesson.md", next)
	}
	dir := pos[0]
	raw, err := os.ReadFile(filepath.Join(dir, lessonFile))
	if err != nil {
		return newErr(ExitUsage, "E-USAGE", "dir", "cannot read "+filepath.Join(dir, lessonFile)+": "+err.Error(), next)
	}
	front := string(raw)
	if i := strings.Index(front[min(4, len(front)):], "\n---"); strings.HasPrefix(front, "---") && i >= 0 {
		front = front[:i+4]
	}
	m := frontKeyRe.FindStringSubmatch(front)
	if m == nil || !lessonKeyRe.MatchString(m[1]) {
		return newErr(ExitValidation, "E-LESSON-PARSE", "key", "lesson.md has no valid key: in its front matter (a lesson key such as ripasso.math.linear-equations-integer)", next)
	}
	var base any
	baseText := strings.TrimSpace(*baseFlag)
	if baseText == "" {
		if saved, err := os.ReadFile(filepath.Join(dir, baseFile)); err == nil {
			baseText = strings.TrimSpace(string(saved))
		}
	}
	if baseText != "" {
		n, err := strconv.Atoi(baseText)
		if err != nil {
			return newErr(ExitUsage, "E-USAGE", "base", "the base is a revision id (a number)", next)
		}
		base = n
	}
	payload, _ := json.Marshal(map[string]any{"lesson": m[1], "base": base, "files": map[string]string{lessonFile: string(raw)}})
	headers := map[string]string{}
	if *dry {
		headers["X-Banco-Dry-Run"] = "1"
	}
	out, err := e.client().doWith("lesson submit", "POST", "/api/v1/lessons/submit", payload, headers)
	if err != nil {
		return err
	}
	if !*dry {
		var answer struct {
			RevisionID int `json:"revision_id"`
		}
		if json.Unmarshal(out, &answer) == nil && answer.RevisionID != 0 {
			_ = os.WriteFile(filepath.Join(dir, baseFile), []byte(strconv.Itoa(answer.RevisionID)+"\n"), 0o644)
		}
	}
	_, err = e.stdout.Write(append(out, '\n'))
	return err
}

func runLessonStatus(e *env, args []string) error {
	return runKeyed(e, keyedCommand{"lesson status", "/api/v1/lesson-revisions/", "", "", idRe, "revision", "a revision id (a number)", "banco lesson status REV"}, args)
}
func runLessonReviewOpen(e *env, args []string) error {
	return runKeyed(e, keyedCommand{"lesson-review open", "/api/v1/lesson-revisions/", "/review", "", idRe, "revision", "a revision id (a number)", "banco lesson-review open REV"}, args)
}
func runLessonReviewSubmit(e *env, args []string) error {
	return runKeyed(e, keyedCommand{"lesson-review submit", "/api/v1/lesson-revisions/", "/review", "review", idRe, "revision", "a revision id (a number)", "banco lesson-review submit REV --file review.json"}, args)
}
func runTopicOpen(e *env, args []string) error {
	return runKeyed(e, keyedCommand{"topic open", "/api/v1/topics/", "", "", lessonKeyRe, "topic", "a topic key such as ripasso.math.linear-equations-integer", "banco topic open ripasso.math.linear-equations-integer"}, args)
}

// runTopicSubmit sends topic.json; the topic key comes from the file's "key".
func runTopicSubmit(e *env, args []string) error {
	fs := flag.NewFlagSet("topic submit", flag.ContinueOnError)
	fs.SetOutput(io.Discard)
	dry := fs.Bool("dry-run", false, "validate and store nothing")
	fs.Bool("json", false, "JSON output (the default)")
	pos, err := parseFlags(fs, args)
	if err != nil {
		return err
	}
	const next = "banco topic submit topic.json --dry-run"
	if len(pos) != 1 {
		return newErr(ExitUsage, "E-USAGE", "file", "topic submit takes exactly one JSON file", next)
	}
	raw, err := os.ReadFile(pos[0])
	if err != nil {
		return newErr(ExitUsage, "E-USAGE", "file", "cannot read "+pos[0]+": "+err.Error(), next)
	}
	var doc map[string]any
	if err := json.Unmarshal(raw, &doc); err != nil {
		return newErr(ExitValidation, "E-FILES", "file", pos[0]+" is not a JSON object: "+err.Error(), "fix the file")
	}
	key, _ := doc["key"].(string)
	if !lessonKeyRe.MatchString(key) {
		return newErr(ExitValidation, "E-FILES", "key", "the file has no valid \"key\" (a topic key such as ripasso.math.linear-equations-integer)", next)
	}
	payload, _ := json.Marshal(map[string]any{"topic": doc})
	return send(e, "topic submit", "POST", "/api/v1/topics/"+url.PathEscape(key), payload, *dry)
}

// runPracticeProgress prints the derived state of every skill of a subject for the official
// student, or for a trial student with --student KEY. It carries no student text (D-064).
func runPracticeProgress(e *env, args []string) error {
	fs := flag.NewFlagSet("practice progress", flag.ContinueOnError)
	fs.SetOutput(io.Discard)
	subject := fs.String("subject", "", "subject key, for example math")
	student := fs.String("student", "", "a trial student key (default: the official student)")
	fs.Bool("json", false, "JSON output (the default)")
	pos, err := parseFlags(fs, args)
	if err != nil {
		return err
	}
	const next = "banco practice progress --subject math"
	if !subjectRe.MatchString(*subject) {
		return newErr(ExitUsage, "E-USAGE", "subject", "give --subject KEY (a subject key such as math)", next)
	}
	if len(pos) != 0 {
		return newErr(ExitUsage, "E-USAGE", "args", "practice progress takes no positional argument", next)
	}
	path := "/api/v1/subjects/" + url.PathEscape(*subject) + "/practice/progress"
	if *student != "" {
		if !studentKeyRe.MatchString(*student) {
			return newErr(ExitUsage, "E-USAGE", "student", "--student is a student key such as trial-1", next)
		}
		path += "?" + url.Values{"student": {*student}}.Encode()
	}
	return send(e, "practice progress", "GET", path, nil, false)
}

// keyedCommand is a command on one thing named by a positional argument: a lesson revision, a
// topic. member "" reads; otherwise --file is wrapped as {member: document} and sent.
type keyedCommand struct {
	name, prefix, suffix, member string
	re                           *regexp.Regexp
	field, what, next            string
}

func runKeyed(e *env, c keyedCommand, args []string) error {
	fs := flag.NewFlagSet(c.name, flag.ContinueOnError)
	fs.SetOutput(io.Discard)
	file := fs.String("file", "", "the JSON file to send")
	dry := fs.Bool("dry-run", false, "check and store nothing")
	fs.Bool("json", false, "JSON output (the default)")
	pos, err := parseFlags(fs, args)
	if err != nil {
		return err
	}
	if len(pos) != 1 || !c.re.MatchString(pos[0]) {
		return newErr(ExitUsage, "E-USAGE", c.field, c.name+" takes one argument: "+c.what, c.next)
	}
	path := c.prefix + url.PathEscape(pos[0]) + c.suffix
	if c.member == "" {
		if *file != "" || *dry {
			return newErr(ExitUsage, "E-USAGE", "args", c.name+" reads: --file and --dry-run are for submit", c.next)
		}
		return send(e, c.name, "GET", path, nil, false)
	}
	payload, err := fileBody(*file, c.member, c.next)
	if err != nil {
		return err
	}
	return send(e, c.name, "POST", path, payload, *dry)
}
