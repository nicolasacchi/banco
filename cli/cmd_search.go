package main

import (
	"flag"
	"io"
	"net/url"
	"regexp"
	"strconv"
	"strings"
)

var searchKindRe = regexp.MustCompile(`^[a-z_]+(,[a-z_]+)*$`)

// runSearch prints the content search for the agents (GET /api/v1/search): lessons by card, glossary terms, topics, items,
// skills, findings, reference texts and programme lines, drafts included. Search before writing a new item or lesson (a
// duplicate is a finding), and cite a reference found with --kind reference_article. A query of several words may be given
// quoted or not.
func runSearch(e *env, args []string) error {
	fs := flag.NewFlagSet("search", flag.ContinueOnError)
	fs.SetOutput(io.Discard)
	subject := fs.String("subject", "", "only this subject, for example math")
	kind := fs.String("kind", "", "only this kind (or kinds, comma separated): lesson_card, glossary_term, topic, practice_item, item, item_instance, course, skill, finding, reference_article, syllabus_line")
	status := fs.String("status", "", "only documents in this status, for example approved")
	limit := fs.Int("limit", 0, "at most this many results (default 20, at most 50)")
	fs.Bool("json", false, "JSON output (the default)")
	pos, err := parseFlags(fs, args)
	if err != nil {
		return err
	}
	const next = `banco search "equazioni di primo grado" --subject math --kind lesson_card`
	query := strings.TrimSpace(strings.Join(pos, " "))
	if query == "" {
		return newErr(ExitUsage, "E-USAGE", "query", "give the words to search for", next)
	}
	if *subject != "" && !subjectKeyRe.MatchString(*subject) {
		return newErr(ExitUsage, "E-USAGE", "subject", "--subject is a subject key (see banco status)", next)
	}
	if *kind != "" && !searchKindRe.MatchString(*kind) {
		return newErr(ExitUsage, "E-USAGE", "kind", "--kind is a kind or kinds separated by commas, for example lesson_card,glossary_term", next)
	}
	if *limit < 0 || *limit > 50 {
		return newErr(ExitUsage, "E-USAGE", "limit", "--limit is between 1 and 50", next)
	}
	values := url.Values{}
	values.Set("q", query)
	if *subject != "" {
		values.Set("subject", *subject)
	}
	if *kind != "" {
		values.Set("kind", *kind)
	}
	if *status != "" {
		values.Set("status", *status)
	}
	if *limit > 0 {
		values.Set("limit", strconv.Itoa(*limit))
	}
	body, err := e.client().do("search", "GET", "/api/v1/search?"+values.Encode())
	if err != nil {
		return err
	}
	_, err = e.stdout.Write(append(body, '\n'))
	return err
}
