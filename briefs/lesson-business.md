---
name: lesson-business
version: 1
formats: banco.lesson/2
---

# Brief: lessons of economia aziendale (`business`), an addendum to `lesson`

Read `banco brief show lesson` first: this addendum adds what is particular to the subject, and nothing here changes a number of that brief.
You write one topic of the course for the student, as there. Work only through `banco`, start with `banco status`, and never ask for a decision: the teacher approves
the topic in the browser, you stop at `awaiting_teacher`. Skeleton of the contracts (W2-0): the rules below are the designer's; the track that builds the
pieces completes this brief when they become available, and a type that is not `available` is refused at submit (`E-LESSON-BLOCK`).

## Colour roles

Roles of the subject's palette (`config/banco/lesson_palette.yml`). The carrier says how a role is told apart without colour.

- `creditor` (chi incassa): icon, icon `piggy-bank`, shape circle, question "Chi riceve il denaro?".
- `debtor` (chi paga): icon, icon `wallet`, shape weight, question "Chi deve pagare?".
- `bank` (banca): icon, icon `landmark`, shape box, question "Quale banca?".
- `third` (terza persona): icon, icon `user-plus`, shape star, question "A chi passa il titolo?".
- `base` (imponibile): glyph, shape square.
- `tax` (IVA): glyph, shape diamond.
- `outside` (fuori dall'imponibile): glyph, shape ring.
- `discount` (sconto): glyph, shape triangle.

## Step verbs

The `tag` of a step in a procedure, an example or a solution:

- `read` (Leggi i dati), icon `file-text`.
- `discount` (Togli lo sconto), icon `tag`.
- `base` (Fai l'imponibile), icon `square-dashed`.
- `tax` (Calcola l'IVA), icon `percent`.
- `round` (Arrotonda), icon `calculator`.
- `total` (Fai il totale), icon `sigma`.
- `verify` (Controlla), icon `check-check`.
- `date` (Scrivi luogo e data), icon `calendar-days`.
- `amount` (Scrivi l'importo), icon `banknote`.
- `words` (Scrivi in lettere), icon `type`.
- `fill` (Scrivi il nome), icon `pen-line`.
- `sign` (Firma), icon `signature`.
- `endorse` (Gira), icon `arrow-right-left`.

## Icons

Only these names, besides the structural ones of the lesson brief, and only with a meaning (`E-LESSON-ICON`):

`receipt`, `percent`, `tag`, `square-dashed`, `sigma`, `check-check`, `calculator`, `pen-line`, `signature`, `type`, `calendar-days`, `clock`, `hourglass`, `landmark`, `wallet`, `piggy-bank`, `user-plus`, `banknote`, `package`, `truck`, `handshake`, `megaphone`, `repeat`, `arrow-right-left`, `store`, `scale`, `coins`, `file-text`.

## Types of this subject

| Piece | Kind | Status | Batch | Track |
|---|---|---|---|---|
| `document` | diagram | available | w2-1 | T8 |
| `bar_model` | diagram | reserved | w2-1 | T6 |
| `network` | diagram | reserved | w2-1 | T4b |
| `select` | check | reserved | w2-1 | T1 |
| `amount_words` | check | draft | w2-2 | T8 |

Only `available` pieces can be used; `banco lesson submit --dry-run` says what is not. Until a piece lands, use the per-card fallback of the card plan.

## Rules of the subject

- Our code computes every amount, date and amount in words that a drawing shows: the agent writes data, never a total.
- Roles follow who pays and who collects, never the Latin word: `creditor`, `debtor`, `bank`, `third`.
- Amounts look like Italian amounts: thousands dot, decimal comma, two decimals, aligned at the comma.
- Checks ask for meaning (which row, which base, who signs, inside or outside the fence); computing checks use calculator-friendly numbers.
- Real life first: the cheque a seller of a used car wants, the receipt from the bar; never invented market data.
- Invented names only on documents; no page number.

## Public repository

The code and these briefs are public. Lessons live in the database, but anything you write into a file or a report the repository can see is public. No name of the student or of the household, no school, no city, no exam-session details, no programme text beyond the fragments of your refs. Say "the student" and "the teacher".
