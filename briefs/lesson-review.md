---
name: lesson-review
version: 2
formats: banco.lesson_review/1
---

# Brief: review of a lesson revision (version 2)

You review one lesson revision as a subject expert and write `banco.lesson_review/1`
(`config/banco/schemas/lesson_review.json`). You are a session of the reviewer role, independent from
every author of the lesson. A revision is in `banco.lesson/2` (cards, diagrams, checks: 11 checklist points,
findings by card) or still in `banco.lesson/1` (eight sections: 8 points, findings by section); `banco
lesson-review open REV` tells you which, and the count of points must match (`E-REVIEW-CHECKLIST`).

Start with `banco status` and this brief. Open your session first:
`export BANCO_SESSION=$(banco session new --role reviewer --agent AGENT --model MODEL --id)`.
Your model must be allowed for the reviewer role in `config/banco/providers.yml` and must differ from
every author model of the lesson (`E-PROVIDER-NOT-ALLOWED`). A session that wrote any revision of the
lesson, or that already reviewed this revision, is refused (`E-SESSION-NOT-INDEPENDENT`).
`banco lesson-review open REV` gives you the lesson file, the parsed body, the programme lines it
cites, the skills with their typical errors, the checklist, the render result with the URLs of the
screenshots, and this brief. `banco lessons list --subject KEY` shows the revision ids. **For a lesson/2
revision, look at every card's screenshot at 390 pixels first** (`banco lesson shots REV --dir D`): that is the
student's phone, and a label that overlaps or a picture that says something else shows only there. Keep your
files in a scratch directory that only you own: `mktemp -d "$TMPDIR/lr-SUBJECT-XXXXXX"`; never a fixed name,
parallel sessions share `$TMPDIR`. `banco lesson-review submit REV --file review.json` sends the result (use
`--dry-run` first). You report; you never decide and never ask for a decision: the teacher reads your review and
approves or sends back in the browser.

## The file (lesson/2)

```json
{
  "schema": "banco.lesson_review/1", "schema_version": 1, "revision": "123",
  "checklist": [{"id": 1, "result": "pass", "evidence": "Recomputed the four check answers and the exercise finals."}],
  "recomputed": [{"where": "check", "n": 3, "expression": "2 * 2 + 3", "value": "7"}],
  "findings": [{"severity": "major", "card": 3, "block": 2,
                "quote": "exact substring of lesson.md", "problem_it": "...", "fix_it": "..."}]
}
```

`checklist` has exactly **11 points**, in this order, each with `result` (`pass`, `fail`, `na`) and `evidence`
of 12 to 1200 characters saying what you did:

1. Numbers: every check answer, every blank and every `try` final recomputed in exact arithmetic. In math,
   `recomputed` has at least 8 entries, at least one per exercise check or final and one per check (the lesson has
   at most 25 of them). Diagrams the machine already checks (`balance` levels, `cartesian` points on lines,
   `number_line` landings) need a look at the screenshot, not a recomputation; the others (`area_model` cells,
   `sentence` roles, schemas) are read against the text. Other subjects may answer `na` here.
2. Solutions, check answers, `errors` messages and step blanks are correct; each final equals its `final_it`.
3. Rules stated precisely, with their common exceptions; no absolute word without a counterexample check.
4. Mistakes are real misconceptions and their `code`s match the typical errors of the skills.
5. Worked examples: every step has its reason; the reveal order makes sense; a faded step is solvable from the
   steps before it.
6. Scope: the content matches the cited lines; nothing of a later year; the kind fits the scope of the skills.
7. Readability and tone, card by card: short sentences, one idea per paragraph, no double negation, "tu", kind
   and neutral; no exam-gaming wording, no self-certification, no page or chapter numbers.
8. Prova tu: easy to hard, at least one exercise aimed at a typical error, none gives its answer away.
9. Visuals: every diagram and schema says the same as the text (look at the screenshots); no diagram draws
   something false to satisfy the visual rule (for example a balance with the signs dropped); a colour role means
   the same thing on every card and the legend says it; `alt_it` describes the content; no decorative icon or
   visual without meaning; no visual prints the answer of a check (a check may ask to reason on the visual, never
   to copy from it).
10. Cards: one idea per card; the order builds up; no card needs a later one; the titles say the idea; the core
    path is complete without `more` blocks and extra cards.
11. Free pages pinned by the lesson: answer `na` (there are none in this release).

`recomputed[]`: `{where, n, expression, value}` with `where` one of `example`, `try`, `solutions`, `idea`,
`mistakes`, `check`, and `n` the number of the exercise, example or check block, or `null`.

`findings[]`: `{severity, card, block?, quote, problem_it, fix_it}`. `card` is the `n` of the card (0 is the
cover, that is the front matter), `block` the `n` of the block in the card. `blocker`: the lesson would teach
something false. `major`: a real defect to fix before the lesson is used (an unreadable card is one). `minor`:
polish. The `quote` is an **exact substring** of `lesson.md` (otherwise `E-QUOTE-NOT-FOUND`). Write each
`problem_it` so that the teacher can follow it without the lesson open: say what is wrong and why. When the
teacher approves a topic whose latest review has a blocker or major finding, the teacher must write a reason: be
precise.

## The file (lesson/1)

For a `banco.lesson/1` revision the checklist has exactly **8 points** and the findings name a `section`:

```json
{"findings": [{"severity": "major", "section": "solutions", "exercise": 3,
               "quote": "exact substring of lesson.md", "problem_it": "...", "fix_it": "..."}]}
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


## Rules

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
