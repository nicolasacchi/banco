package main

import (
	"encoding/json"
	"flag"
	"io"
	"net/url"
	"os"
	"path/filepath"
	"strconv"
	"strings"
)

// The read-only grade commands of the reviewer and the solver (D-402, round 8): `banco item grade REV --instance N --answer "…"` and
// `banco lesson grade REV --check ID --answer "…"`. The server grades each answer through the student's own path and says the verdict, what it matched
// (the key, an accept entry, a declared error value), the error code and the message the student would read. Nothing is stored: no attempt, no event,
// no ledger row. Every token role may ask. A reviewer tests a refused answer with these before filing it, instead of reading it off the accept list.

// stringsFlag is a flag that may be given more than once (--answer).
type stringsFlag []string

func (s *stringsFlag) String() string     { return strings.Join(*s, ",") }
func (s *stringsFlag) Set(v string) error { *s = append(*s, v); return nil }

// onceFlag is a string flag that may be given only once: a second --instance would grade every answer against the last one, so it is refused (D-403).
type onceFlag struct {
	value string
	count int
}

func (o *onceFlag) String() string     { return o.value }
func (o *onceFlag) Set(v string) error { o.value = v; o.count++; return nil }

const (
	itemGradeNext   = `banco item grade 12 --instance 1 --answer "'s scared" --answer "is scared"`
	lessonGradeNext = `banco lesson grade 12 --check 3.2 --answer "is scared"`
)

func runItemGrade(e *env, args []string) error {
	return runGrade(e, gradeCommand{name: "item grade", member: "instance", path: "item-revisions", draftPath: "/api/v1/item-grade", next: itemGradeNext, flagName: "instance",
		flagHelp: "the instance number (1 is the first instance, as review open numbers them); every --answer is graded against it (give --instance once: one command per instance, or --answers-file)", file: "[{instance, answer}, …]",
		draftHelp: "grade against a local item instead of a stored revision: a folder (item.json, generator.mjs, assets/) or an item JSON file (generator.mjs and assets/ are read from its folder). The server builds the instances as work submit --dry-run does and stores nothing; take no REV"}, args)
}

func runLessonGrade(e *env, args []string) error {
	return runGrade(e, gradeCommand{name: "lesson grade", member: "check", path: "lesson-revisions", draftPath: "/api/v1/lesson-grade", next: lessonGradeNext, flagName: "check",
		flagHelp: "the check id: CARD.BLOCK, CARD.BLOCK.stepN, CARD.BLOCK.exN or CARD.BLOCK.exN.P (the n of the card and the block in the lesson); every --answer is graded against it (give --check once: one command per check, or --answers-file)",
		file:     "[{check, answer}, …]", ids: true,
		draftHelp: "grade against a local lesson instead of a stored revision: a lesson.md (or the folder that holds it). The server builds it as lesson submit --dry-run does and stores nothing; take no REV"}, args)
}

// gradeCommand is what item grade and lesson grade differ in: the member that names the target in each answer, the flag that gives it, the route.
type gradeCommand struct {
	name, member, path, draftPath, next, flagName, flagHelp, file, draftHelp string
	ids                                                                      bool // a lesson command takes --ids (tiles, ordering and matching ids: lesson or shown)
}

