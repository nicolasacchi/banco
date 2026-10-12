---
name: lesson-geography
version: 1
formats: banco.lesson/2
---

# Brief: lessons of geografia (`geography`), an addendum to `lesson`

Read `banco brief show lesson` first: this addendum adds what is particular to the subject, and nothing here changes a number of that brief.
You write one topic of the course for the student, as there. Work only through `banco`, start with `banco status`, and never ask for a decision: the teacher approves
the topic in the browser, you stop at `awaiting_teacher`. Skeleton of the contracts (W2-0): the rules below are the designer's; the track that builds the
pieces completes this brief when they become available, and a type that is not `available` is refused at submit (`E-LESSON-BLOCK`).

## Colour roles

Roles of the subject's palette (`config/banco/lesson_palette.yml`). The carrier says how a role is told apart without colour.

- `temperature` (temperatura): icon, icon `thermometer`, shape circle, question "Quanti gradi?".
- `precipitation` (precipitazioni): icon, icon `cloud-rain`, shape square, question "Quanti millimetri di pioggia?".
- `arid` (mese arido): icon, icon `sun-dim`, shape triangle, question "La pioggia sta sotto la linea?".
- `hot` (fascia calda): icon, icon `sun`, shape star.
- `temperate` (fascia temperata): icon, icon `leaf`, shape diamond.
- `cold` (fascia fredda): icon, icon `snowflake`, shape ring.
- `place` (luogo): icon, icon `map-pin`, shape box, question "Dove?".
- `flow` (movimento): icon, icon `route`, shape weight, question "Da dove a dove?".

## Step verbs

The `tag` of a step in a procedure, an example or a solution:

- `environment` (Ambiente), icon `mountain`.
- `population` (Popolazione), icon `users`.
- `identity` (Identità), icon `languages`.
- `economy` (Economia), icon `factory`.
- `connect` (Collega), icon `link`.
- `locate` (Trova sulla carta), icon `map-pin`.
- `read_temp` (Leggi la temperatura), icon `thermometer`.
- `read_rain` (Leggi la pioggia), icon `cloud-rain`.
- `arid` (Trova i mesi aridi), icon `sun-dim`.
- `decide` (Decidi), icon `git-branch`.
- `biome` (Trova il bioma), icon `trees`.
- `compute` (Calcola), icon `calculator`.

## Icons

Only these names, besides the structural ones of the lesson brief, and only with a meaning (`E-LESSON-ICON`):

`thermometer`, `cloud-rain`, `sun`, `sun-dim`, `snowflake`, `leaf`, `trees`, `tree-palm`, `mountain`, `mountain-snow`, `waves`, `droplets`, `globe`, `earth`, `map-pin`, `route`, `users`, `languages`, `landmark`, `factory`, `wheat`, `ship`, `coins`, `chart-column`, `building-2`, `flame`, `git-branch`, `link`, `calculator`.

## Types of this subject

| Piece | Kind | Status | Batch | Track |
|---|---|---|---|---|
| `climograph` | diagram | reserved | w2-1 | T6 |
| `map` | diagram | available | w2-1 | T5 |
| `insolation` | diagram | available | w2-1 | T5 |
| `cross_section` | diagram | available | w2-1 | T5 |
| `chart` | diagram | draft | w2-2 | T6 |
| `chain` | diagram | reserved | w2-1 | T4b |
| `timeline` | diagram | reserved | w2-1 | T4a |
| `select` | check | reserved | w2-1 | T1 |

Only `available` pieces can be used; `banco lesson submit --dry-run` says what is not. Until a piece lands, use the per-card fallback of the card plan.

## Rules of the subject

- The four lenses (ambiente, popolazione, identità, economia) are parts of every country lesson; the "scheda Paese" is its summary schema.
- Maps are north-up, with ids and not names; at most 8 labels per map; "Confini approssimativi" is always printed.
- Every number comes from the data reference, rounded, with its year; choose climate stations whose class is unambiguous under the lesson's own rules.
- A check never asks what the visible layer prints (no arid hatch on a "tocca i mesi aridi").
- No mining in sector checks until the book's convention is known.
- The forest is not "the lungs of the world" in the oxygen sense: the lesson says what it does.

## Public repository

The code and these briefs are public. Lessons live in the database, but anything you write into a file or a report the repository can see is public. No name of the student or of the household, no school, no city, no exam-session details, no programme text beyond the fragments of your refs. Say "the student" and "the teacher".
