---
name: course
version: 1
formats: banco.course/1
---

# Brief: the course map of a subject (version 1)

You write the course map of one subject: the **new skills** of the current year that the diagnosis
graph does not have, and the **ordered list of topics** the student studies. The map is data in the
format `banco.course/1` (`config/banco/schemas/course.json`). The skill graph (`banco.skill_graph/1`)
is not touched: graph and map share one key namespace, and a course skill key must not exist in the
graph.

Start with `banco status` and this brief. Work only through `banco`. Never ask for a decision: the
teacher approves topics and opens the course to the student in the browser; you stop at
`awaiting_teacher`.

## The file

```json
{
  "schema": "banco.course/1", "schema_version": 1, "subject": "math",
  "notes_it": ["Optional: what the teacher should know (at most 10 notes of 400 characters)."],
  "skills": [
    {"key": "math.demo-system-substitution", "label_it": "Sistemi lineari: sostituzione", "layer": "core",
     "prerequisites": ["math.demo-equation"],
     "refs": [{"source": "seconda-2025-26", "line": 30, "fragment": "metodo della sostituzione", "role": "taught_in"}],
     "errors": [{"code": "subst_no_brackets", "description_it": "Sostituisce senza parentesi.", "implicates": ["math.demo-signed-numbers"]}]}
  ],
  "topics": [
    {"key": "ripasso.math.demo-equations", "kind": "ripasso", "title_it": "Equazioni di primo grado",
     "term": 1, "minutes": 45, "skills": ["math.demo-equation"], "after": []}
  ]
}
```

Send it with `banco course submit --subject KEY course.json --dry-run`, then for real. Read the
current map with `banco course open --subject KEY`. An identical file replays the latest revision.

## Skills

- Only the skills the graph does not have. Each has a `layer` (`core`, `sec`, `opt`), `prerequisites`
  (keys of this map, of the subject's graph, or of an approved graph of another subject), optional
  `composite_of`, `refs` and `errors`.
- At least one `taught_in` ref on the current year's source (`seconda-2025-26`). The fragment is an
  exact substring of the imported line: take it from `banco syllabus lines --source S --from N --to M`
  (rows with `citable: true`). Never cite a transcriber line, never invent a line or a quotation.
- At least one typical `errors[]` entry per skill: a snake_case `code`, what the student does wrong
  (`description_it`), and the skills the mistake implicates. These codes are what practice items reuse.
- The union of graph prerequisites and map prerequisites has no cycle (`E-GRAPH-CYCLE`).
- A key in the graph, or twice in the map: `E-COURSE-SKILL-DUPLICATE`. An unknown key anywhere:
  `E-SKILL-UNKNOWN`.

## Topics

- `topics[]` order is the **recommended** course order, not the order you write them in.
- A topic key is `(ripasso|ponte|lezione).SUBJECT.slug`; the prefix equals `kind`, the subject equals
  the map's subject; keys are unique. Its `skills` (1 to 4) are skills of this subject, in the graph or
  in this map, and each skill is in **at most one** topic. `after` names other topics of the map and has
  no cycle (`E-COURSE-TOPIC`). A topic placed before one of its `after` topics, or before the topic that
  holds a direct prerequisite of its skills, is `W-COURSE-ORDER`.
- `term` 1, 2, 3 or `null`; `minutes` 10 to 90.
- Put only topics whose skills exist: ripassi and ponti on graph skills at once; a `lezione` when its
  new skills are in the same revision. Later waves come as later revisions of the map.
- The key is also the key of the lesson (`banco lesson open KEY`) and of the topic file.

## Staleness

The map is validated against the subject's latest graph revision, which is stored with it. When a
newer graph revision exists, `course open`, `status` and the teacher page show
`W-COURSE-GRAPH-STALE`: submit the map again to validate it against the new one. Nothing is
re-validated silently.

## Public repository

The code and these briefs are public. Course maps live in the database, but anything you write into a
file or a report the repository can see is public. No name of the student or of the household, no
school, no city, no exam-session details, no programme text beyond your fragments. Say "the student"
and "the teacher".
