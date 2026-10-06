package main

import (
	"flag"
	"io"
	"net/url"
)

// runReferenceList prints the imported reference texts an item may quote through
// prompt.quote (GET /api/v1/references).
func runReferenceList(e *env, args []string) error {
	fs := flag.NewFlagSet("reference list", flag.ContinueOnError)
	fs.SetOutput(io.Discard)
	fs.Bool("json", false, "JSON output (the default)")
	pos, err := parseFlags(fs, args)
	if err != nil {
		return err
	}
	if len(pos) != 0 {
		return newErr(ExitUsage, "E-USAGE", "args", "reference list takes no argument", "banco reference list")
	}
	body, err := e.client().do("reference list", "GET", "/api/v1/references")
	if err != nil {
		return err
	}
	_, err = e.stdout.Write(append(body, '\n'))
	return err
}

// runReferenceShow prints one reference text with its body, so a quotation can be
// copied as an exact substring (GET /api/v1/references/:key).
func runReferenceShow(e *env, args []string) error {
	fs := flag.NewFlagSet("reference show", flag.ContinueOnError)
	fs.SetOutput(io.Discard)
	key := fs.String("key", "", "reference text key, for example costituzione-artt-1-12")
	fs.Bool("json", false, "JSON output (the default)")
	pos, err := parseFlags(fs, args)
	if err != nil {
		return err
	}
	const next = "banco reference show --key KEY (keys: banco reference list)"
	if !sourceRe.MatchString(*key) {
		return newErr(ExitUsage, "E-USAGE", "key", "give --key KEY (see banco reference list)", next)
	}
	if len(pos) != 0 {
		return newErr(ExitUsage, "E-USAGE", "args", "reference show takes no positional argument", next)
	}
	body, err := e.client().do("reference show", "GET", "/api/v1/references/"+url.PathEscape(*key))
	if err != nil {
		return err
	}
	_, err = e.stdout.Write(append(body, '\n'))
	return err
}
