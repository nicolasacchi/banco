# Rich lessons, wave 2: the contracts (W2-0)

Wave 2 adds 29 diagram types, five blocks, six check components and their options, a text layer for the languages, "Ascolta", vetted
data tables and ten small domain libraries to the lesson/2 of D-245 to D-259. W2-0 froze the contracts that the builder tracks share,
so that ten tracks can work on different files without agreeing again. This page is the reference of those contracts; the decisions
are D-261 (the amendment of firm rule 3) and D-262 to D-270. Nothing here is lesson content.

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
(the reserved dry run, `lesson submit --dry-run --allow-reserved`, built by T1) the schema sees it and the caller answers
`W-TYPE-RESERVED` or `W-TYPE-DRAFT` per use; such a lesson can never be stored. A track makes its piece `available` in the commit of
its look gate. `bin/build-lesson-types` generates `lesson/diagrams/registry.js` (the available types imported at once, every other type
behind a lazy loader, `STATUS`, `HOME_PALETTE`, `FAMILY`, `HELD_BACK`), `lesson/checks/registry.js` and `lesson/voices.js`.

## The module contract (`app/javascript/lesson/diagrams/contract.js`)

A diagram type is `app/javascript/lesson/diagrams/FAMILY/TYPE.js` with `layout(data, ctx)` and `describe(data, ctx)` (required, pure,
never throw) and the optional `speak`, `controls`, `targets`, `printed`, `recordAtRender` (only `program`, only in the server's Chrome)
and `layout3d` (W2-3). `ctx.mode` is `student`, `teacher`, `print`, `render` or `select`; `ctx.revealed` is what the student has opened
so far; `describe` and `speak` never read a hidden or not-yet-revealed value (L10). A slider is always drawn with its - and + buttons.
`checkModule` and `checkControls` test a module against the contract. The Scene gains `shapes[].target`, `shapes[].pattern`,
`labels[].lang`, `labels[].tap` and `frames[]`.

The Ruby side (`Lessons::Diagrams::TYPE`, `extend Lessons::Diagrams::Contract`) has the check hooks of D-252 (`static`, `state`,
`across`), `served(data, mode:)`, `targets(data, set)`, `printed(data, state)`, `reachable(data)` and `verify_functions`. The defaults
check nothing, which is what the reserved dry run needs; the rest refuses until the track builds it.

The schema of a type is one `$defs` entry of `config/banco/schemas/diagram.json` with `x-banco-kind`, `x-banco-release`,
`x-banco-draft`, `x-banco-state-keys`, `x-banco-state-only-keys`, `x-banco-solution`, `x-banco-hide`, `x-banco-targets`,
`x-banco-home-palette` and `x-banco-withheld`. `bin/build-diagram-schema` writes the browser's copies: `lesson/diagram_schema.js`
(release 1) and one `lesson/diagram_schemas/TYPE.js` per wave 2 type, which a type module exports as `schema`.

## Shared interfaces (frozen; only the lead changes them)

| Interface | File | Built by |
|---|---|---|
| graph router (`place`, `route`, `flip`, `moveList`) | `lesson/diagrams/graph/router.js` | T4b |
| chart axis (`linear`, `log`, `readCursor`, `legend`, `valueTable`) | `lesson/diagrams/chart/axis.js` | T6 |
| grid API (`grid`, `cellBox`, `outline`, `stackForPhone`, `scrollFrame`, `cellTargets`) | `lesson/diagrams/grid/api.js` | T9 |
| speech (`voiceFor`, `rateFor` done; `speechOf`, `speak`, `stopAll`) | `lesson/speech.js`, `config/banco/voices.yml` | T2 |
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
