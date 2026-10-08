---
name: topic
version: 1
formats: banco.topic/1
---

# Brief: a topic (version 1)

A topic is what the teacher approves and the student opens: one lesson revision and, for each skill of
the topic, 2 to 4 practice item revisions. You write the topic file (`banco.topic/1`,
`config/banco/schemas/topic.json`) when the lesson and the practice items exist and have passed their
checks. The topic pins revisions; it does not change them.

Start with `banco status` and this brief. Work only through `banco`. Never ask for a decision: the
teacher reads the topic page (lesson, review, four sample instances of each item with hints, messages
and solutions) and approves it in the browser; you stop at `awaiting_teacher`.

## The file

```json
{
  "schema": "banco.topic/1", "schema_version": 1, "subject": "math",
  "key": "ripasso.math.demo-equations",
  "lesson_revision": "latest",
  "intro_it": "Optional, at most 300 characters, shown above the skills.",
  "practice": [
    {"skill": "math.demo-equation",
     "items": [{"item": "math-p-demo-1", "revision": "latest"},
               {"item": "math-p-demo-2", "revision": "latest"},
               {"item": "math-p-demo-3", "revision": 812}]}
  ]
}
```

`banco topic submit topic.json --dry-run`, then for real; the topic key is read from the file. See the
state with `banco topics list --subject KEY` and `banco topic open KEY`.

- `key` is a topic of the subject's latest course map (`E-TOPIC-UNKNOWN`).
- `"latest"` resolves when you submit: the lesson to its newest revision, an item to its newest
  **passed** revision. The stored topic holds integers only, and the answer echoes them (`stored`).
  Pin a number when you mean a specific revision. Items keep their order in the file: that is the
  order in which the student meets them, easier first.
- `practice` has one entry per skill of the map's topic, no skill twice and none missing; an item is
  pinned once (`E-TOPIC-SKILLS`). The lesson's `skills` must equal the topic's.
- A pinned item is a `practice_item` of that skill (`E-TOPIC-ITEM-KIND`); a pinned revision must exist
  and belong to the named lesson or item (`E-TOPIC-PIN`); an item revision that has not passed is
  `E-ITEM-NOT-PASSED`.
- Pool (`E-TOPIC-POOL`), per skill: at least one level 1 item, at least 20 distinct instances
  (distinct fingerprints) and at least 12 hard to guess.
- Warnings: `W-TOPIC-INSTANCE-IN-LESSON` (a practice instance equals a lesson exercise or example: the
  student would meet it twice), `W-PRACTICE-DIAGNOSIS-OVERLAP` (same fingerprint as a diagnosis
  instance of the skill), `W-STALE-PIN` (a newer passed revision exists).

## Stages

`banco topics list` shows the stage of each topic of the map: `missing` (no topic revision),
`in_review` (something on your side is open: skills differ from the map, a stale pin, the lesson has no
independent review, something is sent back, an item revision is not passed or lacks a review or a
blind solve), `awaiting_teacher` (nothing on your side is open), `approved`, `approved_newer_pending`.
`gate_reasons` says what is open. Fix it with a new revision of the lesson or of the item, then submit
the topic again; the teacher's comments are in `banco lesson status REV` and `banco work status REV`.

## Public repository

The code and these briefs are public. Topics live in the database, but anything you write into a file
or a report the repository can see is public. No name of the student or of the household, no school, no
city, no exam-session details. Say "the student" and "the teacher".
