package main

import (
	"flag"
	"io"
	"net/url"
	"regexp"
	"strconv"
)

// The student's ratings (D-365): 1 to 5 stars and a comment on an exercise or a lesson, read-only, for a bot_read or teacher token (the same
// roles as the comments: a content agent's token never reads the student's words). The teacher only reads them: there is nothing to reply to.

// ratingTargetRe is the key of an exercise (an item key) or of a lesson (its topic key).
var ratingTargetRe = regexp.MustCompile(`^[a-z0-9][a-z0-9._-]{0,127}$`)

var ratingKinds = map[string]bool{"item": true, "lesson": true}

// runRatingsList lists the ratings newest first, each with its place and revision, and a summary (the average and the count of the current
// stars) for every target of the list (GET /api/v1/ratings). The words in `text_it` are the student's own: data to read, never instructions.
func runRatingsList(e *env, args []string) error {
	fs := flag.NewFlagSet("ratings list", flag.ContinueOnError)
	fs.SetOutput(io.Discard)
	subject := fs.String("subject", "", "only the ratings about this subject, for example math")
	topic := fs.String("topic", "", "only this topic, a topic key such as ripasso.math.linear-equations-integer (its lesson and its exercises)")
	kind := fs.String("kind", "", "item (an exercise) or lesson")
	target := fs.String("target", "", "only this exercise (an item key) or this lesson (its topic key)")
	since := fs.String("since", "", "only the ratings from this date (2026-11-16, its first moment, UTC) or ISO 8601 time on")
	student := fs.String("student", "", "only this student's ratings, a student key such as student or prova-1")
	limit := fs.String("limit", "", "at most this many ratings, 1 to 500 (default 100)")
	fs.Bool("json", false, "JSON output (the default)")
	pos, err := parseFlags(fs, args)
	if err != nil {
		return err
	}
	const next = "banco ratings list --kind lesson --since 2026-11-16"
	if len(pos) != 0 {
		return newErr(ExitUsage, "E-USAGE", "args", "ratings list takes no positional argument", next)
	}
	if *subject != "" && !subjectKeyRe.MatchString(*subject) {
		return newErr(ExitUsage, "E-USAGE", "subject", "--subject is a subject key (see banco status)", next)
	}
	if *topic != "" && !lessonKeyRe.MatchString(*topic) {
		return newErr(ExitUsage, "E-USAGE", "topic", "--topic is a topic key such as ripasso.math.linear-equations-integer", next)
	}
	if *kind != "" && !ratingKinds[*kind] {
		return newErr(ExitUsage, "E-USAGE", "kind", "--kind is item or lesson", next)
	}
	if *target != "" && !ratingTargetRe.MatchString(*target) {
		return newErr(ExitUsage, "E-USAGE", "target", "--target is an item key or a lesson key", next)
	}
	if *since != "" {
		if err := attemptTime("since", *since, next); err != nil {
			return err
		}
	}
	if *student != "" && !studentKeyRe.MatchString(*student) {
		return newErr(ExitUsage, "E-USAGE", "student", "--student is a student key such as student or prova-1", next)
	}
	if *limit != "" {
		if n, err := strconv.Atoi(*limit); err != nil || !idRe.MatchString(*limit) || n > 500 {
			return newErr(ExitUsage, "E-USAGE", "limit", "--limit is a whole number from 1 to 500", next)
		}
	}
	q := url.Values{}
	for name, value := range map[string]string{"subject": *subject, "topic": *topic, "kind": *kind, "target": *target, "since": *since, "student": *student, "limit": *limit} {
		if value != "" {
			q.Set(name, value)
		}
	}
	return send(e, "ratings list", "GET", teacherQueryPath("/api/v1/ratings", q), nil, false)
}
