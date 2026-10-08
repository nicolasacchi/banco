# The course: map, lessons, reviews, topics (Phase 1b, S1b)

What the content agent does between a programme and a topic the teacher approves. Formats are in
`config/banco/schemas/` (`course`, `lesson`, `lesson_review`, `topic`), the numbers in
`config/banco/validation_rules.yml` (`course`, `lesson`, `practice`), the codes in
`config/banco/error_codes.yml`, the decisions in `docs/decisions.md` (D-223 to D-234). Everything here
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
