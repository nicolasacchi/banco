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

Not available yet (`E-LESSON-BLOCK`, "not available yet"): any block, diagram type, layout, view, check component
or check option that the registry `config/banco/lesson_types.yml` does not list as `available`. The subjects other
than math and italian have an addendum with their roles, verbs, icons and pieces: `banco brief show lesson-SUBJECT`
(for example `lesson-biology`; the subject key with hyphens).

## The docs family: `document`, `source`, `reveal`, `oral`

Four pieces for documents, texts to read and answers to rehearse. They are `available` as far as the table says; the draft kinds are refused
(`banco lesson submit --dry-run --allow-reserved` checks them against their draft schema).

**`diagram document`, `kind: invoice`** (`view: sheet` the invoice as a document, `view: cascade` the rows as a waterfall). You give the goods, the
discounts and the costs; **our code computes every row** (the amounts are `Lessons::Money`, in exact euros, VAT rounded half up to the cent) and draws
them. Never write a total.

```yaml
::: diagram document
alt_it: "Fattura di Cartoleria Alfa a Studio Beta: 800 quaderni a 2,50 euro, sconto del 10%, spese del venditore 60,00 euro, IVA 22%, totale 2.319,20 euro."
kind: invoice
view: sheet                        # sheet | cascade (default sheet)
head: {seller_it: "Cartoleria Alfa srl", buyer_it: "Studio Beta", number: '41', date: '2026-10-12'}
lines:                             # 1 to 6: quantity times price; vat is 22, 10, 5 or 4
  - {text_it: "Quaderni A4", qty: '800', price: '2,50', vat: '22'}
discounts: ['10']                  # successive percentages, each on what is left (at most 4)
costs:                             # at most 4: documented false = the seller's own cost, inside the imponibile; true = advanced for the buyer, outside
  - {text_it: "Imballaggio", amount: '60,00', documented: false}
  - {text_it: "Corriere pagato per il cliente", amount: '50,00', documented: true}
interest: {rate: '6', days: 60, year: 360}   # optional: on the net goods, added after the documented costs
rows: [gross, discounts, net, costs_in, base, vat, costs_out, interest, total]   # optional subset; the order is ours
hide: [base, total]                # rows drawn as an empty box with "?" (a sheet only; a cascade cannot hide a row)
mark: [base]                       # the dashed fence around net, the seller's costs and the imponibile; another row id is outlined
error: documented_costs_taxed      # draw the invoice as that typical error computes it (see below)
states: [{rows: [gross], op_it: "Il lordo."}, {rows: [gross, discounts, net], op_it: "Togli lo sconto."}]   # rows, hide and mark per state
:::
```

- `error` is one of: `taxable_base_on_gross`, `vat_on_gross_added_to_net`, `documented_costs_taxed`, `undocumented_costs_untaxed`,
  `undocumented_costs_omitted`, `successive_discounts_added`, `two_rates_single_rate`, `two_rates_combined`, `vat_added_as_amount`. The error must
  change the total of this invoice (`E-LESSON-DIAGRAM`). The drawing is then titled "Fattura con un errore".
- Two VAT rates: every cost must be `documented: true` (an own cost has no rate).
- Every euro amount written in `alt_it` or `caption_it` must be an amount the figure computes or you wrote in the data (a price, a cost), and never the
  amount of a hidden row (`E-LESSON-ALT`). Invented names only.
- The amounts a check asks come from the same code: ask the value, never copy it from a drawing the student can read. `verify: {fn: money.row, args:
  {qty: '800', price: '2,50'}}` recomputes a line when `verify` is available.

**`source`, `kind: legal`**: the words of a law with the plain version first. The quotation is an exact substring of the imported reference text
(`ref`, `banco references list`; `E-QUOTE-REF`), never from memory.

