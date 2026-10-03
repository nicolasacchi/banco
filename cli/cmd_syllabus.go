package main

import (
	"flag"
	"io"
	"net/url"
	"regexp"
	"strconv"
)

var sourceRe = regexp.MustCompile(`^[a-z0-9][a-z0-9-]*$`)

// runSyllabusLines prints lines of an imported programme, so that a skill graph can
// cite them exactly (GET /api/v1/syllabus/:source/lines). Transcriber lines come
// with citable: false.
func runSyllabusLines(e *env, args []string) error {
	fs := flag.NewFlagSet("syllabus lines", flag.ContinueOnError)
	fs.SetOutput(io.Discard)
	source := fs.String("source", "", "programme key, for example prima-2025-26")
	from := fs.Int("from", 0, "first line")
	to := fs.Int("to", 0, "last line")
	fs.Bool("json", false, "JSON output (the default)")
	pos, err := parseFlags(fs, args)
	if err != nil {
		return err
	}
	const next = "banco syllabus lines --source KEY --from 1 --to 50"
	if !sourceRe.MatchString(*source) {
		return newErr(ExitUsage, "E-USAGE", "source", "give --source KEY (see banco skill-graph open --subject KEY)", next)
	}
	if len(pos) != 0 {
		return newErr(ExitUsage, "E-USAGE", "args", "syllabus lines takes no positional argument", next)
	}
	query := url.Values{}
	if *from != 0 {
		query.Set("from", strconv.Itoa(*from))
	}
	if *to != 0 {
		query.Set("to", strconv.Itoa(*to))
	}
	path := "/api/v1/syllabus/" + url.PathEscape(*source) + "/lines"
	if len(query) > 0 {
		path += "?" + query.Encode()
	}
	body, err := e.client().do("syllabus lines", "GET", path)
	if err != nil {
		return err
	}
	_, err = e.stdout.Write(append(body, '\n'))
	return err
}
