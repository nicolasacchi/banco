package main

import (
	"flag"
	"io"
)

// runStatus prints where each subject stands: stage (drafting, validating,
// in_review, awaiting_teacher, approved), approvals and item counts
// (GET /api/v1/status). The content agent stops at awaiting_teacher: no command
// goes further. --json is accepted and changes nothing.
func runStatus(e *env, args []string) error {
	fs := flag.NewFlagSet("status", flag.ContinueOnError)
	fs.SetOutput(io.Discard)
	fs.Bool("json", false, "JSON output (the default)")
	pos, err := parseFlags(fs, args)
	if err != nil {
		return err
	}
	if len(pos) > 0 {
		return newErr(ExitUsage, "E-USAGE", "args", "status takes no arguments", "banco status --json")
	}
	body, err := e.client().do("status", "GET", "/api/v1/status")
	if err != nil {
		return err
	}
	_, err = e.stdout.Write(append(body, '\n'))
	return err
}
