---
name: lesson-chemistry
version: 1
formats: banco.lesson/2
---

# Brief: lessons of chimica (`chemistry`), an addendum to `lesson`

Read `banco brief show lesson` first: this addendum adds what is particular to the subject, and nothing here changes a number of that brief.
You write one topic of the course for the student, as there. Work only through `banco`, start with `banco status`, and never ask for a decision: the teacher approves
the topic in the browser, you stop at `awaiting_teacher`. Skeleton of the contracts (W2-0): the rules below are the designer's; the track that builds the
pieces completes this brief when they become available, and a type that is not `available` is refused at submit (`E-LESSON-BLOCK`).

## Colour roles

Roles of the subject's palette (`config/banco/lesson_palette.yml`). The carrier says how a role is told apart without colour.

- `coefficient` (coefficiente): glyph, shape diamond.
- `subscript` (pedice): glyph, shape triangle.
- `group` (pacchetto): position, shape box.
- `solid` (solido): icon, icon `cuboid`, shape square, question "Ha forma propria?".
- `liquid` (liquido): icon, icon `droplet`, shape circle, question "Scorre e prende la forma del recipiente?".
- `gas` (gassoso): icon, icon `wind`, shape ring, question "Riempie tutto il recipiente?".
- `heat_in` (assorbe calore): icon, icon `flame`, shape star, question "Il calore entra?".
- `heat_out` (cede calore): icon, icon `snowflake`, shape weight, question "Il calore esce?".

## Step verbs

The `tag` of a step in a procedure, an example or a solution:

- `symbols` (Trova i simboli), icon `case-sensitive`.
- `group` (Apri il pacchetto), icon `parentheses`.
- `subscript` (Leggi i pedici), icon `subscript`.
- `coefficient` (Moltiplica per il coefficiente), icon `x`.
- `count` (Conta gli atomi), icon `sigma`.
- `classify` (Elemento o composto?), icon `boxes`.
- `axes` (Leggi gli assi), icon `move-horizontal`.
- `plateau` (Trova le soste), icon `thermometer`.
- `read` (Leggi il valore), icon `scan-eye`.
- `name` (Dai il nome), icon `tag`.
- `state` (Trova lo stato), icon `layers-3`.
- `compare` (Confronta), icon `git-compare`.
- `verify` (Controlla), icon `check-check`.

## Icons

Only these names, besides the structural ones of the lesson brief, and only with a meaning (`E-LESSON-ICON`):

`atom`, `flask-conical`, `test-tube`, `beaker`, `thermometer`, `thermometer-sun`, `thermometer-snowflake`, `flame`, `snowflake`, `droplet`, `droplets`, `wind`, `cuboid`, `boxes`, `syringe`, `recycle`, `case-sensitive`, `subscript`, `parentheses`, `hash`, `sigma`, `x`, `scan-eye`, `tag`, `layers-3`, `git-compare`, `chart-line`, `mountain`, `move-horizontal`, `check-check`.

## Types of this subject

| Piece | Kind | Status | Batch | Track |
|---|---|---|---|---|
| `formula` | diagram | reserved | w2-1 | T7 |
| `molecule` | diagram | reserved | w2-1 | T7 |
| `periodic_table` | diagram | reserved | w2-1 | T7 |
| `particles` | diagram | draft | w2-2 | T7 |
| `phase_changes` | diagram | draft | w2-2 | T7 |
| `chart` | diagram | draft | w2-2 | T6 |
| `select` | check | reserved | w2-1 | T1 |

Only `available` pieces can be used; `banco lesson submit --dry-run` says what is not. Until a piece lands, use the per-card fallback of the card plan.

## Rules of the subject

- Every idea about matter uses `particles` with `rows: [macro, particles, formula]`, unless it is about one formula.
- Formulas only in `\ce{}`. Never type a count, a melting point, a boiling point or a curve point: the components compute them, quote `describe`.
- Ionic compounds and metals have "unità", not molecules.
- Only the seven names of the changes of state in `chem/terms`.
- A pictogram row, never an invented description of what the student would see in a laboratory.
- Warm and cool colours (`heat_in`, `heat_out`) are a convention of heat, not of right and wrong.

## Public repository

The code and these briefs are public. Lessons live in the database, but anything you write into a file or a report the repository can see is public. No name of the student or of the household, no school, no city, no exam-session details, no programme text beyond the fragments of your refs. Say "the student" and "the teacher".
