package main

import (
	"encoding/json"
	"flag"
	"io"
	"net/url"
	"os"
	"regexp"
)

// The course formats of Phase 1b (D-223..D-232): course maps, lessons, lesson reviews, topics and
// the practice progress. None of these commands decides anything: the teacher approves topics and
// opens the course in the browser (firm rule 2). The contract lists all twelve. The two commands
// that work on a lesson folder (lesson open, lesson submit) land with the server side in S1b and
// answer E-NOT-AVAILABLE until then.

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

// runLessonOpen and runLessonSubmit check their arguments and stop: the folder handling
// (lesson.md and .base) is S1b.
func runLessonOpen(e *env, args []string) error {
	fs := flag.NewFlagSet("lesson open", flag.ContinueOnError)
	fs.SetOutput(io.Discard)
	fs.String("dir", "", "folder for lesson.md (default $TMPDIR/banco-work/lesson-KEY)")
	fs.Bool("json", false, "JSON output (the default)")
	pos, err := parseFlags(fs, args)
	if err != nil {
		return err
	}
	const next = "banco lesson open ripasso.math.linear-equations-integer"
	if len(pos) != 1 || !lessonKeyRe.MatchString(pos[0]) {
		return newErr(ExitUsage, "E-USAGE", "lesson", "lesson open takes one lesson key such as ripasso.math.linear-equations-integer", next)
	}
	return notAvailable("lesson open")
}

func runLessonSubmit(e *env, args []string) error {
	fs := flag.NewFlagSet("lesson submit", flag.ContinueOnError)
	fs.SetOutput(io.Discard)
	fs.String("base", "", "the revision the folder is based on (default: DIR/.base)")
	fs.Bool("dry-run", false, "validate and store nothing")
	fs.Bool("json", false, "JSON output (the default)")
	pos, err := parseFlags(fs, args)
	if err != nil {
		return err
	}
	if len(pos) != 1 {
		return newErr(ExitUsage, "E-USAGE", "dir", "lesson submit takes one folder with lesson.md", "banco lesson submit DIR --dry-run")
	}
	return notAvailable("lesson submit")
}

func notAvailable(name string) error {
	return newErr(ExitServer, "E-NOT-AVAILABLE", "", name+" is not available in this build yet", "banco status")
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
