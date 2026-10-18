package main

import (
	"flag"
	"io"
	"net/url"
	"regexp"
	"strings"
)

// The author's side of the findings (D-220). A finding is a possible problem raised by a
// reviewer or the blind solver. The author answers each blocker and major finding: the
// item is right (with a short proof) or a later revision fixes it. Neither command
// decides anything: only the teacher disposes of a finding, in the browser (firm rule 2).
//
// A finding of a lesson review (D-313) is listed and answered the same way. Its id is
// L<review>-<n> (the n-th finding of lesson review <review>), never a bare number, and the
// stances are lesson_right and fixed (a later revision of the same lesson).

// lessonFindingRe is the id of a lesson review's finding: L<review>-<n>.
var lessonFindingRe = regexp.MustCompile(`^L[1-9][0-9]{0,17}-[1-9][0-9]?$`)

// runFindingsList lists the blocker and major findings of a subject
// (GET /api/v1/subjects/:subject/findings): the items' first, then the lesson reviews'.
// --open keeps those the teacher has not decided and the author has not answered;
// --kind item|lesson keeps one kind; --lesson KEY the findings of one lesson; --topic KEY
// those of the topic's lesson and of the items it pins. With --lesson or --topic the
// subject is the key's middle part when --subject is not given.
func runFindingsList(e *env, args []string) error {
	fs := flag.NewFlagSet("findings list", flag.ContinueOnError)
	fs.SetOutput(io.Discard)
	subject := fs.String("subject", "", "subject key, for example italian")
	all := fs.Bool("all", false, "minor findings too (the third reviewer reads them)")
	open := fs.Bool("open", false, "only findings without a decision and without an answer")
	kind := fs.String("kind", "", "item or lesson: only the findings of items, or of lesson reviews")
	lesson := fs.String("lesson", "", "only the findings of this lesson's reviews (a lesson key)")
	topic := fs.String("topic", "", "only the findings of this topic: its lesson and the items it pins (a topic key)")
	fs.Bool("json", false, "JSON output (the default)")
	pos, err := parseFlags(fs, args)
	if err != nil {
		return err
	}
	const next = "banco findings list --subject italian --open"
	if len(pos) != 0 {
		return newErr(ExitUsage, "E-USAGE", "args", "findings list takes no positional argument", next)
	}
	for _, f := range [][2]string{{"lesson", *lesson}, {"topic", *topic}} {
		if f[1] != "" && !lessonKeyRe.MatchString(f[1]) {
			return newErr(ExitUsage, "E-USAGE", f[0], "--"+f[0]+" takes a lesson key such as ripasso.math.equations", "banco lessons list --subject KEY")
		}
	}
	if *lesson != "" && *topic != "" {
		return newErr(ExitUsage, "E-USAGE", "topic", "give --lesson or --topic, not both", "banco findings list --topic KEY --open")
	}
	if *kind != "" && *kind != "item" && *kind != "lesson" {
		return newErr(ExitUsage, "E-USAGE", "kind", "--kind is item or lesson", "banco findings list --subject italian --kind lesson")
	}
	if *kind == "item" && *lesson != "" {
		return newErr(ExitUsage, "E-USAGE", "kind", "--lesson lists the findings of a lesson review, never an item's", "banco findings list --topic "+*lesson)
	}
	if *subject == "" {
		if key := *lesson + *topic; key != "" {
			*subject = strings.Split(key, ".")[1]
		}
	}
	if *subject == "" || !subjectKeyRe.MatchString(*subject) {
		return newErr(ExitUsage, "E-USAGE", "subject", "give --subject KEY (a subject key, see banco status)", next)
	}
	path := "/api/v1/subjects/" + url.PathEscape(*subject) + "/findings"
	q := url.Values{}
	if *open {
		q.Set("open", "1")
	}
	if *all {
		q.Set("all", "1")
	}
	if *kind != "" {
		q.Set("kind", *kind)
	}
	if *lesson != "" {
		q.Set("lesson", *lesson)
	}
	if *topic != "" {
		q.Set("topic", *topic)
	}
	if len(q) > 0 {
		path += "?" + q.Encode()
	}
	return send(e, "findings list", "GET", path, nil, false)
}

// runFindingsRespond sends the author's answer to a finding
// (POST /api/v1/findings/:finding/responses). The file is
// {"stance": "item_right" | "fixed", "revision_id": N (fixed only), "note_it": "..."};
// for a lesson finding (L<review>-<n>) the stance is "lesson_right" or "fixed".
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
	if len(pos) != 1 || !(idRe.MatchString(pos[0]) || lessonFindingRe.MatchString(pos[0])) {
		return newErr(ExitUsage, "E-USAGE", "finding", "findings respond takes one finding id: a number (an item's finding) or L<review>-<n> (a lesson review's)", next)
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
// It disposes of nothing: only the teacher decides (firm rule 2). The findings of a
// lesson review have no third reviewer.
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
	if len(pos) == 1 && lessonFindingRe.MatchString(pos[0]) {
		return newErr(ExitUsage, "E-USAGE", "finding", "a lesson review's finding has no third reviewer: assess only the findings of items (a number)", "banco findings list --subject KEY --kind item --all")
	}
	if len(pos) != 1 || !idRe.MatchString(pos[0]) {
		return newErr(ExitUsage, "E-USAGE", "finding", "findings assess takes one finding id (a number)", next)
	}
	payload, err := fileBody(*file, "assessment", next)
	if err != nil {
		return err
	}
	return send(e, "findings assess", "POST", "/api/v1/findings/"+url.PathEscape(pos[0])+"/assessments", payload, *dry)
}
