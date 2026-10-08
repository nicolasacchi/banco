---
name: lesson-review
version: 1
formats: banco.lesson_review/1
---

# Brief: review of a lesson revision (version 1)

You review one lesson revision as a subject expert and write `banco.lesson_review/1`
(`config/banco/schemas/lesson_review.json`). You are a session of the reviewer role, independent from
every author of the lesson.

Start with `banco status` and this brief. Open your session first:
`export BANCO_SESSION=$(banco session new --role reviewer --agent AGENT --model MODEL --id)`.
Your model must be allowed for the reviewer role in `config/banco/providers.yml` and must differ from
every author model of the lesson (`E-PROVIDER-NOT-ALLOWED`). A session that wrote any revision of the
lesson, or that already reviewed this revision, is refused (`E-SESSION-NOT-INDEPENDENT`).
`banco lesson-review open REV` gives you the lesson file, the parsed body, the programme lines it
cites, the skills with their typical errors, the checklist and this brief. `banco lessons list
--subject KEY` shows the revision ids. Keep your files in a scratch directory that only you own:
`mktemp -d "$TMPDIR/lr-SUBJECT-XXXXXX"`; never a fixed name, parallel sessions share `$TMPDIR`.
`banco lesson-review submit REV --file review.json` sends the result (use `--dry-run` first). You
report; you never decide and never ask for a decision: the teacher reads your review and approves or
sends back in the browser.

## The file

```json
{
  "schema": "banco.lesson_review/1", "schema_version": 1, "revision": "123",
  "checklist": [{"id": 1, "result": "pass", "evidence": "Recomputed the six exercises and both worked examples."}],
  "recomputed": [{"where": "solutions", "n": 3, "expression": "5 - 2(2 - 4)", "value": "9"}],
  "findings": [{"severity": "major", "section": "solutions", "exercise": 3,
                "quote": "exact substring of lesson.md", "problem_it": "...", "fix_it": "..."}]
}
```

`checklist` has exactly 8 points, in this order, each with `result` (`pass`, `fail`, `na`) and
`evidence` of 12 to 1200 characters saying what you did:

1. Numbers: every number of the examples, exercises and solutions recomputed in exact arithmetic.
   In math, `recomputed` has at least 8 entries and at least one with `n` = k for every exercise k
   whose final is not `null` (`E-LESSON-REVIEW-RECOMPUTED`); other subjects may answer `na`.
2. Solutions: each correct and complete; its final equals `finals_it[n]`.
3. Rules stated precisely, with their common exceptions; no absolute word without a counterexample check.
4. "Errori da evitare" are real misconceptions and match the typical errors of the skills.
5. Worked examples: every step has its reason; no step the student cannot follow.
6. Scope: the content matches the cited lines; nothing of a later year; the kind fits the scope of the skills.
7. Readability and tone: short sentences, one idea per paragraph, no double negation, "tu", kind and
   neutral; no exam-gaming wording, no self-certification, no page or chapter numbers, no fact that
   depends on a book we have not seen.
8. Prova tu: easy to hard, at least one exercise aimed at a typical error, none gives its answer away.

`recomputed[]`: `{where, n, expression, value}` with `where` one of `example`, `try`, `solutions`,
`idea`, `mistakes`, `n` the exercise or example number or `null`.

`findings[]`: `{severity, section, exercise?, quote, problem_it, fix_it}`. `section` is one of `why`,
`idea`, `example`, `mistakes`, `try`, `solutions`, `book`, `summary`, `frontmatter`. `blocker`: the
lesson would teach something false. `major`: a real defect to fix before the lesson is used. `minor`:
polish. The `quote` is an **exact substring** of `lesson.md` (otherwise `E-QUOTE-NOT-FOUND`).
Write each `problem_it` so that the teacher can follow it without the lesson open: say what is wrong
and why. When the teacher approves a topic whose latest review has a blocker or major finding, the
teacher must write a reason: be precise.

## Rules (version 1)

1. Try to break the lesson: redo every calculation by hand or with exact arithmetic, defend every
   rule against a counterexample, read the exercises as a student who makes the typical errors.
2. A bare "all verified" is refused. Every `pass` says what you did, in its own words
   (`E-REVIEW-EMPTY`, as for item reviews: no stock phrases, no two points with the same text).
3. Never invent a line or page number. If a cited line does not support the lesson, that is a finding.
4. Report transcription doubts about a programme line as a finding for the teacher.
5. There is no "pass" verdict and no approval: you report, the teacher decides.
6. A second round uses a session that did not see the first.

## Public repository

Reviews stay in the database, but anything written to a file in the repository is public: say "the
student" and "the teacher", with no names, school, city or exam details.
