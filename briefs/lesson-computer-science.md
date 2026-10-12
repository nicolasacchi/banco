---
name: lesson-computer-science
version: 1
formats: banco.lesson/2
---

# Brief: lessons of informatica (`computer_science`), an addendum to `lesson`

Read `banco brief show lesson` first: this addendum adds what is particular to the subject, and nothing here changes a number of that brief.
You write one topic of the course for the student, as there. Work only through `banco`, start with `banco status`, and never ask for a decision: the teacher approves
the topic in the browser, you stop at `awaiting_teacher`. Skeleton of the contracts (W2-0): the rules below are the designer's; the track that builds the
pieces completes this brief when they become available, and a type that is not `available` is refused at submit (`E-LESSON-BLOCK`).

## Colour roles

Roles of the subject's palette (`config/banco/lesson_palette.yml`). The carrier says how a role is told apart without colour.

- `variable` (variabile): icon, icon `box`, shape box, question "Che nome ha la scatola?".
- `condition` (condizione): icon, icon `diamond`, shape diamond, question "È vera o falsa?".
- `weight` (peso): glyph, shape weight.
- `sign` (bit del segno): icon, icon `circle-minus`, shape circle, question "Quale bit pesa meno?".
- `carry` (riporto): icon, icon `corner-up-left`, shape triangle, question "Che cosa passa alla colonna dopo?".
- `reference` (riferimento che si sposta): icon, icon `move-down`, shape square, question "Che cosa cambia quando copio?".
- `locked` (bloccato con $): icon, icon `lock`, shape ring, question "Che cosa non si sposta?".
- `output` (output): icon, icon `monitor`, shape star, question "Che cosa scrive il programma?".

## Step verbs

The `tag` of a step in a procedure, an example or a solution:

- `read` (Leggi), icon `keyboard`.
- `assign` (Calcola e metti), icon `arrow-left-right`.
- `test` (Controlla la condizione), icon `diamond`.
- `repeat` (Torna al rombo), icon `repeat`.
- `write` (Scrivi), icon `monitor`.
- `pad` (Porta a 8 bit), icon `ruler`.
- `invert` (Inverti i bit), icon `flip-horizontal-2`.
- `add_one` (Aggiungi 1), icon `plus`.
- `sum_weights` (Somma i pesi), icon `sigma`.
- `verify` (Controlla), icon `check-check`.
- `divide` (Dividi per la base), icon `divide`.
- `group` (Raggruppa), icon `binary`.
- `copy` (Copia la formula), icon `copy`.
- `lock` (Blocca con $), icon `lock`.

## Icons

Only these names, besides the structural ones of the lesson brief, and only with a meaning (`E-LESSON-ICON`):

`workflow`, `box`, `equal-not`, `arrow-left-right`, `diamond`, `repeat`, `list-ordered`, `code-xml`, `monitor`, `keyboard`, `binary`, `rotate-ccw`, `weight`, `flip-horizontal-2`, `plus`, `ruler`, `sigma`, `check-check`, `divide`, `sheet`, `lock`, `copy`, `mouse-pointer-click`, `palette`, `type`, `toggle-right`, `scale`, `circle-minus`, `corner-up-left`, `move-down`.

## Types of this subject

| Piece | Kind | Status | Batch | Track |
|---|---|---|---|---|
| `register` | diagram | available | w2-1 | T9 |
| `column_calc` | diagram | available | w2-1 | T9 (`op: repeated_division` is w2-3) |
| `input: bits` | check option | available (it carries a `profile`, still T1's) | w2-1 | T9 |
| `program` | diagram | draft | w2-2 | T9 |
| `select` | check | reserved | w2-1 | T1 |

Only `available` pieces can be used; `banco lesson submit --dry-run` says what is not. Until a piece lands, use the per-card fallback of the card plan.

## How to write the pieces that are available

- `register view: row`: `width`, `base` (2, 8, 10, 16), `value` with exactly `width` digits (leading zeros are part of the register), `read: unsigned | twos`, `weights: true` (the first weight is the negative one in two's complement), `groups: 4`, `group_digits: true` (the hex digit under each group of four), `mark` (a role marker under a digit, positions from the left starting at 1), `states` with a new `value` and a short `op_it` ("Inverti ogni bit"). The readout ("Il registro con segno vale -5") and the sum of the weights are ours: never write them. `toggle: true` (base 2) makes every bit a switch; `goals` ("Prova a fare ...") name numbers the register can show: the card says "Sì" when one is reached, nothing is graded. A figure with `toggle` shows every value of its width: no check on the same card may ask for one of them (`E-CHECK-ANSWER-BY-SIMULATION`), and a wider register than 8 bits cannot sit on a card with a check at all.
- `register view: ring`: `width` 3 or 4, `read: unsigned | twos | both`, `cliff: true` (the seam where the value jumps), `pointer` and `step: true` (the student moves it with -1 and +1), `highlight` (a code and a word), `moves` (`from` and `by`: the landing code is computed and drawn as an arc along the ring). The codes are read off the pointer and the legend, not written round the circle.
- `column_calc`: `op: add | sub | mul`, `a`, `b` (at most `width` digits; a multiplier has at most 4), `width` (a phone shows 8 digits, not 16), `reveal: columns` to show the work one column (one partial product for `mul`) at a time with Avanti, `read: unsigned | twos`. A carry that leaves the register falls out to the left, dashed, in the role `carry`; a borrow across zeros changes every digit it runs through. Carries, borrows, partial products and the result are computed: you give only the two numbers.
- `input: bits` on a `normalized_text` check: eight switches in two groups of four instead of a typed line; the check carries `profile: {name: binary, width: 8, leading_zeros: required}`, the answer is exactly 8 bits, and so is every `errors[].answer`. When the error under test is `padding_missing` (too few bits) the check keeps the typed line, because switches always give the whole width. No weights are drawn on the switches.

## Rules of the subject

- Bits are always grouped by 4 with a thin space, in text, diagrams and answers; an answer of 8 bits is given with 8 switches.
- Every digit of a register sits in its own fixed cell, so columns align without a monospaced font.
- Code is written in `[[code:...]]` spans (at most 40 characters) and in the body font with indentation guides.
- The decimal comma meets code: a number is written with a comma in the flowchart and with a point in the listing; say it where it matters.
- The VB listing is generated by our code from the structure of the `program`; the agent never writes it.
- A program is data in a closed language: Ruby parses it, only the server's Chrome runs it.

## Public repository

The code and these briefs are public. Lessons live in the database, but anything you write into a file or a report the repository can see is public. No name of the student or of the household, no school, no city, no exam-session details, no programme text beyond the fragments of your refs. Say "the student" and "the teacher".
