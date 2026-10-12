---
name: lesson-biology
version: 1
formats: banco.lesson/2
---

# Brief: lessons of biologia (`biology`), an addendum to `lesson`

Read `banco brief show lesson` first: this addendum adds what is particular to the subject, and nothing here changes a number of that brief.
You write one topic of the course for the student, as there. Work only through `banco`, start with `banco status`, and never ask for a decision: the teacher approves
the topic in the browser, you stop at `awaiting_teacher`. Skeleton of the contracts (W2-0): the rules below are the designer's; the track that builds the
pieces completes this brief when they become available, and a type that is not `available` is refused at submit (`E-LESSON-BLOCK`).

## Colour roles

Roles of the subject's palette (`config/banco/lesson_palette.yml`). The carrier says how a role is told apart without colour.

- `phosphate` (fosfato): icon, icon `circle`, shape circle, question "Che cosa tiene unita la catena?".
- `sugar` (zucchero): icon, icon `pentagon`, shape pentagon, question "Qual è il pezzo a cinque lati?".
- `base` (base azotata): icon, icon `rectangle-horizontal`, shape box, question "Quale lettera porta?".
- `pair_at` (coppia A-T): glyph, shape diamond.
- `pair_cg` (coppia C-G): glyph, shape triangle.
- `prokaryote` (procariote): icon, icon `pill`, shape square, question "Una cellula senza nucleo?".
- `eukaryote` (eucariote): icon, icon `circle-dot`, shape ring, question "Una cellula con il nucleo?".
- `plant` (vegetale): icon, icon `leaf`, shape star, question "Solo nella cellula vegetale?".

## Step verbs

The `tag` of a step in a procedure, an example or a solution:

- `observe` (Osserva), icon `eye`.
- `compare` (Confronta), icon `git-compare`.
- `classify` (Classifica), icon `boxes`.
- `count` (Conta), icon `hash`.
- `measure` (Misura), icon `ruler`.
- `pair` (Appaia), icon `link-2`.
- `compute` (Calcola), icon `percent`.
- `name` (Dai il nome), icon `tag`.

## Icons

Only these names, besides the structural ones of the lesson brief, and only with a meaning (`E-LESSON-ICON`):

`microscope`, `dna`, `leaf`, `sprout`, `paw-print`, `pill`, `circle-dot`, `circle`, `pentagon`, `rectangle-horizontal`, `ruler`, `scaling`, `zoom-in`, `layers`, `link-2`, `copy`, `git-compare`, `book-a`, `puzzle`, `droplet`, `sun`, `recycle`, `heart-pulse`, `boxes`, `eye`, `hash`, `percent`, `tag`, `git-branch`, `scan-eye`.

## Types of this subject

| Piece | Kind | Status | Batch | Track |
|---|---|---|---|---|
| `strand` | diagram | available | w2-1 | T7 |
| `cell` | diagram | draft | w2-2 | T7 |
| `word_parts` | diagram | reserved | w2-1 | T3 |
| `scale` | diagram | draft | w2-2 | T6 |
| `nested` | diagram | draft | w2-2 | T4b |
| `bar_model` | diagram | reserved | w2-1 | T6 |
| `select` | check | reserved | w2-1 | T1 |

Only `available` pieces can be used; `banco lesson submit --dry-run` says what is not. Until a piece lands, use the per-card fallback of the card plan.

## Rules of the subject

- Sizes and percentages are always "circa" and come from the vetted reference (`bio/sizes`), never from memory.
- Schematic drawings only through `cell` and `strand`: never a hand-made picture of a cell.
- At most three new technical words per card, each in bold the first time and decoded with `word_parts` or one plain sentence.
- A mnemonic shape (the pentagon of the sugar, the tabs of the bases) is said to be a mnemonic: "le forme aiutano a ricordare".
- At most one `more` for the exceptions (the red blood cell, root cells).
- The pair colours (`pair_at`, `pair_cg`) are a rule of pairing, not the identity of a base: the letter says the base.

## Public repository

The code and these briefs are public. Lessons live in the database, but anything you write into a file or a report the repository can see is public. No name of the student or of the household, no school, no city, no exam-session details, no programme text beyond the fragments of your refs. Say "the student" and "the teacher".
