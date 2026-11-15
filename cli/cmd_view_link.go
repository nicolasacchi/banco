package main

import (
	"encoding/json"
	"flag"
	"io"
	"strconv"
	"strings"
)

// View links (D-332): a temporary URL that opens the teacher's pages read-only, without login. The bot creates one
// over the API and hands it to the user. The server owns every rule (path shape, 5..1440 minutes, the limit of active
// links); the CLI only checks what would make the request meaningless and sends the flags that were given.

// runViewLinkNew creates a view link (POST /api/v1/view-links). The answer carries the URL once: the server keeps
// only a digest of the token. It writes at once (nothing is decided), so there is no --confirm.
func runViewLinkNew(e *env, args []string) error {
	fs := flag.NewFlagSet("view-link new", flag.ContinueOnError)
	fs.SetOutput(io.Discard)
	path := fs.String("path", "", "the page the link opens, under /teacher (default /teacher)")
	minutes := fs.String("minutes", "", "how long the link lives, a number of minutes (the server's default: 60)")
	fs.Bool("json", false, "JSON output (the default)")
	pos, err := parseFlags(fs, args)
	if err != nil {
		return err
	}
	const next = "banco view-link new --path /teacher/subjects/math/course --minutes 60"
	if len(pos) != 0 {
		return newErr(ExitUsage, "E-USAGE", "args", "view-link new takes no positional argument", next)
	}
	given := map[string]bool{}
	fs.Visit(func(f *flag.Flag) { given[f.Name] = true })
	body := map[string]any{}
	if given["path"] {
		if strings.TrimSpace(*path) == "" {
			return newErr(ExitUsage, "E-USAGE", "path", "--path needs a page path, for example /teacher/subjects/math/course", next)
		}
		body["path"] = *path
	}
	if given["minutes"] {
		if !idRe.MatchString(*minutes) {
			return newErr(ExitUsage, "E-USAGE", "minutes", "--minutes is a positive whole number of minutes, for example 60", next)
		}
		n, err := strconv.Atoi(*minutes)
		if err != nil {
			return newErr(ExitUsage, "E-USAGE", "minutes", "--minutes is a positive whole number of minutes, for example 60", next)
		}
		body["minutes"] = n
	}
	payload, err := json.Marshal(body)
	if err != nil {
		return newErr(ExitUsage, "E-USAGE", "args", err.Error(), next)
	}
	return send(e, "view-link new", "POST", "/api/v1/view-links", payload, false)
}

// runViewLinkList lists this token's view links with their state (GET /api/v1/view-links); never the URL.
func runViewLinkList(e *env, args []string) error {
	fs := flag.NewFlagSet("view-link list", flag.ContinueOnError)
	fs.SetOutput(io.Discard)
	fs.Bool("json", false, "JSON output (the default)")
	pos, err := parseFlags(fs, args)
	if err != nil {
		return err
	}
	if len(pos) != 0 {
		return newErr(ExitUsage, "E-USAGE", "args", "view-link list takes no positional argument", "banco view-link list")
	}
	return send(e, "view-link list", "GET", "/api/v1/view-links", nil, false)
}

// runViewLinkRevoke ends a view link at once (POST /api/v1/view-links/:id/revoke); the id comes from view-link list.
func runViewLinkRevoke(e *env, args []string) error {
	fs := flag.NewFlagSet("view-link revoke", flag.ContinueOnError)
	fs.SetOutput(io.Discard)
	fs.Bool("json", false, "JSON output (the default)")
	pos, err := parseFlags(fs, args)
	if err != nil {
		return err
	}
	if len(pos) != 1 || !idRe.MatchString(pos[0]) {
		return newErr(ExitUsage, "E-USAGE", "id", "view-link revoke takes one view link id (a number), see banco view-link list", "banco view-link revoke 7")
	}
	return send(e, "view-link revoke", "POST", "/api/v1/view-links/"+pos[0]+"/revoke", []byte("{}"), false)
}
