// Command banco is the content agents' only door to the banco API.
// Standard library only. JSON on stdout, errors as JSON on stderr.
package main

import (
	"encoding/json"
	"flag"
	"io"
	"os"
	"strings"

	"banco/contract"
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
	{name: "items list", run: runItemsList},
	{name: "reference list", run: runReferenceList},
	{name: "reference show", run: runReferenceShow},
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
	if args[0] == "help" {
		return runHelp(e, nil)
	}
	for _, a := range args {
		if a == "--help" || a == "-h" {
			return runHelp(e, args)
		}
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

// runHelp lists the command names from the embedded contract. Local: no
// network, no token. It is not a contract command (the contract stays frozen).
func runHelp(e *env, args []string) int {
	c, err := contract.Parse()
	if err != nil {
		return reportError(e.stderr, newErr(ExitServer, "E-CONTRACT", "", err.Error(), "go build -o bin/banco ./cli"))
	}
	// "banco work submit --help": the full contract entry of the longest matching command.
	var words []string
	for _, a := range args {
		if !strings.HasPrefix(a, "-") {
			words = append(words, a)
		}
	}
	var best *contract.Command
	for i := range c.Commands {
		n := strings.Fields(c.Commands[i].Name)
		if len(words) >= len(n) && strings.Join(words[:len(n)], " ") == c.Commands[i].Name &&
			(best == nil || len(n) > len(strings.Fields(best.Name))) {
			best = &c.Commands[i]
		}
	}
	if best != nil {
		json.NewEncoder(e.stdout).Encode(map[string]any{
			"usage":       "banco " + best.Name + " [args] [flags]",
			"command":     best.Name,
			"args":        best.Args,
			"flags":       best.Flags,
			"error_codes": best.ErrorCodes,
			"exit_codes":  c.ExitCodes,
		})
		return ExitOK
	}
	type row struct {
		Name  string   `json:"name"`
		Args  []string `json:"args"`
		Flags []string `json:"flags,omitempty"`
	}
	rows := []row{}
	for _, cc := range c.Commands {
		rows = append(rows, row{cc.Name, cc.Args, cc.Flags})
	}
	json.NewEncoder(e.stdout).Encode(map[string]any{
		"usage":    "banco <command> [args] [flags]; `banco schema` shows the full contract from the server",
		"commands": rows,
	})
	return ExitOK
}
