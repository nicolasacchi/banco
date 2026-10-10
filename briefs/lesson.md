---
name: lesson
version: 2
formats: banco.lesson/2
---

# Brief: lessons (version 2, `banco.lesson/2`)

You write one topic of the course for one student: a lesson made of short cards, one idea each, with
a picture or a diagram on every idea, small questions to answer on the page, worked examples that
open one step at a time, and a summary with a schema. The student has reading difficulties: every
line you write must be easy to read, and no card is a wall of text. Kinds: `ripasso` (a topic of the
previous year that the current year needs), `ponte` (a prerequisite the previous year did not teach),
`lezione` (content of the current year). A lesson is a Markdown file, `lesson.md`; the server parses
it into the data format `banco.lesson/2` (`config/banco/schemas/lesson.json`) and draws it with its
own templates. You write data and text, never HTML or code: the student's browser shows what our
templates draw from your data. The cover (title, picture, goals, the list of cards, the buttons) is
ours: you do not write it.

Start with `banco status` and this brief. Work only through `banco`. Never ask for a decision: the
teacher approves the topic in the browser, you stop at `awaiting_teacher`. The old format
(`banco.lesson/1`, eight sections) is in `banco brief show lesson-v1`; write new lessons in this one.

## The file

`lesson.md`: UTF-8, LF, at most 96 KB (`E-LESSON-SIZE`). A front matter between two `---` lines
(YAML, no aliases, no custom tags), then parts and cards. Write LaTeX in single quotes in YAML
(`'x = \frac{5}{2}'`) or in block scalars (`|-`).

```markdown
---
schema: banco.lesson/2
key: ripasso.math.demo-equations
kind: ripasso
subject: math
title_it: "Equazioni di primo grado: risolvere e verificare"
goals_it:
  - "**Risolvere** un'equazione di primo grado intera"
  - "**Verificare** il risultato nell'equazione di partenza"
skills: [math.demo-equation]
uses: [math.demo-signed-numbers]
refs:
  - {source: seconda-2025-26, line: 12, fragment: "equazioni di primo grado numeriche", role: needed_by}
  - {source: prima-2025-26, line: 7, fragment: "equazioni di primo grado", role: taught_in}
scope: studied
minutes: 30
calculator: false
why_it: "Molti argomenti di quest'anno finiscono con un'equazione come $ax = b$. Se la sai risolvere, il resto è più semplice."
hero:
  type: balance
  alt_it: "Bilancia in equilibrio: a sinistra due scatole x e un peso da 1, a destra sette pesi da 1."
  left: {x: 2, units: 1}
  right: {units: 7}
  x_value: '3'
---

# Per cominciare

## Un'equazione è una bilancia {idea icon=scale id=bilancia}

I due membri sono i due piatti. Una **soluzione** è il numero che tiene i piatti in equilibrio.

::: diagram balance
alt_it: "Bilancia: a sinistra due scatole x e tre pesi da 1, a destra sette pesi da 1."
left: {x: 2, units: 3}
right: {units: 7}
x_value: '2'
:::
```

A worked lesson is public: the demo `test/fixtures/lesson2/demo.md` (math, 10 core cards and 2 extra)
and `test/fixtures/lesson2/demo-italian.md` (italian). Read them before writing.

Front matter fields:

- `key`, `kind`, `subject`, `skills`, `uses`, `refs`, `scope`, `minutes`, `calculator`: exactly as in
  version 1 (`E-LESSON-PARSE`, `E-SKILL-UNKNOWN`, `E-LESSON-REFS`). The fragment of a ref is an exact
  substring of the imported line: take it from `banco syllabus lines`, never from memory.
- `goals_it`: 1 to 3 lines of at most 12 words, each starting with a verb in bold.
- `why_it`: 2 to 4 sentences (`W-LESSON-WHY`): which later topic this lesson serves, said simply.
  It is shown on the cover under "Vuoi saperne di più?". There is no "why" card.
