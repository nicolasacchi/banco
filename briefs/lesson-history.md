---
name: lesson-history
version: 1
formats: banco.lesson/2
---

# Brief: lessons of storia (`history`), an addendum to `lesson`

Read `banco brief show lesson` first: this addendum adds what is particular to the subject, and nothing here changes a number of that brief.
You write one topic of the course for the student, as there. Work only through `banco`, start with `banco status`, and never ask for a decision: the teacher approves
the topic in the browser, you stop at `awaiting_teacher`. Skeleton of the contracts (W2-0): the rules below are the designer's; the track that builds the
pieces completes this brief when they become available, and a type that is not `available` is refused at submit (`E-LESSON-BLOCK`).

## Colour roles

Roles of the subject's palette (`config/banco/lesson_palette.yml`). The carrier says how a role is told apart without colour.

- `rome` (Roma): icon, icon `landmark`, shape square.
- `other` (altri popoli): icon, icon `users`, shape circle.
- `senate` (Repubblica e Senato): icon, icon `vote`, shape triangle.
- `princeps` (Augusto, il principe): icon, icon `crown`, shape star.
- `cause` (): the same role as `italian.cause`, same colour, icon and shape.
- `effect` (conseguenza): icon, icon `flag`, shape ring, question "Che cosa ne segue?".
- `date` (data): glyph, shape weight.
- `source` (fonte): icon, icon `scroll-text`, shape box, question "Chi lo dice?".

## Step verbs

The `tag` of a step in a procedure, an example or a solution:

- `fact` (Il fatto), icon `pin`.
- `why` (Perché?), icon `circle-help`.
- `then` (Quindi), icon `arrow-right`.
- `when` (Quando?), icon `calendar`.
- `what` (Che cos'è?), icon `search`.
- `who` (Chi l'ha fatta?), icon `user`.
- `says` (Che cosa dice?), icon `quote`.
- `aim` (Perché l'ha fatta?), icon `target`.

## Icons

Only these names, besides the structural ones of the lesson brief, and only with a meaning (`E-LESSON-ICON`):

`landmark`, `users`, `vote`, `crown`, `milestone`, `flag`, `scroll-text`, `hourglass`, `calendar`, `swords`, `shield`, `coins`, `wheat`, `church`, `route`, `map-pin`, `waves`, `mountain`, `ship`, `image`, `git-branch`, `signpost`, `messages-square`, `list-ordered`, `quote`, `search`, `pin`, `arrow-right`, `user`, `target`.

## Types of this subject

| Piece | Kind | Status | Batch | Track |
|---|---|---|---|---|
| `timeline` | diagram | available | w2-1 | T4a |
| `chain` | diagram | available | w2-1 | T4b |
| `network` | diagram | available | w2-1 | T4b |
| `map` | diagram | available | w2-1 | T5 |
| `word_parts` | diagram | reserved | w2-1 | T3 |
| `source` | block | available (`kind: legal`; the historical kinds are W2-2) | w2-1 | T8 |
| `reveal` | block | available | w2-1 | T8 |
| `oral` | block | available | w2-1 | T8 |
| `image` | block | draft | w2-2 | T8 |
| `select` | check | reserved | w2-1 | T1 |
| `tiles` | check | reserved | w2-1 | T1 |

Only `available` pieces can be used; `banco lesson submit --dry-run` says what is not. Until a piece lands, use the per-card fallback of the card plan.

## Rules of the subject

- Dates and facts are history's numbers: every date, duration and century is recomputed by the components (`verify: chrono...`), every fact is checked against a second reference.
- Translations are our own, labelled "Traduzione semplificata", with the original in the block; no modern published Italian translation is copied; Latin only in "Il testo originale".
- Neutrality: no evaluative adjectives about people in the lesson's own voice; judgements appear only inside a `source`, attributed.
- Classification conventions vary (is a statue an iconographic or a material source?): checks use only unambiguous cases.
- Counterfactuals are always marked as hypotheses (`reveal` with options, "Togli una causa"); a check never asks "what would have happened".
- Maps: ids only, simplifications said in the caption. Images only if the operator allows them, with author, licence and link.

## Public repository

The code and these briefs are public. Lessons live in the database, but anything you write into a file or a report the repository can see is public. No name of the student or of the household, no school, no city, no exam-session details, no programme text beyond the fragments of your refs. Say "the student" and "the teacher".
