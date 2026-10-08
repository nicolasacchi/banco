---
name: practice-item
version: 1
formats: banco.item/1
---

# Brief: practice items (version 1)

A practice item is an item of kind `practice_item` (`banco.item/1`, `config/banco/schemas/item.json`).
The student meets it while studying a topic: after a lesson, on one skill, with help on request and an
answer at once. It goes through the same pipeline as a diagnosis item: generator or static instances,
blind verifier, leak scans, expert review (with two more points), blind solve, findings and
responses. Everything in `banco brief show diagnosis-item` applies **unless this brief says
otherwise**: the sources, the component rules, the choice rules, the readability rules, the phrases
never used, the over-absolute rules, the calculating subjects, the supports (`answer_format_it`,
`steps_it`) and the generator and verify contract. Read that brief first.

Start with `banco status` and this brief. Work only through `banco`. Never ask for a decision: you
stop at `awaiting_teacher`.

## What differs from a diagnosis item

- `kind: "practice_item"`. Required: `component`, `prompt`, `error_catalogue`, `tests`, `level`, and
  either `instances` or `generator`. Components: `number`, `fraction`, `expression`, `choice`,
  `ordering`, `matching`, `normalized_text`. No `sub_items`, no `rubric`: practice is closed only.
- `level` (1 to 3): 1 one step or direct; 2 the typical case; 3 combined with prerequisites. A topic
  needs at least one level 1 item per skill.
- `hints_it` (2 to 4 strings, each at most 300 characters; **write 3**) on the item, and optionally
  on an instance (an instance's own hints replace the item's for that instance). Every instance has
  effective hints (`E-HINTS`). Hints are shown one at a time, on request, and counted.
- Hint order: 1 says what to look at or which rule applies; 2 is the first concrete step with this
  instance's numbers; 3 (and 4) is the next step, stopping before the final value.
- A hint never states the key (`E-HINT-KEY`: a string the display-key check would flag, unless it also
  occurs in the display of the same instance; numbers taken from the display are allowed). In a
  `choice` item a hint must not name the key option (`W-HINT-OPTION`); the reviewer judges. Ordering and
  matching have no scan: the reviewer judges.
- Hints obey the readability rules of messages (`E-READ`, `E-PHRASE`): sentences of at most 25 words,
  the second person, kind, no exam-gaming.
- `diagnosis_item`, `short_answer` and `testlet` items must not carry `level` or `hints_it`.
- A practice item is never pinned by a blueprint (`E-BLUEPRINT-PRACTICE-ITEM`), and a topic pins only
  practice items.

## Messages and solutions: what the student reads

- **Right away after a typical error**: the `message_it` of the catalogue entry, at most two sentences:
  the wrong step and the rule that holds; it never gives the key. Then the student gets "Prova
  questo": a new instance in which the same mistake is possible again. So make every catalogue code
  appear in the `errors[]` of several instances: a code carried by fewer than 3 instances is
  `W-PRACTICE-CODE-SPARSE`. Error values must be what a student making that mistake would really
  type; they differ from each other and from the key.
- **An answer no code explains**: the student reads that it matches no mistake we know, and gets hint
  1 and one more try. The second wrong answer shows the solution.
- **After a correct answer**, and on request: the worked `solution` of the instance (`steps` and
  `final`). Each step says what is done and why, in short sentences, and the last step ends at the
  key. A step is correct on its own: the reviewer checks them one by one.
- The solution is shown after the attempt, never before; it may state the key, the hints may not.

## Pools

- A generated item keeps `generator.pool` of 24 clean seeds; a static practice item has at least 10
  instances (`E-PRACTICE-POOL`). Instances must differ in display and fingerprint.
- Per skill a topic needs at least 20 distinct instances over its 2 to 4 pinned items, 12 of them hard
  to guess (written answers, an ordering or matching of 4 or more): plan the items so that the pool
  reaches that. Write the first, level 1, item first.
- Do not copy the lesson's exercises or worked examples (`W-TOPIC-INSTANCE-IN-LESSON`) and do not reuse
  the instances of the diagnosis items of the skill (`W-PRACTICE-DIAGNOSIS-OVERLAP`).

## Reviewers and solvers

A reviewer checks 13 points: the 11 of the review brief, plus 12 (hints: 2 to 4 per instance, from the
rule to the next step; none states the key; the last stops before the final value) and 13 (messages
and solution: each typical-error message names the mistake and the rule without the key; each
solution step is correct, says why, and ends at the key). A review of a practice item with another
number of points is `E-REVIEW-CHECKLIST`. The blind solver sees what the student sees before asking
for help: prompt and display, never hints, messages or solutions. Findings are answered with
`banco findings respond`, exactly as for diagnosis items.

## The cycle

`banco work open ITEM`, edit, `banco work submit DIR --dry-run`, `banco work submit DIR`,
`banco work status REV --wait`: the same as for diagnosis items (new generators wait for a verifier).
`banco items list --subject KEY --kind practice --current` lists the practice items only. The teacher
can send an item back ("Rimanda"); read `teacher_comments` before you edit. When the items of a skill
have passed, been reviewed and been solved blind, the topic file pins them (`banco brief show topic`).

## Public repository

The code and these briefs are public. Items live in the database, but anything you write into a file
or a report the repository can see is public. No name of the student or of the household, no school,
no city, no exam-session details, no programme text. Say "the student" and "the teacher".