```yaml
::: source
kind: legal
title_it: "Costituzione, art. 74"
ref: costituzione-artt-55-96          # an imported reference text
open: plain                           # plain (default) | original: which text the switch shows first
parts:                                # 1 to 4 commi, at most 60 words each
  - text_it: "Il Presidente della Repubblica, prima di promulgare la legge, può con messaggio motivato alle Camere chiedere una nuova deliberazione."
    plain_it: "Prima di firmare la legge, il Presidente può rimandarla alle Camere. Deve spiegare perché."   # required on a core card
    marks: [{text_it: "Presidente della Repubblica", role: guarantee}]   # exact words of text_it, a role of the subject
guide: [{span_it: "con messaggio motivato", note_it: "Deve scrivere il motivo."}]   # "Leggi con me": exact spans of a part
:::
```

The student sees "In parole semplici" first and the switch "Testo della legge"; both are printed. A source counts as a visual, one per card, at most 3
cards whose only visual is a source; the plain versions count in the 250 words open by default and the quotations behind the switch in the 240 words
of originals (`E-LESSON-APPARATUS-WORDS`). The other kinds (`written`, `iconographic`, `material`) are W2-2.

**`reveal`**: think first, then turn. Ungraded, nothing is stored.

```yaml
::: reveal
prompt_it: "Pensaci: perché il Senato non riforma?"     # the front
answer_it: "..."                                         # the back, at most 40 words
:::
::: reveal
who_it: "Sei il venditore"
year: '-27'                                              # optional
situation_it: "Hai spedito la merce. Il cliente non paga da due mesi. Che cosa fai?"   # replaces prompt_it
options:                                                 # 2 to 4, exactly one real
  - {id: a, text_it: "Aspetto ancora", then_it: "Il tempo passa."}    # then_it at most 25 words
  - {id: b, text_it: "Gli scrivo", then_it: "Resta una prova scritta.", real: true}
real_it: "Di solito si manda prima un sollecito scritto."   # replaces answer_it, at most 40 words
:::
```

With options the card is a crossroads: S picks a road, sees what comes of it, then turns to what really happened; the real road is marked in words. Our
line "Le altre strade sono ipotesi: nessuno sa come sarebbe andata." is always added: never ask what would have happened. A reveal with options counts as
a visual, one per card; a plain one does not.

**`oral`**: rehearse an answer for the oral exam. S puts the outline in order (graded like an ordering) and then reads the model answer.

```yaml
::: oral
question_it: "Spiega come si arriva dal lordo al totale di una fattura."
outline: [{id: o1, text_it: "Parto dal lordo"}, {id: o2, text_it: "Tolgo gli sconti"}, {id: o3, text_it: "Calcolo l'IVA"}]   # 3 to 7
answer: [o1, o2, o3]                  # every outline id once, in order
errors: [{answer: [o2, o1, o3], code: business_discounts_added, message_it: "Prima il lordo."}]   # other orders
connectives: ["prima", "poi", "infine"]
terms: ["lordo", "netto"]
model_it: "Parto dal lordo. Poi tolgo gli sconti. Infine calcolo l'IVA."   # at most 120 words, shown only after the outline is right or the second try
:::
```

