package main

import (
	"flag"
	"io"
	"net/url"
)

// The teacher's pages and the student's progress as JSON (D-328): read-only commands, any token role may run them.
// They show what the teacher sees in the browser and what the student sees on their own pages.

// runTeacherHome prints the dashboard: what waits for the teacher, subject by subject.
func runTeacherHome(e *env, args []string) error {
	fs := flag.NewFlagSet("teacher home", flag.ContinueOnError)
	fs.SetOutput(io.Discard)
	student := fs.String("student", "", "a trial student key (default: the official student)")
	fs.Bool("json", false, "JSON output (the default)")
	pos, err := parseFlags(fs, args)
	if err != nil {
		return err
	}
	const next = "banco teacher home"
	if len(pos) != 0 {
		return newErr(ExitUsage, "E-USAGE", "args", "teacher home takes no positional argument", next)
	}
	path := "/api/v1/teacher/home"
	if *student != "" {
		if !studentKeyRe.MatchString(*student) {
			return newErr(ExitUsage, "E-USAGE", "student", "--student is a student key such as trial-1", next)
		}
		path += "?" + url.Values{"student": {*student}}.Encode()
	}
	return send(e, "teacher home", "GET", path, nil, false)
}

// runTeacherCourse prints the path of a subject's course: each topic's stage, badge and gate reasons.
func runTeacherCourse(e *env, args []string) error {
	fs := flag.NewFlagSet("teacher course", flag.ContinueOnError)
	fs.SetOutput(io.Discard)
	only := fs.Bool("only-ready", false, "only the topics that wait for the teacher")
	fs.Bool("json", false, "JSON output (the default)")
	pos, err := parseFlags(fs, args)
	if err != nil {
		return err
	}
	const next = "banco teacher course math"
	if len(pos) != 1 || !subjectRe.MatchString(pos[0]) {
		return newErr(ExitUsage, "E-USAGE", "subject", "give one subject key, for example: banco teacher course math", next)
	}
	path := "/api/v1/teacher/subjects/" + url.PathEscape(pos[0]) + "/course"
	if *only {
		path += "?only=ready"
	}
	return send(e, "teacher course", "GET", path, nil, false)
}

// runTeacherTopic prints one topic as the teacher reviews it; --lesson adds the lesson's text.
func runTeacherTopic(e *env, args []string) error {
	fs := flag.NewFlagSet("teacher topic", flag.ContinueOnError)
	fs.SetOutput(io.Discard)
	lesson := fs.Bool("lesson", false, "include the whole lesson body")
	fs.Bool("json", false, "JSON output (the default)")
	pos, err := parseFlags(fs, args)
	if err != nil {
		return err
	}
	const next = "banco teacher topic math ripasso.math.linear-equations-integer"
	if len(pos) != 2 || !subjectRe.MatchString(pos[0]) {
		return newErr(ExitUsage, "E-USAGE", "args", "give a subject key and a topic key: banco teacher topic SUBJECT TOPIC", next)
	}
	if !lessonKeyRe.MatchString(pos[1]) {
		return newErr(ExitUsage, "E-USAGE", "topic", "a topic key such as ripasso.math.linear-equations-integer", next)
	}
	path := "/api/v1/teacher/subjects/" + url.PathEscape(pos[0]) + "/topics/" + url.PathEscape(pos[1])
	if *lesson {
		path += "?lesson=full"
	}
	return send(e, "teacher topic", "GET", path, nil, false)
}

// runTeacherTest prints the entry test of a subject as the teacher reviews it.
func runTeacherTest(e *env, args []string) error {
	fs := flag.NewFlagSet("teacher test", flag.ContinueOnError)
	fs.SetOutput(io.Discard)
	fs.Bool("json", false, "JSON output (the default)")
	pos, err := parseFlags(fs, args)
	if err != nil {
		return err
	}
	const next = "banco teacher test math"
	if len(pos) != 1 || !subjectRe.MatchString(pos[0]) {
		return newErr(ExitUsage, "E-USAGE", "subject", "give one subject key, for example: banco teacher test math", next)
	}
	return send(e, "teacher test", "GET", "/api/v1/teacher/subjects/"+url.PathEscape(pos[0])+"/test", nil, false)
}

// runProgress prints what a student sees of their progress: topics by status, the entry tests, the skill states.
func runProgress(e *env, args []string) error {
	fs := flag.NewFlagSet("progress", flag.ContinueOnError)
	fs.SetOutput(io.Discard)
	student := fs.String("student", "student", "a student key (default: the official student, key student)")
	fs.Bool("json", false, "JSON output (the default)")
	pos, err := parseFlags(fs, args)
	if err != nil {
		return err
	}
	const next = "banco progress"
	if len(pos) != 0 {
		return newErr(ExitUsage, "E-USAGE", "args", "progress takes no positional argument", next)
	}
	if !studentKeyRe.MatchString(*student) {
		return newErr(ExitUsage, "E-USAGE", "student", "--student is a student key such as trial-1", next)
	}
	return send(e, "progress", "GET", "/api/v1/students/"+url.PathEscape(*student)+"/progress", nil, false)
}