- `hero` (optional): one diagram, in the same fields as a `diagram` block, drawn large on the cover.
- `book_it` (optional, at most 30 words): what textbooks call the topic. The line "Pagine del libro: le
  indica il docente." is printed by our template. Never a page, chapter or exercise number.
- There is no `finals_it`: the final of an exercise lives in its `try` entry.

## Parts and cards

A level-1 heading (`# Titolo`) at the top level starts a **part** (optional: none, or 2 to 6, each with
at least 2 cards; `E-LESSON-PARTS`). A level-2 heading starts a **card** and ends with a tag in braces:

```
## Titolo della scheda {ROLE [extra] [icon=NAME] [id=SLUG] [tone=ROLE_NAME]}
```

- `ROLE`: `idea`, `example`, `mistakes`, `try` or `summary`. `extra` marks a depth card. `icon=NAME`: one of
  our icons (below); the default comes from the role. `id=SLUG` (`[a-z0-9-]`, at most 32): only when
  another card links to this one. `tone=ROLE_NAME`: a colour role whose colour takes the card's header.
- Each token at most once, the role first. A `## ` line at the top level without a valid tag, text
  before the first card, a `{` or `}` in a title outside `$...$`, a repeated card id: `E-LESSON-CARD`
  with the line. A `## ` or `# ` line inside a directive (for example in a YAML block scalar) is text, never
  a card.
- Core cards: 6 to 14 (`E-LESSON-CARDS`). Order: `idea` and `example` cards in any order, the first `idea`
  before the first `example`, then exactly one `mistakes`, exactly one `try`, exactly one `summary` (the last
  core card). Extra cards (`idea` or `example`, 0 to 4) come after the summary, outside the parts.
- **One idea per card.** The title says the idea as a sentence ("Togli lo stesso peso dai due piatti", not
  "Primo principio"). The core path is complete without `more` blocks and extra cards.
- **A visual on every `idea` card** (`E-CARD-NO-VISUAL`): a `diagram`, a `schema`, a `procedure`, or a `cases`
  block with a diagram in at least one case. A formula, a table, a callout or text is not a visual. When no
  diagram type draws the idea truthfully, fold the idea into an `example` card or draw a `flow`: never draw
  something false. An `example` card needs an `example` block, a `mistakes` card 3 to 8 `mistake` blocks, a
  `try` card one `try` block, the `summary` card one `summary` and one `schema` (`E-LESSON-MAP`).

Limits (`config/banco/validation_rules.yml`, block `lesson2`):

- At most 500 words of core prose (`E-LESSON-WORDS`: text, callouts, summary, mistakes, the `why_it` of
  example steps, card titles; each `$...$` counts as one word), at most 90 words per core card and 40
  per callout (`E-CARD-WORDS`), 1 to 6 blocks per card (`E-CARD-BLOCKS`). Depth (`more` blocks and extra
  cards) at most 1000 words, one `more` at most 150 (`E-LESSON-EXTRA-WORDS`).
- 2 to 8 checks outside the `try` card, step blanks included, at most 3 blanks, at most 2 more in extra
  cards (`E-LESSON-CHECKS`); do not leave 3 idea or example cards in a row without a check
  (`W-LESSON-CHECKS-SPARSE`). On the `try` card at most 3 checks per exercise and 12 in all.
- At most 12 diagrams, schemas and procedures in core (a `cases` counts each diagram in it), 4 in extras, at most
  6 states in one diagram (`E-LESSON-VISUALS`).
- Sentences of at most 25 words, bold spans of at most 4 words, bold at most 8% of the words of the running text (the `text` and `callout` blocks), no banned
  phrase, no page number (`E-READ`, `E-LESSON-BOLD`, `E-PHRASE`, `E-LESSON-PAGE`), Gulpease at least 50
  (`W-GULPEASE`). Address the student as "tu", kindly and neutrally, never "bravo/brava". No italics, no
  ALL-CAPS words (acronyms excepted), no emoji. Decimal comma. The same notation everywhere.
