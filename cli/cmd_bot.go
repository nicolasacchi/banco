package main

import (
	"flag"
	"io"
	"net/url"
	"strconv"
	"strings"
	"time"
)

// What the operator's bot asked for (D-333) and what several teachers and bots on the same students need (D-334):
// the next topic and the skills to recover, the whole picture in one call, and who did what. All three are GETs that
// record nothing; the server owns every rule, the CLI sends the flags that were given.

// runNext prints, subject by subject, the topic the student's own Oggi page proposes next, the skills to recover and
// the progress (GET /api/v1/students/:student/next); --subject keeps one subject.
func runNext(e *env, args []string) error {
	fs := flag.NewFlagSet("next", flag.ContinueOnError)
	fs.SetOutput(io.Discard)
	student := fs.String("student", "student", "a student key (default: the official student, key student)")
	subject := fs.String("subject", "", "only this subject")
	fs.Bool("json", false, "JSON output (the default)")
	pos, err := parseFlags(fs, args)
	if err != nil {
		return err
	}
	const next = "banco next --subject math"
	if len(pos) != 0 {
		return newErr(ExitUsage, "E-USAGE", "args", "next takes no positional argument", next)
	}
	if !studentKeyRe.MatchString(*student) {
		return newErr(ExitUsage, "E-USAGE", "student", "--student is a student key such as trial-1", next)
	}
	path := "/api/v1/students/" + url.PathEscape(*student) + "/next"
	if *subject != "" {
		if !subjectRe.MatchString(*subject) {
			return newErr(ExitUsage, "E-USAGE", "subject", "--subject is a subject key such as math", next)
		}
		path += "?" + url.Values{"subject": {*subject}}.Encode()
	}
	return send(e, "next", "GET", path, nil, false)
}

// runDigest prints the dashboard, the progress, the next topics, the comments, the answers waiting and the latest
// activity in one answer (GET /api/v1/digest).
func runDigest(e *env, args []string) error {
	fs := flag.NewFlagSet("digest", flag.ContinueOnError)
	fs.SetOutput(io.Discard)
	student := fs.String("student", "student", "a student key (default: the official student, key student)")
	fs.Bool("json", false, "JSON output (the default)")
	pos, err := parseFlags(fs, args)
	if err != nil {
		return err
	}
	const next = "banco digest"
	if len(pos) != 0 {
		return newErr(ExitUsage, "E-USAGE", "args", "digest takes no positional argument", next)
	}
	if !studentKeyRe.MatchString(*student) {
		return newErr(ExitUsage, "E-USAGE", "student", "--student is a student key such as trial-1", next)
	}
	return send(e, "digest", "GET", "/api/v1/digest?"+url.Values{"student": {*student}}.Encode(), nil, false)
}

// runActivity prints who did what, newest first (GET /api/v1/activity): decisions, comment actions and view links of
// every teacher and bot. --since is a date (UTC midnight) or an ISO 8601 time.
func runActivity(e *env, args []string) error {
	fs := flag.NewFlagSet("activity", flag.ContinueOnError)
	fs.SetOutput(io.Discard)
	since := fs.String("since", "", "only what happened after this date (2026-11-15) or ISO 8601 time")
	actor := fs.String("actor", "", "only the actions of this login, such as silvia@scc.im")
	limit := fs.String("limit", "", "at most this many rows, 1 to 200 (the server's default: 50)")
	fs.Bool("json", false, "JSON output (the default)")
	pos, err := parseFlags(fs, args)
	if err != nil {
		return err
	}
	const next = "banco activity --since 2026-11-15 --actor silvia@scc.im --limit 20"
	if len(pos) != 0 {
		return newErr(ExitUsage, "E-USAGE", "args", "activity takes no positional argument", next)
	}
	given := map[string]bool{}
	fs.Visit(func(f *flag.Flag) { given[f.Name] = true })
	q := url.Values{}
	if given["since"] {
		at, err := time.Parse("2006-01-02", *since)
		if err != nil {
			if at, err = time.Parse(time.RFC3339, *since); err != nil {
				return newErr(ExitUsage, "E-USAGE", "since", "--since is a date such as 2026-11-15 or an ISO 8601 time such as 2026-11-15T09:00:00Z", next)
			}
		}
		q.Set("since", at.UTC().Format(time.RFC3339))
	}
	if given["actor"] {
		if strings.TrimSpace(*actor) == "" {
			return newErr(ExitUsage, "E-USAGE", "actor", "--actor is a login such as silvia@scc.im", next)
		}
		q.Set("actor", *actor)
	}
	if given["limit"] {
		n, err := strconv.Atoi(*limit)
		if err != nil || !idRe.MatchString(*limit) || n > 200 {
			return newErr(ExitUsage, "E-USAGE", "limit", "--limit is a whole number from 1 to 200", next)
		}
		q.Set("limit", *limit)
	}
	path := "/api/v1/activity"
	if len(q) > 0 {
		path += "?" + q.Encode()
	}
	return send(e, "activity", "GET", path, nil, false)
}
