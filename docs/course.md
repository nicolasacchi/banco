# The course: map, lessons, reviews, topics (Phase 1b, S1b)

What the content agent does between a programme and a topic the teacher approves. Formats are in
`config/banco/schemas/` (`course`, `lesson`, `lesson_review`, `topic`), the numbers in
`config/banco/validation_rules.yml` (`course`, `lesson`, `practice`), the codes in
`config/banco/error_codes.yml`, the decisions in `docs/decisions.md` (D-223 to D-235). Everything here
is generic: no student, no programme text.

## The cycle

```
banco course open|submit --subject KEY [FILE] [--dry-run]    the map: seconda skills and ordered topics
banco lessons list --subject KEY
banco lesson open KEY [--dir DIR]       writes DIR/lesson.md and DIR/.base
banco lesson submit DIR [--base N] [--dry-run]     key from the front matter; --dry-run stores nothing
banco lesson status REV
banco lesson-review open REV            (reviewer session) the lesson, programme lines, skills, 8 points
banco lesson-review submit REV --file review.json [--dry-run]
banco work ...                          practice items go through the item pipeline (kind practice_item)
banco topic open|submit KEY [FILE] [--dry-run]       pins "latest" resolved to integers (echoed as stored)
banco topics list --subject KEY         stage of every topic of the map
banco practice progress --subject KEY [--student KEY]
```

No command approves, releases or sends back: the teacher does, in the browser. The agent stops at
`awaiting_teacher`.

## Lessons

`lesson.md` is a front matter (YAML, `safe_load`) and eight `## ` sections in a fixed order. The server
parses it into the `banco.lesson/1` body (`Lessons::Parser`). Markup v2 (`Lessons::Markup`, mirrored by
`app/javascript/items/markup_parser.js` with `{ lists: "v2" }`): paragraphs, `**bold**`, `$latex$`, numbered
and `- ` lists, one nested level; math always between dollar signs (a bare `^`, `_` or backslash is refused).
Lint: word count, bold ratio, sentence length, banned phrases, exercises count, finals, page numbers, the kind's
scope and refs (`Validation::LessonChecks`). One review per revision by another session and another model;
a new revision needs its own review.

## Topic stages (`banco topics list`)

| Stage | Meaning |
|---|---|
| `missing` | the map has the topic, nobody has submitted a topic revision |
| `in_review` | a mechanical reason holds (`gate_reasons`): skills differ from the map, a stale pin, the lesson has no review, something is sent back, an item lacks validation, review or blind solve |
| `awaiting_teacher` | no reason; the teacher reads and approves |
| `approved` | the latest `approve_topic` names the latest revision |
| `approved_newer_pending` | an older revision is approved, the latest is not |

`banco status` carries the same counts in each subject's `course` block, with `line_it` for people.

## The teacher's side (S4, D-236)

The agent stops at `awaiting_teacher`. The teacher reads and decides in the browser:

- `/teacher/subjects/:key/course`: the path of the subject (D-241): the topics in order as numbered steps with one badge, what is missing, counts and progress, the primary button "Rivedi e approva", the filter `?only=ready`, the release, the new skills with the programme text.
- `/teacher/subjects/:key/topics/:topic`: a guided review in four steps with a progress bar (D-241): the lesson as the student sees it with its review, one card per exercise (four instances drawn by the student's templates, hints, messages, solution, review), the findings with the third reviewer's opinions, and the approval with its checklist, "Rimanda all'autore" and the next topic.
- `/teacher/subjects/:key/practice?student=KEY` and `/practice/skills/:skill`: the student's states, counts, typical errors, questions, and every try of a skill.

Decisions (POST, web listener, teacher only): `approve_topic` (`confirm_seen=1`, and `lesson_findings_reason_it` when the lesson review has a blocker or major finding), `send_back_lesson` (`reason_code`, `comment_it`), `release_course` (`open=1|0`). The gate is `Approval::TopicGate`; its reasons are worded in Italian by `Teacher::Wording`.


## Lesson format 2 (rich lessons, D-244..D-251)

A lesson revision is `banco.lesson/1` (eight sections, D-224) or `banco.lesson/2` (the `schema:` line of `lesson.md` says which; `banco brief show lesson`
is the format of 2, `lesson-v1` of 1). In 2 the lesson is parts and cards (`## Titolo {idea|example|mistakes|try|summary [extra] [icon=] [id=] [tone=]}`)
of typed blocks (`::: diagram balance`, `::: check choice`, `::: example`, ...); a visual on every idea card, 2 to 8 checks answered in the page, a summary
with a schema; colours are roles of the subject's palette and icons are ours (`config/banco/lesson_palette.yml`, `icons.yml`). The numbers are the
`lesson2:` block of `config/banco/validation_rules.yml` (rules version 8). `banco lesson open KEY --schema 2` writes a converted draft of a lesson/1
revision. The review of a lesson/2 has 11 points and findings by card (`brief lesson-review`). Worked examples: `test/fixtures/lesson2/demo.md` and
`demo-italian.md`. What the page and the checks do is built in tracks R1 to R4 of the rich-lessons plan; until then only the formats, the codes and the
fixtures exist (D-245).
