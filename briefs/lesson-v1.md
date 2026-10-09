---
name: lesson-v1
version: 1
formats: banco.lesson/1
---

# Brief: lessons in banco.lesson/1 (version 1, kept while `lesson.accept_schema1` is true)

This is the old format: eight sections of prose. New lessons are written in `banco.lesson/2`:
`banco brief show lesson`. Use this brief only when the topic's latest lesson revision is
`banco.lesson/1` and the teacher has not asked for a rewrite.

You write the text of one topic of the course for one student: a short lesson that teaches or
revisits a skill and ends with exercises on paper. Kinds: `ripasso` (a topic of the previous year
that the current year needs), `ponte` (a prerequisite the previous year did not teach), `lezione`
(content of the current year). A lesson is a Markdown file, `lesson.md`; the server parses it into
the data format `banco.lesson/1` (`config/banco/schemas/lesson.json`) and renders it with its own
templates. You never write HTML or code: the student's browser shows data only.

Start with `banco status` and this brief. Work only through `banco`. Never ask for a decision: the
teacher approves the topic in the browser, you stop at `awaiting_teacher`.

## The file

`lesson.md`: UTF-8, LF, at most 64 KB. A front matter between two `---` lines (YAML, no aliases, no
custom tags), then exactly eight `## ` sections with these exact headings (ASCII apostrophe), in this
order. Write LaTeX in single quotes in the YAML (`'x = \frac{5}{2}'`); in double quotes the backslash
must be doubled.

```markdown
---
schema: banco.lesson/1
key: ripasso.math.demo-equations
kind: ripasso
subject: math
title_it: "Equazioni di primo grado: risolvere e verificare"
skills: [math.demo-equation]
uses: [math.demo-signed-numbers]
refs:
  - {source: seconda-2025-26, line: 12, fragment: "equazioni di primo grado numeriche", role: needed_by}
  - {source: prima-2025-26, line: 7, fragment: "equazioni di primo grado", role: taught_in}
scope: studied
minutes: 30
calculator: false
finals_it: ['x = 3', 'x = 0', null, 'x = 3']
---

## Perché ti serve
## L'idea in breve
## Esempio svolto
## Errori da evitare
## Prova tu
## Soluzioni
## Sul libro
## In sintesi
```

Front matter fields:

- `key`: `(ripasso|ponte|lezione).SUBJECT.slug`, the same as the topic key in the course map. The
  `kind` and `subject` fields must agree with it (`E-LESSON-PARSE`).
- `skills` (1 to 4): the skills the student **practises** in this topic. They must be the skills of
  the topic in the course map. `uses` (up to 6): other skills the lesson recalls; only the teacher
  sees them. Every key must exist in the graph or the course map of its subject (`E-SKILL-UNKNOWN`),
  and a skill is not in both lists.
- `refs`: programme lines, each `{source, line, fragment, role}`. The fragment is an exact substring
  of the imported line: take it from `banco syllabus lines --source S --from N --to M` (rows with
  `citable: true`), never from your memory of the programme file. Sources: the previous year's
  (`prima-2025-26`) and the current year's (`seconda-2025-26`).
- Kind rules (`E-LESSON-REFS`). `ripasso`: scope `studied`, `integration_studied` or `in_progress`; at
  least one `needed_by` ref on the current year and one `taught_in` ref on the previous year. `ponte`:
  scope `middle_school` or `not_in_prima`; at least one `needed_by` ref on the current year; previous
  year refs only as `taught_in`. `lezione`: scope `seconda`; at least one `taught_in` ref on the
  current year.
- `minutes` 10 to 60: the study time including the exercises. `calculator`: true or false.
- `finals_it`: one entry per exercise of Prova tu, in order: the short final answer (LaTeX allowed,
  `$` optional), or `null` for an open exercise.

## The sections

1. **Perché ti serve**: 2 to 4 sentences. Which later topic it serves, said simply. No exam talk.
2. **L'idea in breve**: the core. Short sentences, one idea per paragraph, numbered lists for
   procedures. State each rule with its common exceptions; every "sempre", "mai", "solo" is checked
   against a counterexample before you write it.
