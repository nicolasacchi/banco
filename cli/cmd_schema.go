package main

import (
	"flag"
	"io"
)

// runSchema prints the contract the server serves (GET /api/v1/schema).
func runSchema(e *env, args []string) error {
	fs := flag.NewFlagSet("schema", flag.ContinueOnError)
	fs.SetOutput(io.Discard)
	pos, err := parseFlags(fs, args)
	if err != nil {
		return err
	}
	if len(pos) > 0 {
		return newErr(ExitUsage, "E-USAGE", "args", "schema takes no arguments", "banco schema")
	}
	body, err := e.client().do("schema", "GET", "/api/v1/schema")
	if err != nil {
		return err
	}
	_, err = e.stdout.Write(append(body, '\n'))
	return err
}