- Phrases never used: exam-gaming ("la risposta che cercano", "cosa scrivere") and self-certification
  ("è tutto verificato"). No personalisation and no data about the student.

## Blocks

Inside a card, plain paragraphs and lists are text (markup below). Everything else is a fenced block:

```
::: TYPE [ARG] ["Title"]
body
:::
```

A blank line is required before and after every fence. The body is markup for `callout` and `summary`, one
LaTeX formula or a YAML `lines:` list for `math`, YAML for every other type. Only `more` nests: it opens with
`:::: more "Title"`, closes with `::::`, and holds text, `callout`, `math`, `diagram`, `schema`, `table`,
`procedure`; never `check`, `try`, `cases` or another `more`. Unknown types, a block of a later release, an
unclosed fence, a YAML error, a body that fails its schema, a line that starts with three backticks:
`E-LESSON-BLOCK` with the line.

YAML traps: a double-quoted scalar that contains a backslash is refused (`"$a \neq 0$"` silently turns `\n` into a
newline): use single quotes or a block scalar. The words `yes`, `no`, `on`, `off`, `true`, `false` are not
text in YAML: write `"sì"`, `"no"` in quotes. Every `_it` value is markup (inline only), except `text_it`
of text, `more` and `try` solutions and the `result_it` of an example, which may hold lists.

Release 1 blocks (the fields are in the schema; `banco lesson submit --dry-run` tells you what is wrong):

