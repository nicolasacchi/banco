package main

import (
	"encoding/json"
	"flag"
	"io"
	"strings"

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
	out := map[string]any{
		"cli_version":      version,
		"contract_version": c.Version,
		"contract_sha256":  contract.Digest(),
	}
	// a release build is stamped <base>+<commit> (bin/build-cli-dist, ".dirty" after an uncommitted change): the commit alone is its own member
	if _, commit, ok := strings.Cut(version, "+"); ok && commit != "" {
		out["cli_commit"] = commit
	}
	// The server's commit (GET /api/v1/updates: public, no token). The command stays local: a server that does not answer is told in
	// `server_error`, never an exit code, so `banco version` still works with no network.
	if u, err := fetchUpdates(e.client(), "version", "/api/v1/updates"); err != nil {
		out["server_commit"] = nil
		out["server_error"] = err.Error()
	} else {
		out["server_commit"] = u.Server.Commit
		out["server_built_at"] = u.Server.BuiltAt
	}
	return json.NewEncoder(e.stdout).Encode(out)
}
