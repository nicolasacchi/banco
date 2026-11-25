package main

import (
	"encoding/json"
	"fmt"
	"io"
)

// Exit codes (E-05).
const (
	ExitOK         = 0
	ExitUsage      = 2
	ExitValidation = 3
	ExitAuth       = 4
	ExitConflict   = 5
	ExitServer     = 6
)

// CLIError is written to stderr as JSON: {code, field, message, next}.
//
// A refused validation carries more: every code found, every finding (code,
// severity, field, message, detail) and whether it was a dry run.
type CLIError struct {
	Code     string            `json:"code"`
	Field    string            `json:"field"`
	Message  string            `json:"message"`
	Next     string            `json:"next"`
	Reason   string            `json:"reason,omitempty"`
	Codes    []string          `json:"codes,omitempty"`
	Findings []json.RawMessage `json:"findings,omitempty"`
	DryRun   bool              `json:"dry_run,omitempty"`
	exit     int
	onStdout bool // the answer of a dry run: its JSON is the output, on stdout, whatever the exit code
}

func (e *CLIError) Error() string { return fmt.Sprintf("%s: %s", e.Code, e.Message) }

func newErr(exit int, code, field, message, next string) *CLIError {
	return &CLIError{Code: code, Field: field, Message: message, Next: next, exit: exit}
}

// reportError prints the error as one JSON line on stderr and returns the exit code.
func reportError(w io.Writer, err error) int {
	ce, ok := err.(*CLIError)
	if !ok {
		ce = newErr(ExitServer, "E-INTERNAL", "", err.Error(), "")
	}
	b, _ := json.Marshal(ce)
	fmt.Fprintln(w, string(b))
	return ce.exit
}

// dryRunAnswer marks a validation refusal of a --dry-run as the command's output: the findings are what the author asked for, so they go to stdout
// (the exit code stays 3). Every other failure (Chrome busy, a refused token, a usage error) stays an error on stderr.
func dryRunAnswer(err error, dry bool) error {
	if ce, ok := err.(*CLIError); ok && dry && ce.exit == ExitValidation {
		ce.onStdout = true
	}
	return err
}

// exitForStatus maps an HTTP status to an exit code.
func exitForStatus(status int) int {
	switch {
	case status == 401 || status == 403:
		return ExitAuth
	case status == 409:
		return ExitConflict
	case status == 400 || status == 404 || status == 422 || status == 413:
		return ExitValidation
	default:
		return ExitServer
	}
}

// errorFromBody turns a non-2xx answer into a CLIError, using the server's
// {code, field, message, next} when it sent one.
func errorFromBody(status int, body []byte) *CLIError {
	var e CLIError
	if json.Unmarshal(body, &e) != nil || e.Code == "" {
		e = CLIError{Code: fmt.Sprintf("E-HTTP-%d", status), Message: fmt.Sprintf("server answered %d", status)}
	}
	e.exit = exitForStatus(status)
	e.explainAuth(status)
	return &e
}

// explainAuth says in words why the token was refused (D-327): the server answers a wrong, an expired and a revoked
// token alike (401 E-AUTH), and a read-only token that writes with 403 E-AUTH, reason read_only_token.
func (e *CLIError) explainAuth(status int) {
	if e.Code != "E-AUTH" {
		return
	}
	switch {
	case status == 401:
		e.Message = "the server refused the token: it is wrong, expired (a bot_read or teacher token renews itself on use and expires only after its lifetime, 90 days by default, without a request) or revoked"
		e.Next = "ask the operator for a new token (bin/rails banco:token:issue), then set BANCO_TOKEN"
	case status == 403 && e.Reason == "read_only_token":
		e.Message = "this token is read-only (role bot_read): it can read everything and write nothing"
		e.Next = "use a token with a writing role for this command, or read with banco teacher home | course | topic | test, banco progress"
	}
}
