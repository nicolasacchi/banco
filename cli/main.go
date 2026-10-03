// Command banco is the content agents' only door to the banco API.
// Standard library only. JSON on stdout, errors as JSON on stderr.
package main

import (
	"flag"
	"io"
	"os"
	"strings"
)

// version is the CLI build version; the contract version is read from the
// embedded contract.
const version = "0.1.0"

func main() {
	os.Exit(run(os.Args[1:], os.Stdout, os.Stderr, os.Getenv))
}

// env is what a command needs from its surroundings.
type env struct {
	stdout, stderr io.Writer
	getenv         func(string) string
	client         func() *client
}

// command is one row of the dispatch table. The table must match
// contract/commands.json exactly (TestCommandsMatchContract).
type command struct {
	name string
	run  func(e *env, args []string) error
}

var commands = []command{
	{name: "version", run: runVersion},
	{name: "schema", run: runSchema},
	{name: "brief show", run: runBriefShow},
	{name: "diagnosis simulate", run: runDiagnosisSimulate},
	{name: "diagnosis report", run: runDiagnosisReport},
	{name: "health", run: runHealth},
	{name: "status", run: runStatus},
	{name: "syllabus lines", run: runSyllabusLines},
	{name: "work open", run: runWorkOpen},
	{name: "work submit", run: runWorkSubmit},
	{name: "work status", run: runWorkStatus},
	{name: "skill-graph open", run: runSkillGraphOpen},
	{name: "skill-graph submit", run: runSkillGraphSubmit},
	{name: "skill-graph coverage", run: runSkillGraphCoverage},
	{name: "blueprint open", run: runBlueprintOpen},
	{name: "blueprint submit", run: runBlueprintSubmit},
	{name: "session new", run: runSessionNew},
	{name: "review open", run: runReviewOpen},
	{name: "review submit", run: runReviewSubmit},
	{name: "solve open", run: runSolveOpen},
	{name: "solve submit", run: runSolveSubmit},
	{name: "submissions", run: runSubmissions},
	{name: "grade propose", run: runGradePropose},
}

func run(args []string, stdout, stderr io.Writer, getenv func(string) string) int {
	return runWith(args, &env{
		stdout: stdout, stderr: stderr, getenv: getenv,
		client: func() *client { return newClient(getenv) },
	})
}

func runWith(args []string, e *env) int {
	if len(args) == 0 {
		return reportError(e.stderr, newErr(ExitUsage, "E-USAGE", "command", "no command given", "banco schema"))
	}
	// A command name may have several words ("brief show"); the longest match wins.
	var match *command
	for i := range commands {
		words := strings.Fields(commands[i].name)
		if len(args) >= len(words) && strings.Join(args[:len(words)], " ") == commands[i].name &&
			(match == nil || len(words) > len(strings.Fields(match.name))) {
			match = &commands[i]
		}
	}
	if match == nil {
		return reportError(e.stderr, newErr(ExitUsage, "E-USAGE", "command", "unknown command: "+strings.Join(args[:min(len(args), 2)], " "), "banco schema"))
	}
	if err := match.run(e, args[len(strings.Fields(match.name)):]); err != nil {
		return reportError(e.stderr, err)
	}
	return ExitOK
}

// parseFlags lifts the first positional argument before flag parsing, so
// "banco item show REV --json" and "banco item show --json REV" both work.
// It returns the positionals in order and the flag set values via fs.
func parseFlags(fs *flag.FlagSet, args []string) ([]string, error) {
	var positional []string
	rest := args
	for len(rest) > 0 {
		if strings.HasPrefix(rest[0], "-") {
			if err := fs.Parse(rest); err != nil {
				return nil, newErr(ExitUsage, "E-USAGE", "flags", err.Error(), "")
			}
			rest = fs.Args()
			continue
		}
		positional = append(positional, rest[0])
		rest = rest[1:]
	}
	return positional, nil
}
