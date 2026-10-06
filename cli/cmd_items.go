package main

import (
	"flag"
	"io"
	"net/url"
)

// runItemsList prints every revision of the items (of one subject), with the status
// of its latest validation, whether it is the current revision of its item, and the
// number of reviews and blind solves (GET /api/v1/items). It tells a reviewer which
// revision ids to open with banco review open.
func runItemsList(e *env, args []string) error {
	fs := flag.NewFlagSet("items list", flag.ContinueOnError)
	fs.SetOutput(io.Discard)
	subject := fs.String("subject", "", "subject key, for example math")
	current := fs.Bool("current", false, "only the current (latest) revision of each item")
	fs.Bool("json", false, "JSON output (the default)")
	pos, err := parseFlags(fs, args)
	if err != nil {
		return err
	}
	const next = "banco items list --subject math --current"
	if *subject != "" && !subjectKeyRe.MatchString(*subject) {
		return newErr(ExitUsage, "E-USAGE", "subject", "--subject is a subject key (see banco status)", next)
	}
	if len(pos) != 0 {
		return newErr(ExitUsage, "E-USAGE", "args", "items list takes no positional argument", next)
	}
	query := url.Values{}
	if *subject != "" {
		query.Set("subject", *subject)
	}
	if *current {
		query.Set("current", "1")
	}
	path := "/api/v1/items"
	if len(query) > 0 {
		path += "?" + query.Encode()
	}
	body, err := e.client().do("items list", "GET", path)
	if err != nil {
		return err
	}
	_, err = e.stdout.Write(append(body, '\n'))
	return err
}
