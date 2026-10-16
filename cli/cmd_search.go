package main

import (
	"flag"
	"io"
	"net/url"
	"regexp"
	"strconv"
	"strings"
)

var searchLikeRe = regexp.MustCompile(`^[A-Za-z0-9][A-Za-z0-9._:#\-]{0,199}$`)

var searchKindRe = regexp.MustCompile(`^[a-z_]+(,[a-z_]+)*$`)

// runSearch prints the content search for the agents (GET /api/v1/search): lessons by card, glossary terms, topics, items,
// skills, findings, reference texts and programme lines, drafts included. Search before writing a new item or lesson (a
// duplicate is a finding), and cite a reference found with --kind reference_article. A query of several words may be given
// quoted or not. --like KEY is "Simili": the nearest neighbours of an object (a key, or the ref of a result such as
// item:KEY#seed), the object itself left out; run it on what you wrote to find near-duplicates. It needs the embedding service;
// without it the answer says "semantic": false.
func runSearch(e *env, args []string) error {
	fs := flag.NewFlagSet("search", flag.ContinueOnError)
	fs.SetOutput(io.Discard)
	subject := fs.String("subject", "", "only this subject, for example math")
	kind := fs.String("kind", "", "only this kind (or kinds, comma separated): lesson_card, glossary_term, topic, practice_item, item, item_instance, course, skill, finding, reference_article, syllabus_line")
	status := fs.String("status", "", "only documents in this status, for example approved")
	like := fs.String("like", "", "the objects most like this one: a key or a ref (item:KEY, item_instance:KEY#seed, lesson_card:KEY#scheda-2); no QUERY")
	limit := fs.Int("limit", 0, "at most this many results (default 20, at most 50)")
	fs.Bool("json", false, "JSON output (the default)")
	pos, err := parseFlags(fs, args)
	if err != nil {
		return err
	}
	const next = `banco search "equazioni di primo grado" --subject math --kind lesson_card`
	query := strings.TrimSpace(strings.Join(pos, " "))
	if *like != "" && query != "" {
		return newErr(ExitUsage, "E-USAGE", "like", "--like takes the place of the QUERY: give one or the other", next)
	}
	if *like != "" && !searchLikeRe.MatchString(*like) {
		return newErr(ExitUsage, "E-USAGE", "like", "--like is a key or a ref: math.powers-properties, item:KEY, item_instance:KEY#seed, lesson_card:KEY#scheda-2", `banco search --like item:math-frazioni-1`)
	}
	if *like == "" && query == "" {
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
	if *like != "" {
		values.Set("like", *like)
	} else {
		values.Set("q", query)
	}
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
