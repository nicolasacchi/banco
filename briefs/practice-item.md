---
name: practice-item
version: 2
formats: banco.item/1
---

# Brief: practice items (version 2)

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
- Instances of one item must look different to the student: different cases or rows, not the same rows reshuffled (`W-INSTANCES-ALIKE`).
- A `matching` with 2 categories (a right/wrong judge): vary the split of the labels across the instances, never the same split in every instance, and give every instance at least 2 rows of each label it uses (`W-MATCHING-JUDGE-ROWS`, D-301, D-314). An identical split (always 2-2-2, always 3-3) lets a student count the last row from the others.
- Per skill a topic needs at least 20 distinct instances over its 2 to 4 pinned items, 12 of them hard
  to guess (written answers, an ordering or matching of 4 or more): plan the items so that the pool
  reaches that. Write the first, level 1, item first.
- Do not copy the lesson's exercises or worked examples (`W-TOPIC-INSTANCE-IN-LESSON`) and do not reuse
  the instances of the diagnosis items of the skill (`W-PRACTICE-DIAGNOSIS-OVERLAP`).

## Rules every author applies from the first draft

The first courses taught these rules; reviewers and blind solvers check them. They are general: they hold for every subject.

- **Positions do not matter.** The server reshuffles the options of a choice, the elements of an ordering and both columns of a
  matching at every serve (`Diagnosis::Rekey`, shared by practice), and the student never sees the stored order. Do not vary
  the position of the key, do not balance a, b, c, and do not spend effort on it; a reviewer or a solver raises no finding about
  where the key stands in the stored item. What still matters is the content: the key is never the only option worded
  differently or the only one that is longer, and every instance of an item offers the same full set of labels or options (a
  missing label gives the answer away and removes a trap).
- **Instances look different.** Different cases, rows, numbers and sentence patterns, not one sentence model with another name or
  number. Vary the lures and the number of distinct keys: an item whose answers repeat three times in ten instances is a short item.
  Several instances that share a text pattern are alike even when no row is identical (`W-INSTANCES-ALIKE` catches only the identical rows).
- **Hints guide, they never give.** A hint says what to look at, which rule applies, the next step. It never names the key, a
  row, a pair, an option or a position, never counts something the answer counts, and never eliminates distractors one by one
  until the key is left. Write hints per instance when the instances differ in kind; an item-level hint must make sense for every
  instance, also the ones that look different from the first.
- **Messages and solutions that fit every instance.** A typical-error `message_it` is bound to a code and shown for every instance
  that carries the code: word it so that it is true for each of them (a message about "the number in front" must fit an instance
  with no such number) and for the option it is attached to. It names the wrong step and the rule, never the key of the instance
  or of another. An error value is what a student making that mistake would really type, and it differs from the key and from the
  other values.
- **Accept lists take every correct answer.** For a typed answer list every correct form the prompt allows: the numeral and the
  word, the form with and without the preposition or the article, the common synonym, the contraction and its full form. The
  same item accepts the same kind of forms in every instance. Where you cannot list them, pin the form in the prompt ("lo stesso
  verbo", "la stessa persona") and say the answer format (`answer_format_it`): unit, decimal comma, how many words.
- **No near copy.** Not of the entry test, not of the lesson's own exercises and worked examples, not of another item. A near copy
  is the same scene with other names, the same sub-expression, the same sentence in other words. `W-PRACTICE-DIAGNOSIS-OVERLAP`
  sees only an exact match: before you write and again on what you wrote, run `banco search --like KEY` and compare with the entry
  test items of the same skill (`banco item open` on them).
- **Cause and effect never rest on the direction of "perché".** Readers confuse "A perché B" with "B perché A". Show the two
  facts apart (two boxes, an arrow) or ask which fact is the cause; do not make the item measure how a subordinate clause reads.
- **Chains and orderings stand alone.** Every step of a chain, a timeline or an ordering is understood without its neighbours:
  no "Questi", "Poi", "Dieci anni dopo" that only make sense next to another step, and no two steps that say almost the
  same thing, so that the order has one defensible answer.
- **Hedged statements and no absolutes.** A rule with exceptions is a tendency ("di solito", "tra le cause"); traditions and legends
  are hedged ("secondo la tradizione"); a cause is one of several, never presented as the whole story. A harmless "sempre" that
  is true in the case at hand is allowed.
- **Sources and quotations are never invented.** Quote a text only from the imported references (`banco search --kind
  reference_article`, `prompt.quote`), or a short passage you are certain of, adapted and marked as such. Otherwise describe the
  source (what it is, who wrote it, when) without quoting. No page or line you have not seen.
- **Figures are readable at 340 px.** An item figure is an SVG asset shown as a picture: a counted square at least 13 px, labels
  at least every other line, text large enough on a phone, no script, no outside reference, no `data:` or `javascript:` in an
  attribute. The alt text says what the picture shows without the answer. Markup inside choice options is not rendered: plain
  text only. A long sentence as an ordering element overflows a phone: use short elements.
- **Say the answer format.** Practice refuses an answer it cannot read: the prompt or `answer_format_it` says the unit, the
  decimal comma, whether a percentage sign is written, how many words.
- **One rule, stated once.** The same rule in the lesson, the checks, the items, the messages and the hints, worded the same way
  and never two contradicting rules. A convention (dates, notation, terms) is the one the approved topics of the course use.
- **Exactly one right answer** per instance: defend every distractor, and for a typed answer think of the second correct way to say it.
- **Foreign languages.** The explanations are in Italian and the language is in `_en`, `_es`, `_la` keys and spans; write every
  verb form by hand and check it again; a correct but less common answer is accepted.

## Reviewers and solvers

A reviewer checks 13 points: the 11 of the review brief, plus 12 (hints: 2 to 4 per instance, from the
rule to the next step; none states the key; the last stops before the final value) and 13 (messages
and solution: each typical-error message names the mistake and the rule without the key; each
solution step is correct, says why, and ends at the key). A review of a practice item with another
number of points is `E-REVIEW-CHECKLIST`. The blind solver sees what the student sees before asking
for help: prompt and display, never hints, messages or solutions. Findings are answered with
`banco findings respond`, exactly as for diagnosis items. A reviewer or solver never judges the position of the key (see the rules above); a solver reads and solves every instance itself (`banco brief show solve`).

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

The direction of an accent (è/é, à/á…) is never tested and never makes an answer wrong (D-296); a missing accent and an apostrophe for an accent still count.
