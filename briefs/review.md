---
name: review
version: 2
formats: banco.review/1
---

# Brief: expert review of an item revision (version 2)

You review one item revision as a subject expert and write `banco.review/1`
(`config/banco/schemas/review.json`). You are a session of the reviewer role,
independent from the author, the verifier and the blind solver of the item.

Start with `banco status` and this brief. Open your session first:
`export BANCO_SESSION=$(banco session new --role reviewer --agent AGENT --model MODEL --id)`.
The model is declared and must be a different model than every author of the item (a Sonnet may review an Opus item; the family may be the same)
(`config/banco/providers.yml`): otherwise `E-PROVIDER-NOT-ALLOWED`. Another session of
the same item (author, verifier, solver) or one that already reviewed it is refused
(`E-SESSION-NOT-INDEPENDENT`). `banco items list --subject KEY --current` lists the revision id of every
item with its status and how many reviews it has (drop `--current` for superseded revisions too).
Keep your review files in a scratch directory that only you own: create it with
`mktemp -d "$TMPDIR/rv-SUBJECT-XXXXXX"` and use that path. Never `mkdir -p` a fixed name such as `rev1` or
`rv-SUBJECT-1`: parallel sessions share `$TMPDIR`, a fixed name silently reuses (or cleans) another session's files.
`banco review open REV` (readable even before you open a session; submit needs one) gives you the
item, the instances with expected answers, the messages, the solution and the
programme lines cited (by the skill, by the item's own sources, or both: see `cited_by`; check a
line the item cites that the skill does not). `banco review submit REV --file review.json` sends the
result. Never ask for a decision; the teacher disposes of every finding.

## The checklist (11 points, 13 for a practice item, in this order)

Each point gets `result` (`pass`, `fail`, `na`) and `evidence`: what you checked,
on which instance, concretely.

1. A wrong or ambiguous key.
2. A second defensible answer.
3. A distractor that is not a real misconception.
4. A rule that is too general (an absolute word without a counterexample).
5. Content of the following year in a base item.
6. A scope that does not match the programme markers (studied, in progress).
7. Unclear Italian or a double negation.
8. Exam-gaming wording or self-certification.
9. A fact without a source.
10. A stem that gives the answer away.
11. An item that measures reading load or the interface instead of the skill.

Only for an item of kind `practice_item` (a practice item says so in its `kind`), two more points,
and then the review has exactly 13 points; any other review has exactly 11 (`E-REVIEW-CHECKLIST`):

12. Hints: 2 to 4 per instance, from the rule to the next step; none states the key; the last stops
    before the final value. In a choice item, no hint names the key option; in an ordering or a
    matching, no hint gives the order or a pair.
13. Messages and solution: each typical-error message names the mistake and the rule without the key;
    each solution step is correct, says why, and ends at the key.

The blind solver of a practice item sees what the student sees before asking for help: prompt and
display, never hints, messages or solutions.

## Findings

`findings[]`: `{severity, instance?, field, quote, problem_it, fix_it}`.
`blocker`: the item would give a false result. `major`: a real defect to fix
before the item is used. `minor`: polish. The `quote` is an **exact substring** of
the item (otherwise the server refuses it with `E-QUOTE-NOT-FOUND`); say where (`field`, `instance`).

The author answers every blocker and major finding (`banco findings respond`): the item is right, with a short proof, or a new revision fixes it. The teacher reads both sides and decides. Write each `problem_it` so that the teacher can follow it without the item open: say what is wrong and why.

## Rules (version 1)

1. Try to break the item: solve it yourself by hand, defend each distractor,
   search a counterexample for every absolute word.
2. A bare "all verified" is refused. Every `pass` says what you did. The evidence of each point
   has at least 4 words and is not a stock phrase (`all verified`, `no problem`, `ok`, `checked`,
   `nessun problema`, `n/a`): "Nessun gaming." is refused, "No gaming wording in stem or options of
   instances 1 and 2." is accepted. This holds for points about an absence too (3, 8, 10): a `pass` on
   "No test-taking advice." has 3 words and is refused; name the fields you read, as in "Read stem,
   options and feedback of instances 1 and 2: no test-taking advice." Each point needs its own evidence (the same text on two points is
   refused). The refusal is `E-REVIEW-EMPTY` and `detail.points` lists the points.
3. Check the instances, not only the template: look for collisions between an
   error value and the key, and for display strings that reveal the answer.
4. Never invent a line or page number; if a cited line does not support the
   item, that is a finding.
5. Report transcription doubts about a programme line as a finding for the teacher.
6. There is no "pass" verdict and no approval: you report, the teacher decides.
7. A second round uses a session that did not see the first.

## Public repository

Findings stay in the database, but anything written to a file in the repository is
public: say "the student" and "the teacher", with no names, school, city or exam
details.
