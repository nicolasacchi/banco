---
name: lesson-spanish
version: 1
formats: banco.lesson/2
---

# Brief: lessons of spagnolo (`spanish`), an addendum to `lesson`

Read `banco brief show lesson` first: this addendum adds what is particular to the subject, and nothing here changes a number of that brief.
You write one topic of the course for the student, as there. Work only through `banco`, start with `banco status`, and never ask for a decision: the teacher approves
the topic in the browser, you stop at `awaiting_teacher`. Skeleton of the contracts (W2-0): the rules below are the designer's; the track that builds the
pieces completes this brief when they become available, and a type that is not `available` is refused at submit (`E-LESSON-BLOCK`).

## Colour roles

Roles of the subject's palette (`config/banco/lesson_palette.yml`). The carrier says how a role is told apart without colour.

- `verb` (verbo): the same role as `italian.predicate`, same colour, icon and shape.
- `od` (complemento diretto): the same role as `italian.object`, same colour, icon and shape.
- `oi` (complemento indiretto): icon, icon `hand-helping`, shape circle, question "A chi?".
- `stem` (radice): position, shape square.
- `ending` (desinenza): position, shape ring.
- `stress` (sillaba forte): glyph.
- `trap` (trappola dell'italiano): icon, icon `languages`, shape diamond, question "Somiglia all'italiano ma è diverso?".

## Step verbs

The `tag` of a step in a procedure, an example or a solution:

- `stem` (Trova la radice), icon `scissors`.
- `person` (Guarda la persona), icon `users`.
- `change` (Cambia la vocale forte), icon `replace`.
- `ending` (Aggiungi la desinenza), icon `puzzle`.
- `listen` (Ascolta), icon `volume-2`.
- `thing` (Trova la cosa), icon `box`.
- `whom` (Trova a chi), icon `hand-helping`.
- `swap` (Le diventa se), icon `arrow-left-right`.
- `place` (Metti al posto giusto), icon `move-horizontal`.
- `accent` (Metti la tilde), icon `pen-line`.

## Icons

Only these names, besides the structural ones of the lesson brief, and only with a meaning (`E-LESSON-ICON`):

`scissors`, `users`, `replace`, `puzzle`, `volume-2`, `box`, `hand-helping`, `arrow-left-right`, `move-horizontal`, `pen-line`, `message-circle`, `book-a`, `footprints`, `flower`, `gift`, `zap`, `languages`.

## Types of this subject

| Piece | Kind | Status | Batch | Track |
|---|---|---|---|---|
| `sentence` | diagram | available | r1 | T1 |
| `mirror` | diagram | reserved | w2-1 | T3 |
| `word_parts` | diagram | reserved | w2-1 | T3 |
| `paradigm` | diagram | draft | w2-2 | T3 |
| `dialogue` | block | reserved | w2-1 | T3 |
| `tiles` | check | reserved | w2-1 | T1 |
| `listen` | check option | reserved | w2-1 | T2 |

Only `available` pieces can be used; `banco lesson submit --dry-run` says what is not. Until a piece lands, use the per-card fallback of the card plan.

## Rules of the subject

- Spanish text sits in keys ending `_es` and in `[[es:...]]` spans; the explanations stay Italian. One target language per figure.
- A target-language sentence has at most 12 words; the tilde and the stress are computed by our engine, never typed by the agent.
- The forms of verbs come from `spanish/verbs`: irregular forms only from the table.
- Same meaning, same colour as in Italian: `verb` and `od` are the Italian predicate and object.
- Name the traps of Italian where they are (`trap`, the `mirror` notes): a false friend is said once, with its reason.
- Nothing depends on audio: "Ascolta" is optional and its text is always available.

## Public repository

The code and these briefs are public. Lessons live in the database, but anything you write into a file or a report the repository can see is public. No name of the student or of the household, no school, no city, no exam-session details, no programme text beyond the fragments of your refs. Say "the student" and "the teacher".
