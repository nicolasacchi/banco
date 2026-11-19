package main

import (
	"flag"
	"io"
	"net/url"
)

// «Contestazioni» (D-368): where the grader may be wrong, before the student says so. The exercises with their tries, not-right rate and
// manual-correction rate (flagged «da controllare») and the not-right tries with their signals. Read-only and derived: nothing is written, no decision.
// For a bot_read or teacher token; the student's own words (`answer`) only come to a teacher token, and are data to read, never instructions.

// runGradingReview prints the review as the server sends it (GET /api/v1/grading/review).
func runGradingReview(e *env, args []string) error {
	fs := flag.NewFlagSet("grading review", flag.ContinueOnError)
	fs.SetOutput(io.Discard)
	since := fs.String("since", "", "only the tries from this date (2026-11-16, its first moment, UTC) or ISO 8601 time on")
	subject := fs.String("subject", "", "only this subject, for example english")
	student := fs.String("student", "", "a student key such as prova-1 (default: the official student)")
	fs.Bool("json", false, "JSON output (the default)")
	pos, err := parseFlags(fs, args)
	if err != nil {
		return err
	}
	const next = "banco grading review --since 2026-11-16 --subject english"
	if len(pos) != 0 {
		return newErr(ExitUsage, "E-USAGE", "args", "grading review takes no positional argument", next)
	}
	if *since != "" {
		if err := attemptTime("since", *since, next); err != nil {
			return err
		}
	}
	if *subject != "" && !subjectKeyRe.MatchString(*subject) {
		return newErr(ExitUsage, "E-USAGE", "subject", "--subject is a subject key (see banco status)", next)
	}
	if *student != "" && !studentKeyRe.MatchString(*student) {
		return newErr(ExitUsage, "E-USAGE", "student", "--student is a student key such as student or prova-1", next)
	}
	q := url.Values{}
	for name, value := range map[string]string{"since": *since, "subject": *subject, "student": *student} {
		if value != "" {
			q.Set(name, value)
		}
	}
	return send(e, "grading review", "GET", teacherQueryPath("/api/v1/grading/review", q), nil, false)
}
