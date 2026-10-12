---
name: lesson-english
version: 1
formats: banco.lesson/2
---

# Brief: lessons of inglese (`english`), an addendum to `lesson`

Read `banco brief show lesson` first: this addendum adds what is particular to the subject, and nothing here changes a number of that brief.
You write one topic of the course for the student, as there. Work only through `banco`, start with `banco status`, and never ask for a decision: the teacher approves
the topic in the browser, you stop at `awaiting_teacher`. Skeleton of the contracts (W2-0): the rules below are the designer's; the track that builds the
pieces completes this brief when they become available, and a type that is not `available` is refused at submit (`E-LESSON-BLOCK`).

## Colour roles

Roles of the subject's palette (`config/banco/lesson_palette.yml`). The carrier says how a role is told apart without colour.

- `subject` (): the same role as `italian.subject`, same colour, icon and shape.
- `verb` (verbo): the same role as `italian.predicate`, same colour, icon and shape.
- `auxiliary` (ausiliare): icon, icon `hand-helping`, shape square, question "Chi aiuta il verbo?".
- `object` (): the same role as `italian.object`, same colour, icon and shape.
- `agent` (): the same role as `italian.agent`, same colour, icon and shape.
- `time` (): the same role as `italian.time`, same colour, icon and shape.
- `main` (frase principale): icon, icon `flag`, shape box, question "Qual è la frase che regge le altre?".
- `participle` (participio): icon, icon `list-ordered`, shape diamond, question "Qual è la terza forma?".

## Step verbs

The `tag` of a step in a procedure, an example or a solution:

- `split` (Trova le due frasi), icon `scissors`.
- `connective` (Trova la parola che apre), icon `key-round`.
- `object` (Trova l'oggetto), icon `box`.
- `tense` (Guarda il tempo), icon `clock`.
- `be` (Metti be al tempo giusto), icon `equal`.
- `participle` (Scrivi la terza forma), icon `list-ordered`.
- `agent` (Aggiungi by), icon `user-round`.
- `reread` (Rileggi ascoltando), icon `volume-2`.

## Icons

Only these names, besides the structural ones of the lesson brief, and only with a meaning (`E-LESSON-ICON`):

`volume-2`, `languages`, `hourglass`, `scissors`, `key-round`, `flag`, `hand-helping`, `message-square`, `clock`, `box`, `user`, `user-round`, `zap`, `repeat`, `check-check`, `equal`, `list-ordered`.

## Types of this subject

| Piece | Kind | Status | Batch | Track |
|---|---|---|---|---|
| `sentence` | diagram | available | r1 | T1 |
| `mirror` | diagram | reserved | w2-1 | T3 |
| `timeline` | diagram | reserved | w2-1 | T4a |
| `paradigm` | diagram | draft | w2-2 | T3 |
| `dialogue` | block | reserved | w2-1 | T3 |
| `tiles` | check | reserved | w2-1 | T1 |
| `listen` | check option | reserved | w2-1 | T2 |

Only `available` pieces can be used; `banco lesson submit --dry-run` says what is not. Until a piece lands, use the per-card fallback of the card plan.

## Rules of the subject

- English text sits in keys ending `_en` and in `[[en:...]]` spans; the explanations stay Italian. One target language per figure.
- A target-language sentence has at most 12 words; vocabulary beyond the first 3000 words is glossed or listed in `teaches_en`.
- Every dialogue line has its Italian gloss one tap away (`gloss_it`).
- British English by default (en-GB); contractions are accepted on both sides of a typed answer.
- Same meaning, same colour as in Italian: `subject`, `verb`, `object`, `agent`, `time` are the Italian roles.
- Nothing depends on audio: "Ascolta" is optional and its text is always available.

## Public repository

The code and these briefs are public. Lessons live in the database, but anything you write into a file or a report the repository can see is public. No name of the student or of the household, no school, no city, no exam-session details, no programme text beyond the fragments of your refs. Say "the student" and "the teacher".
