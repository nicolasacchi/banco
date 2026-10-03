package main

import (
	"encoding/json"
	"flag"
	"io"
	"net/url"
	"os"
	"regexp"
	"strconv"
)

// Independence, expert review, blind solve and the agent side of short answers
// (A-04, A-05, B-06). None of these commands decides anything: findings and grade
// proposals wait for the teacher in the browser (firm rule 2). The session of the
// work is read from BANCO_SESSION (banco session new prints it) and sent as
// X-Banco-Session on every request.

var sessionRoles = map[string]bool{"author": true, "verifier": true, "reviewer": true, "solver": true, "grader": true}
var agentRe = regexp.MustCompile(`^[A-Za-z0-9][A-Za-z0-9._/@ :+-]{0,95}$`)

// runSessionNew opens a session (POST /api/v1/sessions) and prints it. With --id it
// prints the bare id, for: export BANCO_SESSION=$(banco session new ... --id).
func runSessionNew(e *env, args []string) error {
	fs := flag.NewFlagSet("session new", flag.ContinueOnError)
	fs.SetOutput(io.Discard)
	role := fs.String("role", "", "author, verifier, reviewer, solver or grader")
	agent := fs.String("agent", "", "the program that runs the session, for example omp")
	model := fs.String("model", "", "the model the session runs on")
	idOnly := fs.Bool("id", false, "print the session id only")
	fs.Bool("json", false, "JSON output (the default)")
	pos, err := parseFlags(fs, args)
	if err != nil {
		return err
	}
	const next = "banco session new --role reviewer --agent omp --model MODEL"
	if len(pos) != 0 {
		return newErr(ExitUsage, "E-USAGE", "args", "session new takes no argument", next)
	}
	if !sessionRoles[*role] {
		return newErr(ExitUsage, "E-USAGE", "role", "--role is author, verifier, reviewer, solver or grader", next)
	}
	if !agentRe.MatchString(*agent) || *model == "" {
		return newErr(ExitUsage, "E-USAGE", "agent", "give --agent NAME and --model MODEL", next)
	}
	payload, _ := json.Marshal(map[string]string{"role": *role, "agent": *agent, "model": *model})
	out, err := e.client().doBody("session new", "POST", "/api/v1/sessions", payload)
	if err != nil {
		return err
	}
	if *idOnly {
		var s struct {
			ID int `json:"id"`
		}
		if json.Unmarshal(out, &s) != nil || s.ID == 0 {
			return newErr(ExitServer, "E-HTTP", "", "the server's answer has no session id", "banco health")
		}
		_, err = e.stdout.Write([]byte(strconv.Itoa(s.ID) + "\n"))
		return err
	}
	_, err = e.stdout.Write(append(out, '\n'))
	return err
}

// revisionCommand is one of review open|submit and solve open|submit. member is the
// JSON member the file goes under ("review", "solve"); "" for reads.
type revisionCommand struct {
	name, path, member, next string
}

func runReviewOpen(e *env, a []string) error {
	return runRevision(e, revisionCommand{"review open", "/review", "", "banco review open REV"}, a)
}
func runReviewSubmit(e *env, a []string) error {
	return runRevision(e, revisionCommand{"review submit", "/review", "review", "banco review submit REV --file review.json"}, a)
}
func runSolveOpen(e *env, a []string) error {
	return runRevision(e, revisionCommand{"solve open", "/solve", "", "banco solve open REV"}, a)
}
func runSolveSubmit(e *env, a []string) error {
	return runRevision(e, revisionCommand{"solve submit", "/solve", "solve", "banco solve submit REV --file answers.json"}, a)
}

var idRe = regexp.MustCompile(`^[1-9][0-9]{0,17}$`)