| Block | What it is | Fields |
|---|---|---|
| text | paragraphs and lists | markup |
| `callout tip\|warning\|remember\|rule ["Titolo"]` | a box with an icon and a fixed label | markup, 40 words |
| `math` | a formula, large | one LaTeX formula, or `lines: [{tex, note_it?}]` (2 to 4: a chain of transformations; mark what changes with `\role{highlight}{...}`) |
| `procedure ["Titolo"]` | numbered steps, each with its verb | `steps: [{tag, text_it, example_tex?}]` (2 to 6) |
| `cases ["Titolo"]` | 2 to 4 side-by-side cases | `cases: [{title_it, icon?, tone?, condition_it?, text_it, example_it?, diagram?}]` |
| `legend` | colour, icon and label of each role, with the question it answers | `roles: [{role, note_it?, question_it?}]` (2 to 8) |
| `example` | a worked example that opens one step at a time | `problem_it`, `steps: [{tag?, do_it, why_it, blank?}]` (2 to 8, each `do_it` + `why_it` at most 30 words), `result_it?`, `diagram?` (its `states` match the steps one to one) |
| `mistake` | a card to turn: wrong, then right | `group_it?`, `wrong_it`, `right_it`, `why_it`, `code?` (a code of the skill's error catalogue, `W-MISTAKE-CODE`) |
| `check COMPONENT` | a question answered on the page | see Checks |
| `more "Titolo"` | collapsed "Vuoi saperne di più?" | nested blocks, 150 words |
| `summary` | the summary | one list of 3 to 5 points, 20 words each (`E-LESSON-SUMMARY`); put the key word of each point in bold (`**Verifica**`) |
| `schema concept_map\|flow\|table` | the schema a student could copy by hand | see Diagrams |
| `diagram TYPE` | a drawing | see Diagrams |
| `table` | a table, at most 4 columns and 10 rows | `caption_it?`, `header`, `rows` |
| `try` | the exercises, one at a time | `intro_it?`, `exercises: [{text_it, diagram?, check or checks (up to 3, for parts a, b, c), final_it?, solution_it or solution_steps}]` (4 to 8, `E-LESSON-EXERCISES`) |

A step `tag` is one of the verbs of the subject (below). A `try` exercise answered with a `check` is graded by
our code; one without a check keeps a `final_it` (`W-LESSON-FINAL-MISSING` when it has neither;
`W-LESSON-FINAL-IN-TRY` when the exercise text gives the final away). `solution_steps` is a list of tagged
steps `{tag?, do_it, why_it}`; `solution_it` is markup text. The solution is shown only when the student asks.

Not available yet (a later release, `E-LESSON-BLOCK` "not available yet"): `reveal`, `image`, `page`, the
`ordering` and `tiles` checks, the `bar_model` and `fraction_bar` diagrams.

## Checks

`::: check COMPONENT` with `choice`, `number`, `fraction`, `normalized_text`, `matching` or `span_select`. The
fields are those of a practice item of the same component, plus:

- `prompt_it`; `errors: [{answer, code?, message_it}]`: each wrong option should be a typical error of the skills'
  catalogue, with a message that helps; `explain_it`: shown after a right answer or after the second wrong one,
  it teaches (it is not "giusto").
- `number` and `fraction`: the answer is exact, decimal comma (`number`: an integer or `2,5`; a fraction such as `5/2` is a `fraction` answer, the student cannot type it in a `number` box); `input_before` and `input_after` put the box
  inside its formula (`$x =$` then the box). `matching`: with `reuse_right: true` it is a classification (a row per
  item, the categories as chips). `span_select`: the sentence split into `spans: [{id: s1, text_it}]`, the answer
  is a list of span ids.
- The answer is among the options, the answer is not in its own prompt, no error equals the answer
  (`E-LESSON-CHECK`, `W-CHECK-ANSWER-IN-PROMPT`). A check may ask the student to reason on a picture, never to
  copy the answer from it. At least one check after each idea worth checking.
- A step `blank` inside an `example` is a check (`choice`, `number`, `fraction`, `normalized_text`) that hides the
  rest of the example until it is answered: put one faded step in at least one example, and put nothing before
  it that gives it away.
- Right is "Sì.", wrong is "Non ancora." with your hint, both in ink: there is no green, no red, no score. The
  lesson's checks never count for the skill states.

## Diagrams

`::: diagram TYPE` (a drawing) or `::: schema TYPE` (a schema). Every diagram has `alt_it` (5 to 50 words, says
what the picture shows; `E-LESSON-ALT`), `caption_it?`, `size: s|m|l`, and optional `states` (2 to 6, the student
steps through them). **A state overlays the top level, shallowly**: the effective state is the top-level object with
each key present in the state replacing the top-level key of the same name. `op_it` (and `groups`,
`next_label_it`) exist only in states; `alt_it`, `caption_it`, `size` and `x_value` are top level only
(`E-LESSON-DIAGRAM`). A label is plain text or text with `$...$`, at most 6 words (a concept map node 6, an edge
label 3). Numbers are exact strings: `"-3"`, `"2,5"` (comma, never a dot), `"5/2"`; `"-inf"` and `"+inf"` only in
number line intervals.

| Type | For | Fields |
|---|---|---|
| `balance` | the principles of equivalence, **only for equations with natural terms and a positive solution** | `left`, `right`: `{x: boxes (at most 12), units: weights (at most 24)}`; `x_value` (positive; omitted exactly when both plates hold the same number of boxes); `try: {from, to}` (the student puts a number in the box; the range holds the solution); `states` with `op_it` and `groups: n` (both plates divisible by n). The plates are level at `x_value` (with `states`, every state): the drawing cannot lie, so a balance is tilted only when both plates hold the same number of boxes (then there is no `x_value`) |
| `number_line` | signs, inequalities, intervals | `min`, `max`, `step` ((max - min)/step an integer, at most 30), `labels: all\|ends\|marks`, `marks: [{at, label_it?, kind: dot\|open\|closed\|cross, role?}]`, `intervals`, `jumps: [{from, by, label_it?, role?}]` |
| `equation_parts` | the anatomy of an equation | `parts: [{tex, role, label_it?}]` in order (the members and the `=`), `brackets: [{from, to, label_it, role?}]` over whole parts (at most 4) |
| `area_model` | products, the box method | `rows`, `cols` (at most 4), `cells` |
| `cartesian` | lines, systems | `x: [min, max]`, `y: [min, max]`, `grid`, `lines: [{id, eq, label_it?, role?}]` with `eq` as `y = 2x + 1`, `x = 3` or `2x + 3y = 6` (rational coefficients), `points: [{x, y, label_it?, role?, on_lines?: [ids]}]` (a point with `on_lines` lies exactly on each line), `segments` |
| `sentence` | logical and grammatical analysis | `text_it`, `parts: [{id?, text_it, role, label_it?, question_it?, implied?}]` (exact substrings of `text_it`, in order, at most 10; an `implied` part such as "(noi)" is drawn dashed), `links`, `layout: line\|centre`, `states` with `op_it`, `next_label_it` (a part with the same `id` keeps its role) |
| `concept_map` (schema) | classifications | `root`, `nodes: [{id, text_it, role?, icon?}]`, `edges: [{from, to, label_it?}]` forming a tree of depth at most 3 with at most 4 children per node, `links` (at most 3 cross links) |
| `flow` (schema) | procedures | `nodes: [{id, kind: step\|decision\|end, text_it, role?}]`, `edges: [[from, to, "label"?]]`: one main chain, a decision has 2 or 3 branches, no cycles |
| `table` (schema) | summaries | `header`, `rows` (at most 4 columns, 10 rows) |

What a balance cannot draw: negative terms, negative or zero solutions, and subtraction on a plate have no honest
picture on a balance. For signs use a `number_line` (jumps); for equations with negative terms use the `example`
steps and a `flow`; never a balance with the signs dropped.

Choose by subject: math uses `balance` for the principles, `number_line` for signs and inequalities, `area_model` for
products, `cartesian` for lines and systems, `equation_parts` for anatomy; italian uses `sentence` for analysis,
`concept_map` for classifications, `flow` for procedures such as "trova il predicato", `table` in summaries.

## Markup (version 2, lessons)

- Blocks are separated by a blank line; lists `1. ` and `- ` with one nested level (as in version 1).
- Inline: `**bold**`, `$latex$`, `\$` for a literal dollar sign.
- **Colour roles**: `[[role:text]]` in text (for example `[[subject:Il treno]] [[predicate:è arrivato]]`) and
  `\role{unknown}{x}` in a formula. The role must be in the palette of the lesson's subject (`E-LESSON-ROLE`). Use
  the same role for the same thing in text, formulas and diagrams on every card. At most 3 roles whose carrier is an
  icon in the running text of one card (`E-CARD-ROLES`). The legend is ours: a card that uses roles shows one line of
  explanation under its title; add a `legend` block when a card is about the roles.
- **Links**: `[testo](scheda:SLUG)` to a card of the same lesson (the card needs `id=SLUG`), `[testo](argomento:KEY)`
  to a topic of the subject's course map (`E-LESSON-LINK` when it does not exist).
- Refused (`E-LESSON-MARKUP`, with line and construct): headings inside a block, tables, `<` tags, any other link,
  images, `*italic*`, `_italic_`, backticks, `>` quotes, `---`, bare math (any `^`, `_` or backslash outside
  `$...$`), an unclosed `$` or `**`, and in any formula `\htmlClass`, `\htmlId`, `\htmlStyle`, `\htmlData`,
  `\href`, `\url`, `\includegraphics`, `\def`, `\gdef`, `\newcommand`.

## Colour roles, icons and verbs

Roles of the palette (`config/banco/lesson_palette.yml`; the carrier says how a role is told apart without
colour). Every subject also has `highlight` (cambia), `correct` (giusto), `wrong` (non ancora), `muted` (secondario).

- math: `unknown` (incognita), `known` (numero), `left` (primo membro), `right` (secondo membro), `coefficient`
  (coefficiente, with an icon).
- italian: `predicate` (predicato), `subject` (soggetto), `complement` (complemento), `object` (complemento
  oggetto), `time` (tempo), `cause` (causa), `purpose` (fine), `agent` (agente), all with an icon.

Icons (`config/banco/icons.yml`): only these names, and only with a meaning (`E-LESSON-ICON`). For every subject:
`lightbulb`, `pencil-ruler`, `triangle-alert`, `notebook-pen`, `list-checks`, `telescope`, `compass`, `book-open`,
`info`, `circle-help`, `sparkles`, `map`. Math also: `scale`, `weight`, `brackets`, `arrow-left-right`, `sigma`,
`divide`, `check-check`, `eraser`, `x`, `multiply`, `minus`, `equal`, `plus`, `replace`, `minimize-2`, `ruler`,
`chart-line`, `square-function`, `superscript`, `variable`, `calculator`, `layout-grid`, `move-horizontal`,
`infinity`, `triangle`, `percent`, `pi`. Italian also: `zap`, `user`, `puzzle`, `box`, `clock`, `milestone`, `target`,
`user-round`, `map-pin`, `link`, `highlighter`, `repeat`, `git-branch`, `quote`, `pen-line`, `undo-2`,
`message-circle-question`. Do not use an icon only to decorate.

Step verbs (`tag`, with their Italian label and icon, in procedures, example steps and solution steps):

- math: `develop` (Sviluppa), `move` (Sposta), `add` (Somma), `subtract` (Sottrai), `multiply` (Moltiplica),
  `divide` (Dividi), `verify` (Verifica), `cancel` (Elimina), `substitute` (Sostituisci), `simplify` (Semplifica).
- italian: `predicate` (Trova il predicato), `ask` (Chiedi chi? che cosa?), `agree` (Controlla l'accordo), `mark`
  (Segna le parti), `turn` (Gira la frase), `decide` (Decidi).

## Correctness

Every number of examples, checks, exercises and solutions is yours to get right and the reviewer recomputes them
in exact arithmetic. A diagram must say what the text says. A rule of language or science must hold in standard
usage with its common exceptions; every "sempre", "mai", "solo" is checked against a counterexample before you
write it. A fact that depends on the textbook is written neutrally or left out. If a programme line is unclear or
looks like a transcription error, do not guess: report it to the teacher and leave the skill out.

## The cycle

1. `banco lessons list --subject KEY` shows the lessons, their rules version, reviews and send-backs.
2. `banco lesson open KEY` writes `lesson.md` and `.base` into a folder under `$TMPDIR/banco-work/`. For a topic
   whose latest revision is `banco.lesson/1`, `banco lesson open KEY --schema 2` writes a draft in this format,
   converted from it: the content is yours to rewrite into cards, with a visual on every idea. A new lesson has no
   revision yet: start the folder yourself.
3. Edit, then `banco lesson submit DIR --dry-run` until it exits 0, then `banco lesson submit DIR`. An identical
   file replays the latest revision. `E-STALE-BASE` means someone submitted first: open again.
4. After a stored revision, the server draws every card in its own browser and checks it (`lesson status REV`
   shows the result: an exception, a label too long for its diagram, text under the student's size, a card
   wider than a phone). Fix the data, not the checker. `banco lesson shots REV --dir D` downloads the
   screenshots: look at your own cards at 390 pixels wide (a phone) before you ask for a review.
5. A reviewer of another model reads it (`banco lesson-review open|submit`, see that brief). Read the result with
   `banco lesson status REV`. Answer by a new revision that fixes what they say; a new revision needs its own
   review.
6. The lesson belongs to a topic (`banco topic submit`, see the topic brief). The teacher reads the whole topic
   and approves it in the browser.

## Public repository

The code and these briefs are public. Lessons live in the database, but anything you write into a file or a
report the repository can see is public. No name of the student or of the household, no school, no city, no
exam-session details, no programme text beyond the fragments of your refs. Say "the student" and "the teacher".
