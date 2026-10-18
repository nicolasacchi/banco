# Rich lessons, wave 2: the contracts (W2-0)

Wave 2 adds 29 diagram types, five blocks, six check components and their options, a text layer for the languages, "Ascolta", vetted
data tables and ten small domain libraries to the lesson/2 of D-245 to D-259. W2-0 froze the contracts that the builder tracks share,
so that ten tracks can work on different files without agreeing again. This page is the reference of those contracts; the decisions
are D-262 (the amendment of firm rule 3) and D-263 to D-271. Nothing here is lesson content.

## What is available: `config/banco/lesson_types.yml`

The registry lists every diagram type, layout or view, block, check component and check option with a `status`:

| status | meaning | refused at submit |
|---|---|---|
| `available` | the module, the Ruby checks, the vectors and the gallery card exist and passed the look gate | no |
| `reserved`, schema `final` | the JSON schema is frozen (the W2-1 pieces until they are built) | yes |
| `draft` | a W2-2 piece: its schema is a draft (`x-banco-draft`), frozen after its family's first look | yes |
| `reserved`, schema `none` | only the name (W2-3) | yes |

`Lessons::Types` reads the file; `Lessons::Directives.build` refuses a name that is not available with `E-LESSON-BLOCK` ("is not
available yet") and names the layout, view or option that is held back (`flow layout: line`, `check listen`). With `allow_reserved:`
(the reserved dry run, `lesson submit --dry-run --allow-reserved`: the CLI sends `X-Banco-Allow-Reserved: 1`, which the API honours only
with `X-Banco-Dry-Run: 1`) the schema sees it and the parse answers `W-TYPE-RESERVED` or `W-TYPE-DRAFT` per use; such a lesson can never be
stored. A track makes its piece `available` in the commit of
its look gate. `bin/build-lesson-types` generates `lesson/diagrams/registry.js` (the available types imported at once, every other type
behind a lazy loader, `STATUS`, `HOME_PALETTE`, `FAMILY`, `HELD_BACK`), `lesson/checks/registry.js` and `lesson/voices.js`.

## The module contract (`app/javascript/lesson/diagrams/contract.js`)

A diagram type is `app/javascript/lesson/diagrams/FAMILY/TYPE.js` with `layout(data, ctx)` and `describe(data, ctx)` (required, pure,
never throw) and the optional `speechSegments` (not `speech.speak`, which plays segments), `controls`, `targets`, `printed`, `recordAtRender` (only `program`, only in the server's Chrome)
and `layout3d` (W2-3). `ctx.mode` is `student`, `teacher`, `print`, `render` or `select`; `ctx.revealed` is what the student has opened
so far; `describe` and `speechSegments` never read a hidden or not-yet-revealed value (L10). A slider is always drawn with its - and + buttons.
`checkModule` and `checkControls` test a module against the contract. The Scene gains `shapes[].target`, `shapes[].pattern`,
`labels[].lang`, `labels[].tap` and `frames[]`.

The Ruby side (`Lessons::Diagrams::TYPE`, `extend Lessons::Diagrams::Contract`) has the check hooks of D-252 (`static`, `state`,
`across`), `served(data, mode:)`, `targets(data, set)`, `printed(data, state)`, `reachable(data)` and `verify_functions`. The defaults
check nothing, which is what the reserved dry run needs; the rest refuses until the track builds it.

The schema of a type is one `$defs` entry of `config/banco/schemas/diagram.json` with `x-banco-kind`, `x-banco-release`,
`x-banco-draft`, `x-banco-state-keys`, `x-banco-state-only-keys`, `x-banco-solution`, `x-banco-hide`, `x-banco-targets`,
`x-banco-home-palette` and `x-banco-withheld`. The leak annotations are machine-readable: `x-banco-solution` and `x-banco-withheld` are
booleans on a property, `x-banco-hide` a list of paths (`bars[].parts[].hidden`); `test/fixtures/lesson2/whitelist.json` repeats them
(`solution`, `hide`, `withheld`) and `test/content/leak_contract_test.rb` fails when the two drift. `bin/build-diagram-schema` writes the browser's copies: `lesson/diagram_schema.js`
(release 1) and one `lesson/diagram_schemas/TYPE.js` per wave 2 type, which a type module exports as `schema`.

## Shared interfaces (frozen; only the lead changes them)

| Interface | File | Built by |
|---|---|---|
| graph router (`place`, `route`, `flip`, `moveList`) | `lesson/diagrams/graph/router.js` | T4b |
| chart axis (`linear`, `log`, `readCursor`, `legend`, `valueTable`) | `lesson/diagrams/chart/axis.js` | T6 |
| grid API (`grid`, `cellBox`, `outline`, `stackForPhone`, `scrollFrame`, `cellTargets`) | `lesson/diagrams/grid/api.js` (built; the engine and its helpers are in `grid/engine.js`) | T9 |
| speech (`voiceFor`, `rateFor`, `speechOf`, `speak`, `stopAll`; built, D-283) | `lesson/speech.js`, `config/banco/voices.yml` | T2 |
| `recordAtRender(data) -> { records, findings }` | `lesson/diagrams/computing/program.js` | T9 |
| the libraries (Chrono, Dates, NumWords, Money, Chem, Words, Verbs, Bits, ProgramGrammar, Sheet) | `lib/lessons/*.rb`, `lesson/lib/*.js`, `test/fixtures/lesson2/*.json` | T3, T4a, T7, T8, T9 |
| the vetted data tables (15 schemas) | `config/banco/data/*/*.schema.json`, `bin/build-lesson-data`, `Lessons::VettedData` | the tracks |

An unbuilt function throws `NotBuilt` (`lesson/lib/not_built.js`, `Lessons::X::NotBuilt`), so nothing can use an answer that was never computed.

## Palette v2

`config/banco/lesson_palette.yml` (version 2) has the eleven subjects. The CSS variables are scoped by subject
(`--r-SUBJECT-ROLE-(fg|mark|tint)`); the role classes (`.role-x`, `.mk-x`, `.st-x`, `.fl-x`, `.tn-x`, `.card-tone-x`) read generic
`--role-x-*` variables that each `[data-palette="SUBJECT"]` element maps to its own subject's, so the nearest palette decides: the
lesson's root carries its subject, a figure of a type with a home palette (`balance`, `cell`, `formula`, `register`...) carries its
home subject's. A role with `same_as: SUBJECT.ROLE` copies colour, icon and shape (the same meaning looks the same in every subject).
`embeds` names the roles of a home palette that a subject's pages draw; the palette test checks contrast, colour-vision distance and
unique icons and shapes per subject and on every such mix. Role names may use underscores. `bin/build-icons` builds one sprite per
subject (`banco-sprite-SUBJECT.svg`) beside the structural one.

## The rules every piece obeys

The leak rules L1 to L10, accessibility A1 to A10, print P1 to P6 and the validation V1 to V6 of the plan are enforced by the
whitelist (`test/fixtures/lesson2/whitelist.json`, a row per piece, `provisional` for the drafts), the per-type caps
(`lesson2.types` in `config/banco/validation_rules.yml`, rules version 9), the new error codes (registry version 20, one bad fixture
each, described under `pending` in `test/fixtures/lesson2/manifest.json` until the track writes it) and the per-type vectors
(`test/fixtures/diagrams/types/TYPE.json`). Each family has a gallery skeleton (`test/fixtures/lesson2/gallery/FAMILY.md`), a
stylesheet (`app/assets/stylesheets/lesson/FAMILY.css`) and a locale file (`config/locales/lesson_FAMILY.it.yml`). Each subject has
a brief addendum (`banco brief show lesson-SUBJECT`).

## Controls, live line and select scenes (T9, D-275)

`draw.js` builds the controls a module declares through `controls(data)` (`lesson/diagrams/controls.js`). The values are one object `{ id: value }` that
`layout` and `describe` read as `ctx.controls` (empty at the start, reset when the figure changes state): a toggle is `true` once flipped, a stepper is a number
(its `initial` until it is pressed). Beyond the contract's `{ id, kind, range?, values?, label_it }` a control may carry `initial`, `less_it` and `more_it` (the words on
a stepper's two buttons). A toggle or tap that the scene gives a box to (`scene.controls[id] = { x, y, w, h, label_it, on }`) is a native button laid over the drawing
(`role=switch`), the others sit in the strip under it. `scene.live` is the one polite sentence announced after a change. In `mode: "select"` a type draws its
candidates in one neutral style with `shapes[].target = "tN"` and returns `scene.targets = [{ target, bbox }]`; `targets(data, set, opts)` maps them to the stored ids.
`describe(data, ctx)` and `printed(data, state)` take the state: `printed` is the set of value tokens (digits in every way they are written, weights, readouts, sums), and every
number `describe` says is one of them or a structural count. A page links `stylesheets/lesson/FAMILY.css` for the families its diagrams use (`lesson_family_stylesheets`).
## The docs family (T8, D-278)

`document` (`kind: invoice`, views `sheet` and `cascade`), `source` (`kind: legal`), `reveal` and `oral` are `available`; their texts are
`config/locales/lesson_docs.it.yml` (`t.docs`) and their look `app/assets/stylesheets/lesson/docs.css`, linked by `lesson_family_stylesheets` only
for a lesson that uses one of them. `Lessons::Money` computes every amount of an invoice; the figure never reads a hidden row. The turning of a flip
card is `lesson/blocks/flip.js`, shared by `mistake` and `reveal`. An `oral` is graded as an ordering by the check endpoint and its model answer rides
on the reply (`model_it`). The gallery lesson is `test/fixtures/lesson2/gallery/docs-lesson.md`, rendered by `test/system/docs_family_test.rb`.

## The biology figures (T7, T4b, D-312)

`cell` and `nested` are the first W2-2 types made `available`: their look gate froze their draft schemas (`x-banco-draft` is gone; the registry test
accepts a W2-2 type once that happens). `cell` reads the vetted table `bio/cell_parts` (kinds, parts, names, jobs, colours; `lesson/data/bio-cell_parts.js`
in the browser): each kind is a fixed drawing in fractions of its width, each part has a fixed zone (tap target, number, leader end) far from the others,
`labels: all` puts the names in two columns or, when they do not fit, a number on each part and one key for the figure; the select figure is a neutral
line drawing with one zone per part (`c1.nucleoid`), and no part name reaches its DOM (the page's measuring probe is never handed a name); there the
wall's band stands a few px out from the membrane and their two targets keep each to its own band. With `labels: all` or `tap` every shape of a part
(and an invisible pad along a thin one) forwards its tap to the part's button (`shapes[].hitFor`, wired by `draw.js` for any type's `hits`). Its
colours are repeated in `lesson/science.css` and held equal to the table by `test/lib/cell_parts_data_test.rb`. `true_scale` is a draft view until
`bio/sizes` exists, and `scale` stays a draft for the same reason. `nested` draws "is made of" as boxes inside boxes, the same picture at every width;
its select figure reaches the page with positional ids and one neutral label on every level (`Nested.served`), so the source names no candidate either.
The gallery is `test/fixtures/lesson2/gallery/science-biology.md` (`nested` also has a card in `graph.md`).

## The text layer and "Ascolta" (T2, D-282, D-283)

**Spans** (`Lessons::Markup`, `items/markup_parser.js`, the shared cases `test/fixtures/markup/v2.json`): `[[en:..]]`, `[[es:..]]`, `[[la:..]]` (plain words of another
language; only in a subject that teaches it, `lesson2.target_languages`), `[[code:..]]` (literal, at most 40 characters), `[[g:term]]` (a word of the front matter
`glossary`) and `[[role|it:..]]` (in an english or spanish lesson a role span is target-language text unless it says `|it`). The names `en es it la code g` are never roles.
A key that holds words of a language ends in its code (`text_en`, `form_es`); `Lessons::Lang.keyed` finds them in any block and `Lesson2Checks` applies `E-LESSON-LANG` (the
subject does not teach it, Italian words in it, two languages in one figure), the target-language set (`E-READ`, 12 words a sentence) and `W-LANG-LEVEL` (words outside the
first 3000 of `config/banco/lexicon/{en,es}.txt`, the glossary and `teaches_en` / `teaches_es`). The Italian lint reads a text without its spans. The cloze cue after a gap
(`When I ___ (get) home`) is not an answer in the prompt. `\ce{}` and `\pu{}` (mhchem, chemistry and biology only) are checked by `Lessons::ChemSymbols` (`E-CHEM-SYMBOL`).

**Speech.** `lesson/speech.js` (the contract: gate, walker, player), `speech_state.js`, `speech_device.js`, `speech_ui.js`, `speech_math.js`. `speechOf(card)` reads the rendered card
and nothing that is not visible (a figure answers with `figure.speechSegments()`, which `draw.js` takes from the type's `speechSegments(data, ctx)` or from `describe` of the state
shown now; a type that reads differently from its description, such as `sentence`, exports `speechSegments`). A language with no accepted voice is skipped, and with no accepted
voice at all no speaker is shown: `config/banco/voices.yml` stays empty until the operator has used "Prova le voci" (`/settings#voci`) on the student's own Mac or iPad. The listen
check option (`lesson/checks/listen.js`) sends `text_shown` when the text was looked at. `test/fixtures/lesson2/speech/*.json` hold what is read for the family galleries and the text
lesson; `GOLDEN=1 bin/rails test test/system/lesson_speech_golden_test.rb` writes them again. A piece that wants a speaker (a dialogue line, a `word_parts` word, a `paradigm` cell,
a timeline tense mark, the `oral` model) uses `speakerButton(ctx, { lang, text, node })` of `speech_ui.js` or `ctx.speaker(lang)`.
