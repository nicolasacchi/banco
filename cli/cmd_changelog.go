package main

import (
	"flag"
	"io"
	"net/url"
	"time"
)

// «Novità» (D-375): what changed for the student and the teacher, read from the entries git holds (config/banco/changelog.yml) and the topics the
// teacher approved again (the ledger). Read-only, for every token role. --audience teacher (the default) is everything, with the two revisions of
// each topic update and, for a bot_read or teacher token, the teacher's reason; --audience student is what the student reads, for the topics his
// course shows (--student, default the official student).

var changelogAudiences = map[string]bool{"student": true, "teacher": true}

// runChangelog prints the changelog as the server sends it (GET /api/v1/changelog).
func runChangelog(e *env, args []string) error {
	fs := flag.NewFlagSet("changelog", flag.ContinueOnError)
	fs.SetOutput(io.Discard)
	since := fs.String("since", "", "only what is dated this day (2026-11-17) or later")
	audience := fs.String("audience", "", "teacher (the default: every entry and every topic update) or student (what the student reads)")
	student := fs.String("student", "", "with --audience student: a student key such as prova-1 (default: the official student)")
	fs.Bool("json", false, "JSON output (the default)")
	pos, err := parseFlags(fs, args)
	if err != nil {
		return err
	}
	const next = "banco changelog --audience student --since 2026-11-17"
	if len(pos) != 0 {
		return newErr(ExitUsage, "E-USAGE", "args", "changelog takes no positional argument", next)
	}
	if *since != "" {
		if _, err := time.Parse("2006-01-02", *since); err != nil {
			return newErr(ExitUsage, "E-USAGE", "since", "--since is a day such as 2026-11-17", next)
		}
	}
	if *audience != "" && !changelogAudiences[*audience] {
		return newErr(ExitUsage, "E-USAGE", "audience", "--audience is student or teacher", next)
	}
	if *student != "" {
		if !studentKeyRe.MatchString(*student) {
			return newErr(ExitUsage, "E-USAGE", "student", "--student is a student key such as student or prova-1", next)
		}
		if *audience != "student" {
			return newErr(ExitUsage, "E-USAGE", "student", "--student goes with --audience student", next)
		}
	}
	q := url.Values{}
	for name, value := range map[string]string{"since": *since, "audience": *audience, "student": *student} {
		if value != "" {
			q.Set(name, value)
		}
	}
	return send(e, "changelog", "GET", teacherQueryPath("/api/v1/changelog", q), nil, false)
}