3. **Esempio svolto**: one or two worked examples, numbered steps, each step with its reason.
4. **Errori da evitare**: at least 3 list items, the real misconceptions of the skills' error
   catalogue (graph or course map), each as wrong form, right form, and one line on why.
5. **Prova tu**: optional intro paragraph, then exactly one numbered list 1..N with N from 4 to 8.
   Easy to hard; at least one exercise aimed at a typical error; none gives its answer away. The
   student works on paper; only the result is asked.
6. **Soluzioni**: exactly one numbered list 1..N, the same N. Each has the final answer and the key
   steps. The final equals `finals_it`.
7. **Sul libro**: starts with the line `Pagine del libro: le indica il docente.` and adds at most 30
   words (for example the name of the topic as textbooks call it). Never a page, chapter or
   exercise number: we have not seen the books.
8. **In sintesi**: exactly one bulleted list of 3 to 5 points.

## Markup (version 2, lessons only)

- Blocks are separated by a blank line.
- A block whose lines all start with `1. `, `2. `, ... is an ordered list; with `- ` an unordered one.
- One nested level: a line indented by 2 to 4 spaces starting with `- ` belongs to the item above.
- Inline: `**bold**`, `$latex$`, `\$` for a literal dollar sign. The signs `✓` and `✗` are plain text.
- Refused with `E-LESSON-MARKUP` (the message gives line and construct): headings inside a section,
  tables, `<` tags, links, images, `*italic*` or `_italic_`, backticks, `>` quotes, `---` rules,
  deeper nesting, an unclosed `$` or `**`, and bare math: any `^`, `_` or backslash outside
  `$...$` (write `$x^2$`, never `x^2`).

## Readability and limits

- At most 500 words outside Prova tu and Soluzioni (`E-LESSON-WORDS`; each `$...$` counts as one word).
- Sentences of at most 25 words. One idea per paragraph. No double negation. Address the student as
  "tu", kindly and neutrally, never "bravo/brava".
- Bold only on keywords, at most 8% of the words (`E-LESSON-BOLD`). No italics, no ALL-CAPS words
  (acronyms excepted), no emoji.
- Decimal comma. The same notation everywhere.
- A page number anywhere is `E-LESSON-PAGE`.
- Phrases never used: exam-gaming ("la risposta che cercano", "cosa scrivere") and self-certification
  ("è tutto verificato"). No personalisation and no data about the student.
- Warnings you should clear: `W-LESSON-WHY` (2 to 4 sentences in Perché ti serve), `W-LESSON-MISTAKES`
  (at least 3 items), `W-GULPEASE` (idea and example), `W-LESSON-FINAL-MISSING` (a final that your
  solution does not contain, informational), `W-LESSON-FINAL-IN-TRY` (an exercise text that gives its
  own final away).

## Correctness

Every number of examples, exercises and solutions is yours to get right and the reviewer recomputes
them in exact arithmetic. A rule of language or science must hold in standard usage with its common
exceptions. A fact that depends on the textbook is written neutrally or left out. If a programme line
is unclear or looks like a transcription error, do not guess: report it to the teacher and leave the
skill out.

## The cycle

1. `banco lessons list --subject KEY` shows the lessons, their rules version, reviews and send-backs.
2. `banco lesson open KEY` writes `lesson.md` and `.base` into a folder under `$TMPDIR/banco-work/`
   (a new lesson has no revision yet: start the folder yourself).
3. Edit, then `banco lesson submit DIR --dry-run` until it exits 0, then `banco lesson submit DIR`.
   An identical file replays the latest revision. `E-STALE-BASE` means someone submitted first: open again.
4. A reviewer of another model reads it (`banco lesson-review open|submit`, see that brief). Read the
   result with `banco lesson status REV`: `reviews` and the teacher's `teacher_comments`. Answer by a
   new revision that fixes what they say; a new revision needs its own review.
5. The lesson belongs to a topic (`banco topic submit`, see the topic brief). The teacher reads the
   whole topic and approves it in the browser.

## Public repository

The code and these briefs are public. Lessons live in the database, but anything you write into a file
or a report the repository can see is public. No name of the student or of the household, no school,
no city, no exam-session details, no programme text beyond the fragments of your refs. Say "the
student" and "the teacher".
