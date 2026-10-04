---
name: skill-graph
version: 1
formats: banco.skill_graph/1
---

# Brief: skill graphs (version 1)

You write, for one subject, the graph of skills the entry diagnosis can measure,
as `banco.skill_graph/1` (`config/banco/schemas/skill_graph.json`). The teacher
approves a graph first, then the items, so no work is redone.

Start with `banco status` and this brief. Work only through `banco`
(`banco syllabus lines --source KEY --from N --to M`, `banco skill-graph
open|submit|coverage --subject KEY`).
Never ask for a decision: you stop at `awaiting_teacher`.

## Shape

- `skills[]`: `{key, label_it, layer, scope, scope_reason_it?, prerequisites[],
  composite_of?[], refs[], errors[]}`.
- Key: `<subject>.<kebab-slug>`, for example `math.linear-equation-integer`. Subject
  keys: math, italian, history, geography, english, spanish, computer_science,
  chemistry, biology, business, law_economics. Short inventory prefixes map as
  mat=math, it=italian, hist=history, geo=geography, eng=english, es=spanish,
  inf=computer_science, che=chemistry, bio=biology, eca=business, dir=law_economics.
- `layer`: `core` (needed by several topics of the next year), `sec`, `opt`.
- `scope`: `studied`, `integration_studied` (star), `in_progress` (star-empty or
  both), `middle_school` (from the lower school; carries `scope_reason_it`),
  `not_in_prima` (not in the prior-year programme; carries `scope_reason_it`).
  `middle_school` and `not_in_prima` have no prior-year refs.
- `refs[]`: `{source, line, fragment, role}`; role `taught_in` (prior-year line) or
  `needed_by` (line of the current-year programme that needs the skill). The
  fragment is an exact substring of the line. Transcriber lines are never cited.
- `prerequisites[]`: skill keys, possibly in another subject only if that skill is
  already in an approved graph.
- `errors[]`: typical errors `{code, description_it, implicates[]}`. `implicates`
  names the prerequisites an error points at: the engine descends there.
- `composite_of`: a multi-step skill whose typical errors implicate 2 or more
  distinct prerequisites lists them.
- `excluded[]`: `{line, reason_it, fragment?}` for every non-empty line of the
  subject's prior-year range that no skill cites. For a line that is only partly
  measured, cite what a skill measures and add an entry with the `fragment` (an
  exact substring of the line) that no skill measures; `coverage` lists the rest in
  `partial[]` with the cited and excluded fragments of each line.

## Rules (version 1)

1. Every skill cites a prior-year line, or is `middle_school` or `not_in_prima`,
   and has a current-year line that needs it, directly or through a skill that
   depends on it. A skill that nothing needs is not written.
2. `banco skill-graph coverage --subject KEY --json` must show `uncovered` empty:
   every non-empty line of the range is cited or excluded with a reason the teacher
   can read.
3. Scope follows the programme markers (the line's own, or `block_marker` on the
   lines under a marked header; `W-SCOPE-MARKER` warns when they disagree) and
   nothing else: do not upgrade an
   in-progress block to studied because it would be convenient.
4. Soft sizes: about 20 skills for mathematics, 7 to 12 for the other subjects;
   a sitting decides 6 to 10 skills, so mark which are `core`.
5. No cycles. Prerequisites go down toward simpler skills.
6. Typical errors are errors a learner really makes, written as a description, not
   as a rule. No over-absolute wording ("sempre", "mai", "solo") without a
   counterexample check.
7. Programme lines that are unclear or look wrongly transcribed go to the teacher
   in your report; do not build a skill on them. Never invent a line number or a
   fragment.
8. Labels are neutral Italian (`label_it`) of a few words; no terms of a textbook
   you have not seen.

## Public repository

Programme text and the student are private. Quote only the short fragments the
format requires, through the CLI, and do not copy programme text into files or
reports the repository can see. Say "the student" and "the teacher".
