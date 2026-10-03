package main

import (
	"flag"
	"io"
)

// runHealth prints whether the installation is fit to serve (GET /api/v1/health):
// database, queue, grader, Chrome and its egress, disk, backup, the decisions flag.
// The answer is JSON with "ok"; the exit code is 0 either way, because the report
// is the answer (use jq -e .ok to gate). --no-chrome leaves the browser out.
func runHealth(e *env, args []string) error {
	fs := flag.NewFlagSet("health", flag.ContinueOnError)
	fs.SetOutput(io.Discard)
	noChrome := fs.Bool("no-chrome", false, "skip the Chrome and egress checks")
	fs.Bool("json", false, "JSON output (the default)")
	pos, err := parseFlags(fs, args)
	if err != nil {
		return err
	}
	if len(pos) > 0 {
		return newErr(ExitUsage, "E-USAGE", "args", "health takes no arguments", "banco health --json")
	}
	path := "/api/v1/health"
	if *noChrome {
		path += "?chrome=0"
	}
	body, err := e.client().do("health", "GET", path)
	if err != nil {
		return err
	}
	_, err = e.stdout.Write(append(body, '\n'))
	return err
}
