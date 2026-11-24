---
name: review
version: 4
formats: banco.review/1
---

# Brief: expert review of an item revision (version 4)

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
line the item cites that the skill does not). When an instance shows a figure, `banco review open REV` also writes it as a PNG
file in `banco-figures/REV/` (`--dir DIR` chooses another parent folder: the files go to `DIR/REV/`, so several revisions can share it): its `path`, `alt_it` and the `instances` that show it are in
`figures`, and the instance's `display.figure.file` names it. Look at every figure file: check the drawing against the key, the
alt text and the stored data, as the student sees it; a figure that is missing or unreadable is a finding (`banco review open` then prints a `warnings` line and exits with `E-FIGURE-MISSING`, after printing the item). `banco review submit REV --file review.json` sends the
result. Never ask for a decision; the teacher disposes of every finding.

**Look at the pictures of the instances first.** `banco review open REV` asks the server to draw every instance as the student sees it on a 390 px
phone and prints `item_shots.fetch`, the command that brings the pictures: `banco item shots REV --dir DIR --wait` writes
`DIR/REV/instance-NN_390x844.webp`, one whole-page picture per instance (NN is the instance number), with the findings of the drawing (`errors`: a
page wider than the phone, a box that clips its text, a formula that did not draw, markup printed as text, a figure that did not load). Open each file as an image before you
read the keys: an item that overflows, cuts a formula or hides its question on a phone is a finding (point 11 if it is the reading load or the interface, else the point
the defect belongs to), quoted from the item text that causes it. A choice, a matching and an ordering are drawn shuffled with a fixed seed: the number on an option, a row or a
step is its position in `shown_order` (printed with each file), the ids of the item are the stored ones. The pictures never show the key. If they cannot be had, say so in your report.

Search for duplicates: `banco search "WORDS" --subject KEY` finds the lessons, items and findings that already exist, drafts included; a near copy of one of them is a finding. Check a cited reference text with `banco search "WORDS" --kind reference_article`. Run `banco search --like KEY` (a key, or a ref such as `item:KEY`; a whole lesson is `lesson:KEY`, its card N `lesson_card:KEY#N`) on what you review: its nearest neighbours are the candidates for duplicates.

## The checklist (11 points, 13 for a practice item, two more for a bilingual item, in this order)

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

An item of `english` or `spanish` written in the target language (`bilingual: true`, with `stem_en`/`stem_es` beside `stem_it`, options with
`text` and `text_it`, and so on: `banco review open` shows both texts side by side) is reviewed on two more points, which keep their own
numbers **14 and 15** whether the item is a practice item or not. A practice item that is bilingual has 15 points (1 to 15); another bilingual item
has 13 (1 to 11, then 14 and 15); an item that is not bilingual keeps its 11 or 13 (`E-REVIEW-CHECKLIST`, which also checks the ids):

14. The Italian translation: wrong, adding or dropping something, or giving the key away. Read every Italian text against its target-language
    text, pair by pair (stem, options, hints, messages, solution steps, final): the student can always open it. A translation that
    makes the answer obvious (a «translate this» task whose Italian prompt is the exercise, matching whose Italian options are the answer, a hint
    or a stem in Italian that names the key) is a finding with `field` `translation_leak`; a translation that is wrong or that changes the meaning,
    the level or the number of things is a finding with `field` `translation_fidelity`. The Italian of a reading passage is an exception: the
    student has it only after answering, so it cannot leak, but it must still be faithful.
    An item with `translate_material: false` has **no** Italian of its instance sentence, options, rows and final by design: do not file their absence. Check instead that the marker is right: the material is a form, and no hint, message or Italian instruction gives the key; an exercise that translated a form item (Italian options that show the answer) is a `translation_leak`.
15. The target-language text: above the level of a learner (sentences of at most 12 words, the first 3000 words of the language, plain
    grammar), unclear, with Italian words in it, or with a name that is not a common given name (never the student's or his household's).

The blind solver of a practice item sees what the student sees before asking for help: prompt and
display, never hints, messages or solutions. The blind solver of a bilingual item answers from the target-language text, with the Italian
translation in front of it as the student has it when he opens it (never the Italian of a reading passage, which comes after the answer): if
it can answer from the Italian alone, that is a `translation_leak`.

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

The direction of an accent (è/é, à/á…) is never tested and never makes an answer wrong (D-296); a missing accent and an apostrophe for an accent still count.