Nothing is recorded: our fixed line on the card says it is optional and that no one listens. One oral per card; it counts as a visual.

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
| `network` | who is linked to whom, by what | `layout: pair\|row\|triangle\|hub\|fan\|grid`, `centre` (hub), `into` (fan), `nodes: [{id, label_it, icon?, role?, note_it?, badge_it?}]` (2 to 8, label 6 words, note 25), `edges: [{from, to, kind, label_it?, what?}]` (at most 12 per state; `kind`: owes, pays, elects, trusts, appoints, commands, advises, votes_laws, vetoes, orders, promises, gives, sends; `what`: goods, money, document, order, promise, signature, information, vote), `holds: [{node, items_it}]`, `everyone: true` (a node "Tutti gli altri", id `everyone`), `filter: true` (hub: kind chips), states with `edges`, `holds`, `hide: [ids]`, `badges`, `op_it`. An arrow never reaches a hidden node |
| `chain` | causes, effects, cycles | `layout: line\|fan\|ring`, `nodes: [{id, kind: cause\|event\|effect\|stage, area?, text_it}]` (3 to 10, 8 words) written in reading order (a fan: the causes, the one event, its effects), `links: [{from, to, word?, causal?: false, back?: true}]` (a link goes to the next node, or into the event of a fan; word: perché, quindi, per questo, porta a, poi; at most 2 not causal, 1 back, a line only), `remove: true` ("Togli una causa"), states with `show: [ids]`, `op_it`; a ring has stages only |
| `flow` `layout: line` | a journey with stations and a token | `nodes` (the stations in order, at most 8, label 4 words, `actor_it?`, no `edges`), `branch: {from, to, label_it?, nodes}` (one second lane, at most 4), `returns: [{from, to, label_it?}]` (at most 3, backwards along their lane), `token`, states with `token`, `via` (the stations the token passes, along drawn edges or returns), `op_it` |
| `table` (schema) | summaries | `header`, `rows` (at most 4 columns, 10 rows) |
| `register` | computer science: the digits of an n-bit register with weights, a computed readout, bit switches and goals (`view: row`), or all the codes of 3 or 4 bits on a circle (`view: ring`) | `view`, `width`, `value`, `base`, `read`, `weights`, `groups`, `toggle`, `states`...: see `banco brief show lesson-computer-science` |
| `column_calc` | computer science: an addition, subtraction or multiplication in columns inside a register; carries, borrows and partial products are computed | `op`, `a`, `b`, `width`, `base`, `reveal`, `read`: see `banco brief show lesson-computer-science` |
| `map` | where things are: continents, countries, regions of Italy, the ancient Mediterranean | `base` (`world`, `europe`, `africa`, `asia`, `north_america`, `south_america`, `oceania`, `arctic`, `antarctic`, `italy`, `mediterraneo_antico`), `detail`, `graticule`, `highlight: [{id, role?, pattern?}]` (ids of the gazetteer, never names, never coordinates on the ancient base), `bands`, `places: [{id}]`, `points`, `lines`, `routes: [{via: [ids], role?, label_it?}]`, `slider` with `regions_since` (ancient base), `candidates`, `states`. Not yet: `arrows`, `compare`, `inset`, a circle `value` |
| `insolation` | why the same light warms less far from the equator | `latitudes` (at most 4), `subsolar` (`'23,4'`, `'-23,4'`), `stepper`, `spread`, `states`; the spread 1/cos is computed and printed |
| `cross_section` | altitude and climate, a river's profile | `x: {to, unit}`, `points: [[x, altitude in m]]`, `features`, `belts: [{from_alt, to_alt, label_it, role?}]`, `lapse: {base_temp, per_km}`, `stepper`; the exaggeration is computed and printed |
| `climograph` | climate: rain as bars, temperature as a line, the arid months | `station: geo/stations.ID` (a vetted station: its Italian name, numbers and source come from the table, `E-LESSON-DATA` for an id that is not there) or `place_it`, `lat?`, `alt_m?`, `temp` and `precip` (12 numbers each, `source_it`); `show: [bars, line, arid, range, total]` (`arid` needs bars and line, `range` needs the line, `total` needs the bars; the default is bars and line), `compare: {station or temp, place_it}` (a second, dashed temperature line), `read: true` (a month stepper), `states` with `show: [...]` and `op_it`: add the layers in order, so one scale is on screen at a time. The arid months (P <= 2T), the total, the range and the extremes are computed by us: never write them. A check never asks a number the figure prints or the stepper reads (`W-CHECK-ANSWER-IN-DIAGRAM`, `E-CHECK-ANSWER-BY-SIMULATION`); a figure in a `try` exercise has no `read` |
| `bar_model` | the parts of a whole, percentages | `view: parts` (`bars: [{label_it, parts: [{value, label_it, role?, hidden?}]}]`, at most 4 bars of 8 parts; `total: {value, label_it?}`, every bar adds up to it; a `hidden` part is the blank, one per bar, and needs the total) or `view: percent` (exactly one of `base`, the value of 100 %, and `anchor: {pct, value}`, one known point; `unit: euro\|none`; `marks: [{pct, label_it, role?}]` at most 6 between 0 and 300; `hide: [pct]`, the marks whose value is a blank; `chain: [{pct}]`, at most 3 successive percentages, each on a new line). Every value is computed exactly |
| `seats` | the quorum and the majorities of an assembly | `layout: hemicycle\|grid`, `seats` (at most 1000, a grid 200), `groups: [{id?, label_it, seats, role?}]` (never real parties), `present`, `yes` (everyone present votes yes or no), `thresholds: [legal_number, present_majority, absolute_majority, two_thirds, three_fifths]` (integers: a tie is not a majority), `try: {present: [lo, hi], yes: [lo, hi]}` (two sliders; the readout of every value inside the ranges is reachable, so a check there asks another number or says in `reachable_ok_it` why not) |
| `word_parts` | words in pieces: what each piece means (`view: decode`), or the syllables and where the voice falls (`view: syllables`) | `view`, `words: [{form_it\|form_en\|form_es\|form_la: 'p[ue]d\|o', parts_it?, meaning_it?, syllables?, stress?, label_it?}]` (1 to 4 words, 16 letters, 4 pieces; `\|` between pieces, `[..]` letters that change, `+` an attached piece; one language beside Italian), `arrows: [{from, to: from + 1, label_it?}]`, states with `words`, `op_it`. Spanish syllables, stress and the tilde rule are computed, never written (a tilde that breaks the rule is refused); for English, Latin and Italian write `syllables: 'hap-py'` and `stress: 1`. A select check can ask `targets: pieces` or `syllables` (ids `w1p2`, `w1s3`); see `lesson-spanish`, `lesson-english`, `lesson-biology` |
| `mirror` | the Italian over another language, piece by piece | `rows: [{pieces_it, pieces_es\|pieces_en, links: [[it, other, same\|shift\|false_friend]], notes: [{side, piece, note_it}], roles?}]` (1 to 3 rows, 12 words a side; `'Glie+lo'` is one word written joined), `same_ok`. A `shift`, a `false_friend` and a piece with no link need a note of at most 12 words; select ids `r1i2`, `r1t3`; see `lesson-spanish`, `lesson-english` |

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
- **Words of another language** (D-281): `[[en:When I arrive, I will call you.]]`, `[[es:...]]` (and `[[la:...]]`) in any `_it` text, only in a
  subject that teaches that language (`E-LESSON-LANG`: english `en`, spanish `es`; `la` in italian, history, law_economics, biology). Plain words, no markup
  inside; the Italian lint skips them and a target-language sentence has at most 12 words (`E-READ`). Words beyond the first 3000 of the language, the
  lesson's glossary and `teaches_en` / `teaches_es` are `W-LANG-LEVEL`. In an english or spanish lesson a colour role span is target-language text
  (`[[time:when I arrive]]`); an Italian one says `[[time|it:momento]]`. A key holding such words ends in the language: `text_en`, `form_es`.
  A cloze keeps its cue, `When I ___ (get) home`, without a warning.
- **Code**: `[[code:soldi = soldi + 8]]`, at most 40 characters, literal (`<`, `>`, `=`, `"`, `;`, `$` allowed; `]]` cannot be typed), in the body font.
- **Glossary** (front matter `glossary: [{term_it, def_it, example_it?}]`, at most 12, short Italian): `[[g:promulgazione]]` in a text gives the word
  with a small book icon that opens the definition; the card lists its words under it ("Parole di questa scheda", counted in the 250 apparatus words).
- **Chemistry** (chemistry and biology only): `$\ce{2H2 + O2 -> 2H2O}$` and `$\pu{25 kJ/mol}$`; every symbol in `\ce{}` or `\mathrm{}` is an element symbol,
  case-exact (`E-CHEM-SYMBOL`).
- **Ascolta**: the card has a button that reads it aloud with the device's voice (only voices the operator accepted); nothing in the lesson may depend on
  it. A check can be heard: `listen: {text_en: "I will call you when I get home."}` on a `choice`, `matching` or `span_select` (the text stays behind
  "Mostra il testo").
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
