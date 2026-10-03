package main

import (
	"flag"
	"io"
	"net/url"
	"regexp"
	"strings"
)

// runBriefShow prints the authoring brief a content agent starts from
// (GET /api/v1/briefs/:name). The answer is JSON {name, version, sha256, body};
// --json is accepted for symmetry with the other commands and changes nothing.
func runBriefShow(e *env, args []string) error {
	fs := flag.NewFlagSet("brief show", flag.ContinueOnError)
	fs.SetOutput(io.Discard)
	fs.Bool("json", false, "JSON output (the default)")
	pos, err := parseFlags(fs, args)
	if err != nil {
		return err
	}
	if len(pos) != 1 || pos[0] == "" {
		return newErr(ExitUsage, "E-USAGE", "name", "brief show takes exactly one brief name", "banco brief show diagnosis-item")
	}
	if !briefNameRe.MatchString(pos[0]) {
		return newErr(ExitUsage, "E-USAGE", "name", "a brief name is lowercase letters, digits, - and _", "banco brief show diagnosis-item")
	}
	path := strings.Replace("/api/v1/briefs/:name", ":name", url.PathEscape(pos[0]), 1)
	body, err := e.client().do("brief show", "GET", path)
	if err != nil {
		return err
	}
	_, err = e.stdout.Write(append(body, '\n'))
	return err
}

var briefNameRe = regexp.MustCompile(`^[a-z0-9][a-z0-9_-]*$`)
