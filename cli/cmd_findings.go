package main

import (
	"flag"
	"io"
	"net/url"
)

// The author's side of the findings (D-220). A finding is a possible problem raised by a
// reviewer or the blind solver. The author answers each blocker and major finding: the
// item is right (with a short proof) or a later revision fixes it. Neither command
// decides anything: only the teacher disposes of a finding, in the browser (firm rule 2).

// runFindingsList lists the blocker and major findings of a subject
// (GET /api/v1/subjects/:subject/findings). --open keeps those the teacher has not decided
// and the author has not answered.
func runFindingsList(e *env, args []string) error {
	fs := flag.NewFlagSet("findings list", flag.ContinueOnError)
	fs.SetOutput(io.Discard)
	subject := fs.String("subject", "", "subject key, for example italian")
	all := fs.Bool("all", false, "minor findings too (the third reviewer reads them)")
	open := fs.Bool("open", false, "only findings without a decision and without an answer")
	fs.Bool("json", false, "JSON output (the default)")
	pos, err := parseFlags(fs, args)
	if err != nil {
		return err
	}
	const next = "banco findings list --subject italian --open"
	if *subject == "" || !subjectKeyRe.MatchString(*subject) {
		return newErr(ExitUsage, "E-USAGE", "subject", "give --subject KEY (a subject key, see banco status)", next)
	}
	if len(pos) != 0 {
		return newErr(ExitUsage, "E-USAGE", "args", "findings list takes no positional argument", next)
	}
	path := "/api/v1/subjects/" + url.PathEscape(*subject) + "/findings"
	q := url.Values{}
	if *open {
		q.Set("open", "1")
	}
	if *all {
		q.Set("all", "1")
	}
	if len(q) > 0 {
		path += "?" + q.Encode()
	}
	return send(e, "findings list", "GET", path, nil, false)
}

// runFindingsRespond sends the author's answer to a finding
// (POST /api/v1/findings/:finding/responses). The file is
// {"stance": "item_right" | "fixed", "revision_id": N (fixed only), "note_it": "..."}.
func runFindingsRespond(e *env, args []string) error {
	fs := flag.NewFlagSet("findings respond", flag.ContinueOnError)
	fs.SetOutput(io.Discard)
	file := fs.String("file", "", "response.json")
	dry := fs.Bool("dry-run", false, "check and store nothing")
	fs.Bool("json", false, "JSON output (the default)")
	pos, err := parseFlags(fs, args)
	if err != nil {
		return err
	}
	const next = "banco findings respond FINDING --file response.json"
	if len(pos) != 1 || !idRe.MatchString(pos[0]) {
		return newErr(ExitUsage, "E-USAGE", "finding", "findings respond takes one finding id (a number)", next)
	}
	payload, err := fileBody(*file, "response", next)
	if err != nil {
		return err
	}
	return send(e, "findings respond", "POST", "/api/v1/findings/"+url.PathEscape(pos[0])+"/responses", payload, *dry)
}

// runFindingsAssess sends the third reviewer's opinion on a finding
// (POST /api/v1/findings/:finding/assessments). The file is
// {"verdict": "author_right" | "finding_right" | "unclear", "note_it": "..."}.
// It disposes of nothing: only the teacher decides (firm rule 2).
func runFindingsAssess(e *env, args []string) error {
	fs := flag.NewFlagSet("findings assess", flag.ContinueOnError)
	fs.SetOutput(io.Discard)
	file := fs.String("file", "", "assessment.json")
	dry := fs.Bool("dry-run", false, "check and store nothing")
	fs.Bool("json", false, "JSON output (the default)")
	pos, err := parseFlags(fs, args)
	if err != nil {
		return err
	}
	const next = "banco findings assess FINDING --file assessment.json"
	if len(pos) != 1 || !idRe.MatchString(pos[0]) {
		return newErr(ExitUsage, "E-USAGE", "finding", "findings assess takes one finding id (a number)", next)
	}
	payload, err := fileBody(*file, "assessment", next)
	if err != nil {
		return err
	}
	return send(e, "findings assess", "POST", "/api/v1/findings/"+url.PathEscape(pos[0])+"/assessments", payload, *dry)
}
