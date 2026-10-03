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
	Codes    []string          `json:"codes,omitempty"`
	Findings []json.RawMessage `json:"findings,omitempty"`
	DryRun   bool              `json:"dry_run,omitempty"`
	exit     int
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
	return &e
}
