package main

import (
	"encoding/json"
	"flag"
	"io"
	"net/url"
	"os"
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

const (
	itemGradeNext   = `banco item grade 12 --instance 1 --answer "'s scared" --answer "is scared"`
	lessonGradeNext = `banco lesson grade 12 --check 3.2 --answer "is scared"`
)

func runItemGrade(e *env, args []string) error {
	return runGrade(e, gradeCommand{name: "item grade", member: "instance", path: "item-revisions", next: itemGradeNext, flagName: "instance",
		flagHelp: "the instance number (1 is the first instance, as review open numbers them); every --answer is graded against it", file: "[{instance, answer}, …]"}, args)
}

func runLessonGrade(e *env, args []string) error {
	return runGrade(e, gradeCommand{name: "lesson grade", member: "check", path: "lesson-revisions", next: lessonGradeNext, flagName: "check",
		flagHelp: "the check id: CARD.BLOCK, CARD.BLOCK.stepN, CARD.BLOCK.exN or CARD.BLOCK.exN.P (the n of the card and the block in the lesson); every --answer is graded against it",
		file:     "[{check, answer}, …]"}, args)
}

// gradeCommand is what item grade and lesson grade differ in: the member that names the target in each answer, the flag that gives it, the route.
type gradeCommand struct {
	name, member, path, next, flagName, flagHelp, file string
}

func runGrade(e *env, g gradeCommand, args []string) error {
	fs := flag.NewFlagSet(g.name, flag.ContinueOnError)
	fs.SetOutput(io.Discard)
	target := fs.String(g.flagName, "", g.flagHelp)
	var answers stringsFlag
	fs.Var(&answers, "answer", "an answer to grade, exactly as the student would type it (repeat it for several); structured answers are JSON text; a tiles or ordering check takes ids: the tile ids as a comma list (t1,t2,t3) or the shown ids (e1,e2,e3)")
	file := fs.String("answers-file", "", "a file with one JSON array "+g.file+" instead of --"+g.flagName+" and --answer; the answer may be any JSON value (a list of ids for tiles or an ordering)")
	fs.Bool("json", false, "JSON output (the default)")
	pos, err := parseFlags(fs, args)
	if err != nil {
		return err
	}
	if len(pos) != 1 || !idRe.MatchString(pos[0]) {
		return newErr(ExitUsage, "E-USAGE", "revision", g.name+" takes one argument: a revision id (a number)", g.next)
	}
	var list []map[string]any
	switch {
	case *file != "":
		if *target != "" || len(answers) > 0 {
			return newErr(ExitUsage, "E-USAGE", "answers-file", "--answers-file replaces --"+g.flagName+" and --answer: give one or the other", g.next)
		}
		if list, err = readGradeFile(*file, g); err != nil {
			return err
		}
	default:
		if *target == "" || len(answers) == 0 {
			return newErr(ExitUsage, "E-USAGE", g.flagName, "give --"+g.flagName+" and at least one --answer (or --answers-file FILE)", g.next)
		}
		var value any = *target
		if g.member == "instance" {
			n, convErr := strconv.Atoi(*target)
			if convErr != nil || n < 1 {
				return newErr(ExitUsage, "E-USAGE", "instance", "--instance is the number of an instance, 1 or more", g.next)
			}
			value = n
		}
		for _, a := range answers {
			list = append(list, map[string]any{g.member: value, "answer": a})
		}
	}
	payload, err := json.Marshal(map[string]any{"answers": list})
	if err != nil {
		return newErr(ExitUsage, "E-USAGE", "answers", err.Error(), g.next)
	}
	out, err := e.client().doBody(g.name, "POST", "/api/v1/"+g.path+"/"+url.PathEscape(pos[0])+"/grade", payload)
	if err != nil {
		return err
	}
	_, err = e.stdout.Write(append(out, '\n'))
	return err
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
