package main

import (
	"flag"
	"io"
)

func newTestFlagSet() *flag.FlagSet {
	fs := flag.NewFlagSet("t", flag.ContinueOnError)
	fs.SetOutput(io.Discard)
	fs.Bool("json", false, "")
	return fs
}
