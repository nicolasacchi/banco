package main

import (
	"encoding/json"
	"flag"
	"io"
	"net/url"
	"os"
	"regexp"
)

// namedScripts are the scripts the engine knows by name; any other --script
// value is a file with a scripted student.
var namedScripts = map[string]bool{"all-correct": true, "all-wrong": true, "mixed": true}

// runDiagnosisSimulate runs the pure diagnosis engine on a blueprint against a
// scripted student, with no database writes (POST /api/v1/diagnosis/simulate).
// The blueprint file is a banco.blueprint/1 document or a bundle
// {blueprint, graph?, pool?, external?, seen?}; --subject uses the latest
// blueprint revision stored for that subject instead. The answer is JSON:
// end_reason, trace, states, sittings. --json is accepted and changes nothing.
func runDiagnosisSimulate(e *env, args []string) error {
	fs := flag.NewFlagSet("diagnosis simulate", flag.ContinueOnError)
	fs.SetOutput(io.Discard)
	blueprint := fs.String("blueprint", "", "blueprint or bundle file")
	subject := fs.String("subject", "", "subject key (latest stored blueprint)")
	script := fs.String("script", "all-wrong", "all-correct, all-wrong, mixed or a script file")
	fs.Bool("json", false, "JSON output (the default)")
	pos, err := parseFlags(fs, args)
	if err != nil {
		return err
	}
	const next = "banco diagnosis simulate --blueprint FILE --script all-wrong --json"
	if len(pos) != 0 {
		return newErr(ExitUsage, "E-USAGE", "args", "diagnosis simulate takes no positional argument", next)
	}
	if (*blueprint == "") == (*subject == "") {
		return newErr(ExitUsage, "E-USAGE", "blueprint", "give exactly one of --blueprint FILE and --subject KEY", next)
	}

	body := map[string]any{}
	if *subject != "" {
		body["subject"] = *subject
	} else {
		doc, err := readJSONFile(*blueprint, "blueprint")
		if err != nil {
			return err
		}
		body["bundle"] = doc
	}
	if namedScripts[*script] {
		body["script"] = *script
	} else {
		doc, err := readJSONFile(*script, "script")
		if err != nil {
			return err
		}
		body["script"] = doc
	}
	payload, err := json.Marshal(body)
	if err != nil {
		return newErr(ExitUsage, "E-USAGE", "", err.Error(), next)
	}
	out, err := e.client().doBody("diagnosis simulate", "POST", "/api/v1/diagnosis/simulate", payload)
	if err != nil {
		return err
	}
	_, err = e.stdout.Write(append(out, '\n'))
	return err
}

// readJSONFile reads a file that must hold one JSON document.
func readJSONFile(path, field string) (any, error) {
	raw, err := os.ReadFile(path)
	if err != nil {
		return nil, newErr(ExitUsage, "E-USAGE", field, "cannot read "+path+": "+err.Error(), "check the path")
	}
	var doc any
	if err := json.Unmarshal(raw, &doc); err != nil {
		return nil, newErr(ExitValidation, "E-SIMULATE-INPUT", field, path+" is not JSON: "+err.Error(), "fix the file")
	}
	return doc, nil
}

var subjectKeyRe = regexp.MustCompile(`^[a-z_]+$`)

var studentKeyRe = regexp.MustCompile(`^[a-z0-9-]+$`)

// runDiagnosisReport prints the report of the diagnosis, per subject (B-09,
// GET /api/v1/diagnosis/report): the state of each subject, its sittings, the
// state of each skill, the typical errors seen and the signals. Read-only; the
// student's own words are not in it. --student KEY reports a trial student (default: the official
// student). --json is accepted and changes nothing.
func runDiagnosisReport(e *env, args []string) error {
	fs := flag.NewFlagSet("diagnosis report", flag.ContinueOnError)
	fs.SetOutput(io.Discard)
	subject := fs.String("subject", "", "one subject key (default: all)")
	student := fs.String("student", "", "a trial student's key (default: the official student)")
	fs.Bool("json", false, "JSON output (the default)")
	pos, err := parseFlags(fs, args)
	if err != nil {
		return err
	}
	const next = "banco diagnosis report --subject math --json"
	if len(pos) != 0 {
		return newErr(ExitUsage, "E-USAGE", "args", "diagnosis report takes no positional argument", next)
	}
	path := "/api/v1/diagnosis/report"
	query := url.Values{}
	if *subject != "" {
		if !subjectKeyRe.MatchString(*subject) {
			return newErr(ExitUsage, "E-USAGE", "subject", "--subject is a subject key such as math", next)
		}
		query.Set("subject", *subject)
	}
	if *student != "" {
		if !studentKeyRe.MatchString(*student) {
			return newErr(ExitUsage, "E-USAGE", "student", "--student is a student key such as trial-1", next)
		}
		query.Set("student", *student)
	}
	if len(query) > 0 {
		path += "?" + query.Encode()
	}
	body, err := e.client().do("diagnosis report", "GET", path)
	if err != nil {
		return err
	}
	_, err = e.stdout.Write(append(body, '\n'))
	return err
}