func runGrade(e *env, g gradeCommand, args []string) error {
	fs := flag.NewFlagSet(g.name, flag.ContinueOnError)
	fs.SetOutput(io.Discard)
	var target onceFlag
	fs.Var(&target, g.flagName, g.flagHelp)
	var answers stringsFlag
	fs.Var(&answers, "answer", "an answer to grade, exactly as the student would type it (repeat it for several); structured answers are JSON text; a tiles or ordering check takes ids: the tile ids as a comma list (t1,t2,t3) or the shown ids (e1,e2,e3); a matching takes the object {left id: right id}")
	file := fs.String("answers-file", "", "a file with one JSON array "+g.file+" instead of --"+g.flagName+" and --answer; the answer may be any JSON value (a list of ids for tiles or an ordering, an object for a matching)")
	draft := fs.String("file", "", g.draftHelp)
	ids := new(string)
	if g.ids {
		fs.StringVar(ids, "ids", "", "which ids a tiles, ordering or matching answer is written in when the lesson's own ids look like the shown ones (l1, r1, e1): lesson or shown (default: the shown ids win)")
	}
	fs.Bool("json", false, "JSON output (the default)")
	pos, err := parseFlags(fs, args)
	if err != nil {
		return err
	}
	if target.count > 1 {
		return newErr(ExitUsage, "E-USAGE", g.flagName, "--"+g.flagName+" is given "+strconv.Itoa(target.count)+" times and every --answer is graded against one: run the command once per "+g.flagName+", or list the pairs in --answers-file", g.next)
	}
	if *ids != "" && *ids != "lesson" && *ids != "shown" {
		return newErr(ExitUsage, "E-USAGE", "ids", "--ids is lesson or shown", g.next)
	}
	var files map[string]string
	if *draft != "" {
		if len(pos) != 0 {
			return newErr(ExitUsage, "E-USAGE", "file", "--file grades a local body: it takes no revision id", g.next)
		}
		if files, err = readGradeDraft(*draft, g); err != nil {
			return err
		}
	} else if len(pos) != 1 || !idRe.MatchString(pos[0]) {
		return newErr(ExitUsage, "E-USAGE", "revision", g.name+" takes one argument: a revision id (a number), or --file FILE to grade a local body", g.next)
	}
	var list []map[string]any
	switch {
	case *file != "":
		if target.count > 0 || len(answers) > 0 || *ids != "" {
			return newErr(ExitUsage, "E-USAGE", "answers-file", "--answers-file replaces --"+g.flagName+", --answer and --ids: give one or the other", g.next)
		}
		if list, err = readGradeFile(*file, g); err != nil {
			return err
		}
	default:
		if target.value == "" || len(answers) == 0 {
			return newErr(ExitUsage, "E-USAGE", g.flagName, "give --"+g.flagName+" and at least one --answer (or --answers-file FILE)", g.next)
		}
		var value any = target.value
		if g.member == "instance" {
			n, convErr := strconv.Atoi(target.value)
			if convErr != nil || n < 1 {
				return newErr(ExitUsage, "E-USAGE", "instance", "--instance is the number of an instance, 1 or more", g.next)
			}
			value = n
		}
		for _, a := range answers {
			entry := map[string]any{g.member: value, "answer": a}
			if *ids != "" {
				entry["ids"] = *ids
			}
			list = append(list, entry)
		}
	}
	body := map[string]any{"answers": list}
	path := "/api/v1/" + g.path + "/" + url.PathEscape(strings.Join(pos, "")) + "/grade"
	if *draft != "" {
		body["files"] = files
		path = g.draftPath
	}
	payload, err := json.Marshal(body)
	if err != nil {
		return newErr(ExitUsage, "E-USAGE", "answers", err.Error(), g.next)
	}
	out, err := e.client().doBody(g.name, "POST", path, payload)
	if err != nil {
		return err
	}
	_, err = e.stdout.Write(append(out, '\n'))
	return err
}

// readGradeDraft reads the local body that --file grades. An item: a folder (item.json, generator.mjs, assets/: what work submit sends, without verify.mjs) or
// an item JSON file, whose own folder gives the generator.mjs and the assets it names. A lesson: a lesson.md, or the folder that holds it.
func readGradeDraft(path string, g gradeCommand) (map[string]string, error) {
	st, err := os.Stat(path)
	if err != nil {
		return nil, newErr(ExitUsage, "E-USAGE", "file", "cannot read "+path+": "+err.Error(), g.next)
	}
	if g.member == "check" {
		if st.IsDir() {
			path = filepath.Join(path, "lesson.md")
		}
		raw, err := os.ReadFile(path)
		if err != nil || len(strings.TrimSpace(string(raw))) == 0 {
			return nil, newErr(ExitUsage, "E-USAGE", "file", path+" must be a lesson.md (or the folder that holds it), not empty", g.next)
		}
		return map[string]string{"lesson.md": string(raw)}, nil
	}
	dir := path
	if !st.IsDir() {
		dir = filepath.Dir(path)
	}
	files, _ := readWorkFiles(dir, "")
	delete(files, "verify.mjs")
	if !st.IsDir() {
		raw, err := os.ReadFile(path)
		if err != nil {
			return nil, newErr(ExitUsage, "E-USAGE", "file", "cannot read "+path+": "+err.Error(), g.next)
		}
		files["item.json"] = string(raw)
	}
	if strings.TrimSpace(files["item.json"]) == "" {
		return nil, newErr(ExitUsage, "E-USAGE", "file", "no item.json in "+path+": give an item folder or an item JSON file", g.next)
	}
	return files, nil
}

// readGradeFile reads the one JSON array of {instance|check, answer} of --answers-file.
func readGradeFile(path string, g gradeCommand) ([]map[string]any, error) {
	raw, err := os.ReadFile(path)
	if err != nil {
		return nil, newErr(ExitUsage, "E-USAGE", "answers-file", "cannot read "+path+": "+err.Error(), g.next)
	}
	var list []map[string]any
	if err := json.Unmarshal(raw, &list); err != nil || len(list) == 0 {
		return nil, newErr(ExitUsage, "E-USAGE", "answers-file", path+" must hold one JSON array "+g.file+", at least one entry", g.next)
	}
	for i, a := range list {
		if _, ok := a[g.member]; !ok {
			return nil, newErr(ExitUsage, "E-USAGE", "answers-file", "entry "+strconv.Itoa(i)+" of "+path+" has no \""+g.member+"\"", g.next)
		}
		if _, ok := a["answer"]; !ok {
			return nil, newErr(ExitUsage, "E-USAGE", "answers-file", "entry "+strconv.Itoa(i)+" of "+path+" has no \"answer\"", g.next)
		}
	}
	return list, nil
}