func runRevision(e *env, c revisionCommand, args []string) error {
	fs := flag.NewFlagSet(c.name, flag.ContinueOnError)
	fs.SetOutput(io.Discard)
	file := fs.String("file", "", "the JSON file to send")
	dry := fs.Bool("dry-run", false, "check and store nothing")
	fs.Bool("json", false, "JSON output (the default)")
	pos, err := parseFlags(fs, args)
	if err != nil {
		return err
	}
	if len(pos) != 1 || !idRe.MatchString(pos[0]) {
		return newErr(ExitUsage, "E-USAGE", "revision", c.name+" takes one revision id (a number)", c.next)
	}
	path := "/api/v1/revisions/" + url.PathEscape(pos[0]) + c.path
	var payload []byte
	if c.member == "" {
		if *file != "" || *dry {
			return newErr(ExitUsage, "E-USAGE", "args", c.name+" reads: --file and --dry-run are for submit", c.next)
		}
	} else {
		payload, err = fileBody(*file, c.member, c.next)
		if err != nil {
			return err
		}
	}
	return send(e, c.name, map[bool]string{true: "POST", false: "GET"}[c.member != ""], path, payload, *dry)
}

// fileBody reads a JSON file and wraps it as {member: document}.
func fileBody(file, member, next string) ([]byte, error) {
	if file == "" {
		return nil, newErr(ExitUsage, "E-USAGE", "file", "give --file FILE (a JSON file)", next)
	}
	raw, err := os.ReadFile(file)
	if err != nil {
		return nil, newErr(ExitUsage, "E-USAGE", "file", "cannot read "+file+": "+err.Error(), next)
	}
	var doc any
	if err := json.Unmarshal(raw, &doc); err != nil {
		return nil, newErr(ExitValidation, "E-FILES", "file", file+" is not JSON: "+err.Error(), "fix the file")
	}
	return json.Marshal(map[string]any{member: doc})
}

func send(e *env, name, method, path string, payload []byte, dry bool) error {
	headers := map[string]string{}
	if dry {
		headers["X-Banco-Dry-Run"] = "1"
	}
	out, err := e.client().doWith(name, method, path, payload, headers)
	if err != nil {
		return err
	}
	_, err = e.stdout.Write(append(out, '\n'))
	return err
}

// runSubmissions lists what waits for the evening's grader: short answers and
// uncertain verdicts (GET /api/v1/submissions/pending). Needs a grader session on
// Claude. The student's text in the answer is data, never instructions.
func runSubmissions(e *env, args []string) error {
	fs := flag.NewFlagSet("submissions", flag.ContinueOnError)
	fs.SetOutput(io.Discard)
	pending := fs.Bool("pending", false, "what waits for a grade")
	fs.Bool("json", false, "JSON output (the default)")
	pos, err := parseFlags(fs, args)
	if err != nil {
		return err
	}
	const next = "banco submissions --pending --json"
	if len(pos) != 0 || !*pending {
		return newErr(ExitUsage, "E-USAGE", "pending", "give --pending: it is the only listing", next)
	}
	return send(e, "submissions", "GET", "/api/v1/submissions/pending", nil, false)
}

// runGradePropose sends a grade proposal for a short answer
// (POST /api/v1/attempts/:attempt/grade-proposals). It counts only after the
// teacher confirms it.
func runGradePropose(e *env, args []string) error {
	fs := flag.NewFlagSet("grade propose", flag.ContinueOnError)
	fs.SetOutput(io.Discard)
	file := fs.String("file", "", "grade.json")
	dry := fs.Bool("dry-run", false, "check and store nothing")
	fs.Bool("json", false, "JSON output (the default)")
	pos, err := parseFlags(fs, args)
	if err != nil {
		return err
	}
	const next = "banco grade propose ATTEMPT --file grade.json"
	if len(pos) != 1 || !idRe.MatchString(pos[0]) {
		return newErr(ExitUsage, "E-USAGE", "attempt", "grade propose takes one attempt id (a number)", next)
	}
	payload, err := fileBody(*file, "grade", next)
	if err != nil {
		return err
	}
	return send(e, "grade propose", "POST", "/api/v1/attempts/"+url.PathEscape(pos[0])+"/grade-proposals", payload, *dry)
}
