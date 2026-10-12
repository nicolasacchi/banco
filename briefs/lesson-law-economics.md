---
name: lesson-law-economics
version: 1
formats: banco.lesson/2
---

# Brief: lessons of diritto ed economia (`law_economics`), an addendum to `lesson`

Read `banco brief show lesson` first: this addendum adds what is particular to the subject, and nothing here changes a number of that brief.
You write one topic of the course for the student, as there. Work only through `banco`, start with `banco status`, and never ask for a decision: the teacher approves
the topic in the browser, you stop at `awaiting_teacher`. Skeleton of the contracts (W2-0): the rules below are the designer's; the track that builds the
pieces completes this brief when they become available, and a type that is not `available` is refused at submit (`E-LESSON-BLOCK`).

## Colour roles

Roles of the subject's palette (`config/banco/lesson_palette.yml`). The carrier says how a role is told apart without colour.

- `right` (chi ha il diritto): icon, icon `key-round`, shape circle, question "Chi può pretendere?".
- `duty` (chi deve): icon, icon `hand-coins`, shape weight, question "Chi deve fare qualcosa?".
- `people` (popolo): icon, icon `users`, shape square, question "Chi vota?".
- `legislative` (Parlamento): icon, icon `landmark`, shape box, question "Chi fa le leggi?".
- `executive` (Governo): icon, icon `briefcase`, shape triangle, question "Chi governa?".
- `judicial` (giudici): icon, icon `gavel`, shape diamond, question "Chi giudica?".
- `guarantee` (garanzia): icon, icon `shield`, shape star, question "Chi vigila sulle regole?".
- `norm` (norma): icon, icon `scroll-text`, shape ring, question "Qual è la regola?".

## Step verbs

The `tag` of a step in a procedure, an example or a solution:

- `facts` (Leggi il fatto), icon `file-text`.
- `rule` (Trova la regola), icon `scroll-text`.
- `apply` (Confronta), icon `arrow-left-right`.
- `outcome` (Concludi), icon `gavel`.
- `count` (Conta i voti), icon `calculator`.

## Icons

Only these names, besides the structural ones of the lesson brief, and only with a meaning (`E-LESSON-ICON`):

`handshake`, `signature`, `file-text`, `stamp`, `newspaper`, `landmark`, `gavel`, `scroll-text`, `users`, `briefcase`, `shield`, `key-round`, `hand-coins`, `vote`, `route`, `repeat`, `undo-2`, `calendar-days`, `clock`, `ban`, `git-branch`, `book-a`, `building-2`, `crown`, `user`, `arrow-left-right`, `calculator`.

## Types of this subject

| Piece | Kind | Status | Batch | Track |
|---|---|---|---|---|
| `seats` | diagram | reserved | w2-1 | T6 |
| `network` | diagram | reserved | w2-1 | T4b |
| `flow` | diagram | available | r1 | T4b |
| `source` | block | available (`kind: legal`; the historical kinds are W2-2) | w2-1 | T8 |
| `document` | diagram | available | w2-1 | T8 |
| `tiles` | check | reserved | w2-1 | T1 |

Only `available` pieces can be used; `banco lesson submit --dry-run` says what is not. Until a piece lands, use the per-card fallback of the card plan.

## Rules of the subject

- The barrier is the legal language: long sentences, rare words. The plain text comes first, the legal words next; both are printed.
- Quotations of the Constitution and of the civil code are exact substrings of the imported reference text (`E-QUOTE-REF`); never quote from memory.
- The typical errors are swaps of direction or role (debtor and creditor, duty and obligation): draw them with arrows and roles, not with a concept map.
- The same role for the same organ on every card and lesson: Parlamento is always `legislative`.
- A check never asks a number the readout of a `seats` figure shows; the range of `try` stops short of the answer.
- Real cases are invented ones: invented names only.

## Public repository

The code and these briefs are public. Lessons live in the database, but anything you write into a file or a report the repository can see is public. No name of the student or of the household, no school, no city, no exam-session details, no programme text beyond the fragments of your refs. Say "the student" and "the teacher".
