package main

import (
	"encoding/json"
	"flag"
	"io"
	"net/url"
	"os"
	"regexp"
)

var subjectRe = regexp.MustCompile(`^[a-z_]+$`)

// subjectCommand is one of the commands that work on a subject's graph or entry
// test: skill-graph open|submit|coverage and blueprint open|submit. They differ in
// the path, the method and whether a file is sent.
type subjectCommand struct {
	name   string // "skill-graph submit"
	method string
	path   string // after /api/v1/subjects/:subject
	member string // JSON member the file goes under ("graph", "blueprint"), "" for reads
	next   string
}

var subjectCommands = map[string]subjectCommand{
	"skill-graph open":     {"skill-graph open", "GET", "/skill-graph", "", "banco skill-graph open --subject KEY"},
	"skill-graph submit":   {"skill-graph submit", "POST", "/skill-graph", "graph", "banco skill-graph submit --subject KEY FILE --dry-run"},
	"skill-graph coverage": {"skill-graph coverage", "GET", "/skill-graph/coverage", "", "banco skill-graph coverage --subject KEY"},
	"blueprint open":       {"blueprint open", "GET", "/blueprint", "", "banco blueprint open --subject KEY"},
	"blueprint submit":     {"blueprint submit", "POST", "/blueprint", "blueprint", "banco blueprint submit --subject KEY FILE --dry-run"},
	// The course formats of Phase 1b (D-223..D-232); see cmd_course.go.
	"course open":   {"course open", "GET", "/course", "", "banco course open --subject KEY"},
	"course submit": {"course submit", "POST", "/course", "course", "banco course submit --subject KEY FILE --dry-run"},
	"lessons list":  {"lessons list", "GET", "/lessons", "", "banco lessons list --subject KEY"},
	"topics list":   {"topics list", "GET", "/topics", "", "banco topics list --subject KEY"},
}

func runSkillGraphOpen(e *env, a []string) error {
	return runSubject(e, subjectCommands["skill-graph open"], a)
}
func runSkillGraphSubmit(e *env, a []string) error {
	return runSubject(e, subjectCommands["skill-graph submit"], a)
}
func runSkillGraphCoverage(e *env, a []string) error {
	return runSubject(e, subjectCommands["skill-graph coverage"], a)
}
func runBlueprintOpen(e *env, a []string) error {
	return runSubject(e, subjectCommands["blueprint open"], a)
}
func runBlueprintSubmit(e *env, a []string) error {
	return runSubject(e, subjectCommands["blueprint submit"], a)
}

func runSubject(e *env, c subjectCommand, args []string) error {
	fs := flag.NewFlagSet(c.name, flag.ContinueOnError)
	fs.SetOutput(io.Discard)
	subject := fs.String("subject", "", "subject key, for example math")
	dry := fs.Bool("dry-run", false, "validate and store nothing")
	fs.Bool("json", false, "JSON output (the default)")
	pos, err := parseFlags(fs, args)
	if err != nil {
		return err
	}
	if !subjectRe.MatchString(*subject) {
		return newErr(ExitUsage, "E-USAGE", "subject", "give --subject KEY (a subject key such as math)", c.next)
	}
	if *dry && c.member == "" {
		return newErr(ExitUsage, "E-USAGE", "dry-run", c.name+" reads: --dry-run is for submit", c.next)
	}
	path := "/api/v1/subjects/" + url.PathEscape(*subject) + c.path
	var payload []byte
	if c.member == "" {
		if len(pos) != 0 {
			return newErr(ExitUsage, "E-USAGE", "args", c.name+" takes no file", c.next)
		}
	} else {
		if len(pos) != 1 {
			return newErr(ExitUsage, "E-USAGE", "file", c.name+" takes exactly one JSON file", c.next)
		}
		raw, err := os.ReadFile(pos[0])
		if err != nil {
			return newErr(ExitUsage, "E-USAGE", "file", "cannot read "+pos[0]+": "+err.Error(), c.next)
		}
		var doc any
		if err := json.Unmarshal(raw, &doc); err != nil {
			return newErr(ExitValidation, "E-FILES", "file", pos[0]+" is not JSON: "+err.Error(), "fix the file")
		}
		payload, _ = json.Marshal(map[string]any{c.member: doc})
	}
	headers := map[string]string{}
	if *dry {
		headers["X-Banco-Dry-Run"] = "1"
	}
	out, err := e.client().doWith(c.name, c.method, path, payload, headers)
	if err != nil {
		return err
	}
	_, err = e.stdout.Write(append(out, '\n'))
	return err
}
