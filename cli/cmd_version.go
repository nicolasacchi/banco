package main

import (
	"encoding/json"
	"flag"
	"io"

	"banco/contract"
)

func runVersion(e *env, args []string) error {
	fs := flag.NewFlagSet("version", flag.ContinueOnError)
	fs.SetOutput(io.Discard)
	pos, err := parseFlags(fs, args)
	if err != nil {
		return err
	}
	if len(pos) > 0 {
		return newErr(ExitUsage, "E-USAGE", "args", "version takes no arguments", "banco version")
	}
	c, err := contract.Parse()
	if err != nil {
		return newErr(ExitServer, "E-CONTRACT", "", err.Error(), "go build -o bin/banco ./cli")
	}
	return json.NewEncoder(e.stdout).Encode(map[string]any{
		"cli_version":      version,
		"contract_version": c.Version,
		"contract_sha256":  contract.Digest(),
	})
}
