---
name: blueprint
version: 1
formats: banco.blueprint/1
---

# Brief: entry tests, the blueprint (version 1)

You choose, for one subject, the skills the entry test starts from and the items
that measure them, as `banco.blueprint/1`
(`config/banco/schemas/blueprint.json`). Build it on the subject's graph (the
teacher approves the graph first; the server lets you draft on an unapproved one so
that you can simulate), and every item you pin must have a passed validation.

Start with `banco status` and this brief. Work only through `banco`
(`banco blueprint open|submit --subject KEY`, `banco diagnosis simulate`). Never ask for a
decision: you stop at `awaiting_teacher`.

## Shape

- `graph_revision_id`: the approved graph revision this test is built on.
- `entries[]`: the starting skills in the order they are tried, 4 to 10 of them.
  Each has `items[]` (item revision ids) and optionally `redo_reserve: false` or
  `choice_only_reason_it`. A starting skill may belong to another subject's
  approved graph (`guest_of_subject`); its result goes to the owner subject. While that
  graph is still a draft the entry is accepted with `W-GUEST-UNAPPROVED` so you can simulate;
  the teacher cannot approve the test until the graph is approved.
- `descent[]`: the descent pool, required (it may be empty when no skill lies
  below the starting skills). When a starting skill goes wrong the test goes down
  to its prerequisites and to the skills its typical errors point at, so for every
  such skill (`banco skill-graph coverage` and a failed submit
  `E-BLUEPRINT-UNPINNED-DESCENT` list them) you either pin `{skill, items[]}`, or
  declare `{skill, not_assessed_reason_it}`: the skill is then not asked and the
  teacher reads your reason. The test serves nothing that is not pinned here.
- `budget`: `{sitting_minutes, sittings}`. Defaults: 30 minutes for mathematics, 25
  for the other subjects; two sittings (the second starts by itself when skills
  remain to explore).
- `depends_on_subjects[]`: subjects that must have a closed first sitting.
- `calculator`: `no` by default; `yes` in business and chemistry, and the item
  stems say so.
- `intro_note_it`: what the student reads before starting (shown on the start screen).
- `not_measured_it`: what this test does not measure (for example oral
  exposition, listening and speaking, extended writing). Required.
- `kind_overrides[]`: `{skill, kind, reason_it}` to change `recover` or `learn`.

## Rules (version 1)

1. Every skill needs, in the pool, at least 6 distinct instances over at least 2
   items, 3 of them hard to guess; otherwise declare `redo_reserve: false` and
   the teacher will see it.
2. The first item of a skill is hard to guess (written answer, ordering of 4 or
   more, matching of 4 or more pairs) unless `choice_only_reason_it` says why not.
3. Discursive subjects have closed items, one reading testlet of 150 to 300 words
   (5 closed sub-items) and exactly one short answer. The short answer is indicative by definition: it
   has no mark to set. It is graded by its rubric and counts only after the teacher
   confirms the grade. Do not cite an invented source for it.
4. Order starting skills from the simplest dependency: a failure descends to
   prerequisites, so start where a descent is cheap. Run `banco diagnosis simulate`
   with the `all-correct` and `all-wrong` scripts and read the traces; the teacher
   sees them too. With `--blueprint FILE` the dry run uses the graph revision named in the
   file and the pinned items that are stored and passed (the answer lists in `warnings`
   any it had to invent); after a submit, `--subject KEY` does the same from the stored
   blueprint. A testlet is served at most once per run.
5. Say plainly in `not_measured_it` what the test cannot tell. Do not claim more.
6. Introduction and notes follow the readability rules of the item brief: sentences
   of at most 25 words, no capitals, no emoji.
7. Pin descent items with the same care as starting items: the teacher approves
   everything the student will see, and the test never draws on anything else.
   Items of the descent pool must be validated too (`E-ITEM-NOT-PASSED`).
8. Scope: do not pin items with content of in-progress or next-year lines in skills
   the student has studied.
9. Uncertain programme facts are reported to the teacher, not decided here.

## Public repository

Everything you write into files the repository can see is public: say "the
student" and "the teacher", with no names, school, city or exam details.
