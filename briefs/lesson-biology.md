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
| `cell` | diagram | available (`true_scale` is a draft) | w2-2 | T7 |
| `word_parts` | diagram | available | w2-1 | T3 |
| `scale` | diagram | draft | w2-2 | T6 |
| `nested` | diagram | available | w2-2 | T4b |
| `bar_model` | diagram | available | w2-1 | T6 |
| `select` | check | available | w2-1 | T1 |

Only `available` pieces can be used; `banco lesson submit --dry-run` says what is not. Until a piece lands, use the per-card fallback of the card plan.
`scale` waits for the vetted sizes (`bio/sizes`): until then a size is a sentence ("circa 50 micrometri", from the vetted reference) or a `bar_model`.

## Rules of the subject

- Sizes and percentages are always "circa" and come from the vetted reference (`bio/sizes`), never from memory.
- Schematic drawings only through `cell` and `strand`: never a hand-made picture of a cell.
- At most three new technical words per card, each in bold the first time and decoded with `word_parts` or one plain sentence.
- A mnemonic shape (the pentagon of the sugar, the tabs of the bases) is said to be a mnemonic: "le forme aiutano a ricordare".
- At most one `more` for the exceptions (the red blood cell, root cells).
- The pair colours (`pair_at`, `pair_cg`) are a rule of pairing, not the identity of a base: the letter says the base.

## The `word_parts` figure

Available now, `view: decode`: `form_it: 'eu|cariote'`, `parts_it: ["vero, bene", "nucleo"]`, `meaning_it: "con un vero nucleo"`. `|` is the line between pieces (at most 4 pieces, 16
letters). One short Italian meaning for each piece; only an etymology a dictionary gives. For a Latin or Greek root written in Latin letters use `form_la`.

## The `cell` figure

Available now. One or two cells, side by side (one above the other on a phone), drawn by our code: the same shapes, places and colours in every lesson, so
the cell becomes a map the student learns once. You choose the kinds and the parts; you never draw a cell and never write a part's name or job.

```yaml
::: diagram cell
alt_it: "A sinistra un batterio, a destra una cellula della guancia. Tutte e due hanno membrana, citoplasma, DNA e ribosomi."
labels: all            # all: every part named (two columns, or numbers and one key on a phone); tap: named when tapped; none: nothing named
cells:
  - {kind: bacterium, label_it: "Batterio", parts: [membrane, cytoplasm, nucleoid, ribosomes, wall]}
  - {kind: animal, label_it: "Cellula della guancia", parts: [membrane, cytoplasm, nucleus, ribosomes, mitochondria]}
notes: [{part: nucleoid, text_it: "Il DNA sta nel citoplasma: intorno non c'è un nucleo."}]   # read on a tap, instead of the part's job
states:
  - {op_it: "Le due cellule"}
  - {op_it: "Le quattro parti di tutte e due", highlight: [membrane, cytoplasm, dna, ribosomes]}
:::
```

- **Kinds and their parts** (the vetted table `bio/cell_parts`; the names and jobs the student reads come from it):
  `bacterium`: `wall`, `membrane`, `cytoplasm`, `nucleoid`, `ribosomes`, `flagellum`.
  `animal`: `membrane`, `cytoplasm`, `nucleus`, `ribosomes`, `mitochondria`, `er`, `golgi`, `vesicles`.
  `plant`: `wall`, `membrane`, `cytoplasm`, `nucleus`, `ribosomes`, `mitochondria`, `chloroplasts`, `vacuole`, `er`, `golgi`, `vesicles`.
  A part the kind does not have is refused (`E-LESSON-DIAGRAM`): a bacterium with a nucleus or mitochondria, an animal cell with a wall, chloroplasts or
  the large vacuole, a nucleoid in a eukaryotic cell. Every cell lists `membrane`, `cytoplasm`, `ribosomes` and its DNA (`nucleoid` or `nucleus`).
  Leave out what the card does not need (a bacterium without `flagellum`), never a shared part.
- **`dna`** is never listed: `highlight`, `paths` and `notes` may name it, and it lights the nucleoid of a bacterium or the threads inside a nucleus (a
  eukaryotic cell then gets a label "DNA" inside its nucleus, in every state).
- **`highlight`** lights parts (a halo, a thicker outline, the rest dimmed). **`paths`** are arrows between two parts of one cell, at most 3 per state,
  label at most 6 words ("copia di RNA"). **`fill: {vacuole: low|mid|high}`** is the water of a plant cell: `low` shrinks the vacuole and pulls the
  membrane away from the wall.
- Two cells with different parts get a button **"Solo le differenze"** (it lights what one cell has and the other has not); a figure with `labels: none`, a select check's included, has none.
- **`label_it`** of a cell is what the description and the screen reader say for it; without one they say its kind ("una cellula animale"). To
  ask which kind a cell is (an `example` with a linked `cell` whose blank asks "E la seconda cellula?"), label it "Seconda cellula" and let the
  `alt_it` say what is seen ("solo un bordo sottile"), not the kind. An example's linked `cell` has one state per step; the state of a blank's
  step shows once the blank is answered.
- **A select check** asks `targets: parts`; the ids are `c1.nucleoid`, `c2.wall` (cell 1 or 2, then the part). Its figure has `labels: none`, is drawn as a
  line drawing in one style, and its `alt_it` never names an answer (`E-CHECK-ANSWER-IN-ALT`): "un bordo doppio, dentro tanti puntini e un groviglio di filo".
- Not yet: `true_scale` (the real size ratio waits for the vetted sizes `bio/sizes`), the red blood cell (`kind: red_blood`, `omit_shared`): say them in
  a sentence or a `more`.

## The `nested` figure

Available now. "È fatto di": boxes inside boxes, the outermost the whole figure, each with its name and, beside or under it, an example.

```yaml
::: diagram nested
alt_it: "Cinque riquadri uno dentro l'altro: cellula, tessuto, organo, apparato, organismo. Dentro la cellula, tratteggiati, gli organuli."
levels:                # from the inside out, 3 to 6; ids unique, names at most 6 words and all different
  - {id: cell, label_it: "cellula", example_it: "cellula muscolare del cuore"}
  - {id: tissue, label_it: "tessuto", example_it: "tessuto muscolare del cuore"}
  - {id: organ, label_it: "organo", example_it: "cuore"}
  - {id: system, label_it: "apparato", example_it: "apparato circolatorio"}
  - {id: organism, label_it: "organismo", example_it: "corpo umano"}
inside: {label_it: "organuli", note_it: "stanno dentro la cellula: non sono un livello del corpo"}
states: [{focus: cell, op_it: "Una cellula"}, {focus: tissue, op_it: "Tante cellule simili"}]
:::
```

A select check asks `targets: levels` (ids are the level ids, `answer: ['organ']`): its figure shows the examples without the names. So ask for a level
by its name ("Tocca il riquadro dell'organo": the student must know that the brain is an organ), or by an example the figure does not show (the boxes
show the heart, the stem asks "Il fegato: tocca il suo livello"). Never quote in the stem the example printed in the answer's box: "Il cervello: tocca
il suo livello" over a box that says "il cervello" tests the reading, not the level (no finding catches it: the reviewer does). Use `nested` for "is made
of", a `concept_map` for "is a kind of", a `flow` for "then".

## Public repository

The code and these briefs are public. Lessons live in the database, but anything you write into a file or a report the repository can see is public. No name of the student or of the household, no school, no city, no exam-session details, no programme text beyond the fragments of your refs. Say "the student" and "the teacher".
