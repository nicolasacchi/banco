# banco: agent guide

banco is a study app for one private-candidate student preparing an Italian
upper-secondary exam. Rails 8.1 app with a deterministic engine (no LLM in the
student's path) plus a Go CLI (`banco`) that the teacher's AI agent uses.
Phase 1a: the entry diagnosis.

## Firm rules (change only after talking to the operator)

1. The student talks only to the software: no chat and no model in the student's path.
2. Decisions are taken by the teacher in the browser (web listener only). No
   `/api/v1` route creates a decision; the CLI has no decision command. Exception:
   minor review findings, which the third reviewer's first opinion may close
   (a derived state, never a decision row): D-222, D-239. Exception: the operator may
   record a teacher decision from the host console (`bin/rails banco:decide`), never
   over HTTP: D-260.
3. Agent-written code runs only in browsers: the server's Chrome at validation and
   the render check, and approved free pages in the student's and the teacher's
   browsers, in a sandboxed frame on `pages.banco.scc.im` (D-262). Rails and the
   grader worker never execute it. The teacher's approval of a free page covers
   what it shows and teaches, not its code.
4. The ledger is append-only: triggers block UPDATE and DELETE on every primary
   table except `schema_migrations` and `ar_internal_metadata`. Corrections are
   new rows; states are derived.
5. The course lives in Rails as immutable revisions; code, rules, thresholds and
   agent briefs live in git.
6. Commands, options, names, keys, routes and hosts are English; texts for the
   student and the teacher are Italian. Keys holding Italian text end in `_it`.

## Content agents

Use only `banco`. Start with `banco status` and `banco brief show`. Never open
the database or the data directory. Never authenticate as the teacher. Never
ask for decisions: stop at `awaiting_teacher`.

## Commands

```bash
export TMPDIR=$HOME/tmp/banco-build          # /tmp may be full
bundle config set --local path vendor/bundle
bin/rails test                                # all; Chrome tests need BROWSER_PATH
PROP_RUNS=300 bin/rails test test/lib/diagnosis test/models/diagnosis   # engine and its properties
bin/rails test:system                         # Cuprite, needs BROWSER_PATH (one file: bin/rails test:system test/system/outbox_test.rb)
node --test 'app/javascript/grader/test/**/*.test.mjs' 'lib/harness/test/*.test.mjs'   # graders, harness libs (Node 26)
node --test 'test/javascript/**/*.test.mjs'              # student pages: markup parser, outbox
node --test 'app/javascript/lesson/test/*.test.mjs'      # lesson/2 renderer: numbers, diagram vectors, served fixtures
(cd cli && go test ./...) && go build -o bin/banco ./cli   # CLI: test, build
bin/hygiene                                   # public-repo checks (also in CI)
# the forbidden terms are private: HYGIENE_TERMS (CI secret) or untracked prep/hygiene-terms, one per line
bin/check-structure                           # db/structure.sql equals a fresh dump of the migrations (also in CI)
# generated lesson files, each also with --check (run by test/lib/lesson_types_test.rb): colours and icon sprites, the diagram schemas, the registries, the data tables
bin/build-palette; bin/build-icons; bin/build-diagram-schema; bin/build-lesson-types; bin/build-lesson-data
bin/build-icons --check                       # the committed Lucide sprite equals the build from config/banco/icons.yml
bin/preflight --json | jq .ok                 # health of this installation (also: banco health --json)
bin/rubocop && bin/brakeman --no-pager        # style and security
bundle exec puma -C config/puma.rb            # three listeners
```

Ports: `WEB_PORT` 3000 (HTML, behind the edge proxy), `API_PORT` 3100 (token
only), `HARNESS_PORT` 3200 (internal). Never `PORT`.

## Layout

- `app/`, `config/`, `db/`, `test/`: the Rails app. `lib/banco/`: boot-time
  plumbing (listener tag, edge proxy, token auth), required explicitly.
- `cli/`: Go CLI (stdlib only). `contract/commands.json`: the one contract
  shared by the API (`/api/v1/schema`) and the CLI (`go:embed`).
- `briefs/`: authoring briefs for content agents (`banco brief show NAME`);
  `config/banco/`: schemas (`banco.*/1`) and the error-code registry;
  `docs/rules/diagnosis-1.md` with `lib/diagnosis/rules/v1.rb`: the engine rules.
- `app/models/grading/`: server graders. `Grading::Closed` (Ruby: choice, ordering,
  matching, number, fraction, normalized_text), `Grading::Expression` (a Node worker
  per process running `app/javascript/grader/worker.mjs`, our checker plus the
  vendored Compute Engine 0.146.0), `Grading::Evidence` (verdict to C/W/D/pending),
  `Grading::Recorder` (append-only `attempt_gradings`). Never in a transaction.
  Shared vectors: `test/fixtures/grading/vectors.json`.
- `lib/diagnosis/`: the pure engine (no database): `Plan`, `Fold`, `Engine`,
  `Derivation`, `Simulator`; `app/models/diagnosis/`: the loaders that read rows
  for it. `banco diagnosis simulate` is a dry run of the same engine.
- The practice engine (Phase 1b S2, D-235, rules `practice/1` in `docs/rules/practice-1.md` and `lib/practice/rules/v1.rb`):
  `lib/practice/` (`Outcome`, `ServeState` with its transition table, `Fold` for the skill states, `Selector`, `Today`,
  `GraphOrder`), `app/models/practice/` (`Loader`, `Seeder`, `AnswerRecorder`, `Actions`, `Messages`, `Payload`, `Instances`) and
  `Course::Catalog` (what each student sees). Own ledger tables `practice_*`; `Grading` is shared. Tests: `test/lib/practice`,
  `test/models/practice` (`PROP_RUNS=300` for the properties).
- `lib/validation/`, `app/models/validation/`: mechanical validation (A-06) of items,
  graphs and blueprints; thresholds in `config/banco/validation_rules.yml`; agent
  code runs only in Chrome (`ChromeRunner`, the harness in `lib/harness/` served on
  `HARNESS_PORT`); `ValidateItemRevisionJob`; see `docs/validation.md`.
- Independence and review (M6, `docs/validation.md`): `AgentSession` (role, agent, model; the CLI sends
  `BANCO_SESSION` as `X-Banco-Session`), `ItemSessions` (who wrote or reviewed what),
  `config/banco/providers.yml` with `Providers` (model families per role), `Review::` (`ItemText`,
  `Intake`, `Checklist`, `Gate`, `GradeCheck`), the tables `item_reviews`, `blind_solves`,
  `review_findings`, `grade_proposals`. The agents report; dispositions and confirmations are
  teacher decisions (M9).
- The student's pages (M10): `/diagnosis` (list, warm-up at `/diagnosis/warmup`, one sitting page per
  run, end-of-subject screen) and the teacher's `/teacher/preview`. `Diagnosis::Conductor` runs a run for
  the web (engine action to event, item_served with `Diagnosis::Rekey`'s shuffle), `AnswerRecorder`
  records an answer (grade first, then one short transaction), `ItemPresenter` is all the browser is
  told, `Availability`/`Summary`/`Warmup` are the list, the end screen and the warm-up. The browser side
  is `app/javascript/items/` (one template per component, markup, outbox) and
  `app/javascript/student_controllers/`, on their own importmap (`config/importmap.student.rb`, no
  Turbo); MathLive, KaTeX and Compute Engine are served from `public/vendor/<name>@<version>/`.
  CSP: `config/initializers/content_security_policy.rb`. Fixtures that insert instances directly:
  `test/support/student_ui_rows.rb`.
- Teacher decisions (M9a, D-059..D-062): `DecisionRecorder` is the only writer of `decisions`
  (provenance columns, guards: flag, trusted teacher, CSRF, not the student's device);
  `Teacher::DecisionsController` has one POST per kind under `/teacher` (web listener only);
  `Approval::BlueprintGate` is the approval checklist; students' runs pin
  `Diagnosis::Conductor.approved_blueprint`; `bin/reconcile-decisions --since 1d --json` reports orphans.
  Tests: `test/support/decision_world.rb`.
- The teacher's pages (M9b, D-063..D-068): `TeacherController` (home) and `Teacher::` controllers (graph, test
  overview and one screen per skill, corrections, report, item play, activity beat) are read-only; their read
  models are `Teacher::Home|GraphReview|TestReview|Corrections|InstanceView|Minutes|SendBacks|Wording`; the forms
  post the M9a decisions and come back with a flash (`send_back_item` is "Rimanda"). `Diagnosis::Report` is the
  B-09 report (`banco diagnosis report`), `Health` is `banco health` and `bin/preflight`,
  `Diagnosis::Preferences` is the student's theme and size; the font is vendored. Texts: `config/locales/teacher.it.yml`.
- All the questions of a test (D-215): `/teacher/subjects/:key/test/all` (`Teacher::AllQuestions`, `all_questions_controller.js`) shows every
  pinned item with every instance read-only; the decision `confirm_test_reviewed` stands in `Approval::BlueprintGate` for playing the whole
  test; "Chiudi l'anteprima" (`SittingsController#close`, preview only) ends a preview run with `teacher_close`, which does not count as played.
- Supports (D-216): `answer_format_it` and `steps_it` on items, sub items and `display` (`E-SUPPORT-LEAK`, `W-STEPS-METHOD`); the
  start screen's "Come funziona" and the sitting's "Come si risponde" (`items/help_sections.js`, `Diagnosis::SupportEvents`, app events only);
  the formula sheet: blueprint `formula_sheet_it`, decision `set_formula_sheet`, `Diagnosis::FormulaSheet`, `item_served.formula_sheet_available`,
  the report's `formula_sheet` and `marks`. The engine never reads any of it.
- Roles (D-217): `EdgeTrust` says teacher, guest (reads every teacher page, writes nothing, no preview), student; `BANCO_STUDENT_USERS` maps logins to student keys (`student` is official, any other key a trial student: no release, approved or latest validated blueprint, no device cookie, never counted); `?student=KEY` on the teacher's report, corrections and home; `BANCO_GUEST_USERS`, `BANCO_LOGOUT_URL`.
- References (D-218): a skill key or item key on a teacher page goes through `RefsHelper#ref_for` (Italian name, key, popover card from `Teacher::Refs`); `GET /teacher/refs/:key` is its permalink. Never print a bare key there.
- Finding responses (D-220): the author answers blocker and major findings (`FindingResponse`, `Api::V1::FindingsController`, `banco findings list|respond`); the skill screen shows the key, the solver's answer and the latest response; a response never disposes of a finding.
- The student's course pages (Phase 1b S3, D-236): `CourseController` (Oggi, Materie, Materia), `TopicsController`, `LessonsController`,
  `PracticeController`, `QuestionsController` with the concern `StudentCourse`; read model `Course::StudentView`; `Items::Part` (shared with
  `Diagnosis::ItemPresenter`); `student_controllers/{practice,lesson,question}_controller.js`; the practice outbox prefix `banco.poutbox.`.
  Views `app/views/{course,topics,lessons,practice}`; texts `config/locales/course.it.yml`. Tests: `test/integration/course_pages_test.rb`,
  `test/system/course_pages_test.rb`, `test/support/student_course_world.rb`.
- The course (Phase 1b, `docs/course.md`): `Lessons::Parser` and `Lessons::Markup` (lesson.md and markup v2, `lib/lessons/`),
  `Validation::LessonChecks|CourseChecks|TopicChecks`, `Review::LessonIntake`, `LessonSessions`, `Course::State|TopicStage|Status|Decisions`,
  the API controllers `Courses|Lessons|LessonReviews|Topics|PracticeProgress`; `banco course|lessons|lesson|lesson-review|topics|topic|practice`.
- Teacher decisions and pages of the course (S4, D-236): `approve_topic`, `send_back_lesson`, `release_course` (the third is the only way the course opens to the official student), `Approval::TopicGate` (`.mechanical` for the page), `Course::Decisions.release_reasons`; pages `Teacher::CourseReview|TopicReview|PracticeProgress` with `Teacher::ItemCard` (shared with the entry test) and `teacher/items/_card.html.erb`; test world `test/support/topic_world.rb`. Texts: `config/locales/teacher_course.it.yml`.
- The render check of a lesson/2 (R4, D-249, D-255, `docs/validation.md`): `RenderLessonRevisionJob`, `Validation::LessonRenderCheck` and
  `LessonRenderRunner` (Chrome, `lib/validation/`), the render host `HarnessController#lesson` with `app/views/harness/lesson_render.html.erb` and
  `app/javascript/lesson/render_host.js`, `LessonRender` (table `lesson_renders`), `LessonShots` (`storage/lesson_shots/`, `bin/purge-lesson-shots`),
  `LessonRenders` (status, gate reason, the teacher's line), `Api::V1::LessonShotsController` (`banco lesson shots`), `Teacher::LessonShotsController`.
- Free pages (T11, D-290, `docs/pages.md`): `Banco::PagesApp` and `Banco::ListenerSwitch` (`config.ru`, listener tag `pages`, `PAGES_PORT` 3300, never `PORT`), `Pages::` (`Kit`, `Libs`, `Shell`, `Bundle`, `Store`, `Served`, `Embed`, `Pins`, `Diff`, `Submit`), tables `pages page_revisions page_files page_validations page_reviews`, kit `lib/pages_kit/` (`bin/pages-kit-lock`), libraries `vendor/pages/` (`bin/vendor-pages`), `Validation::PageChecks|PageScan|PageRunner`, `ValidatePageRevisionJob`, `Api::V1::Pages|PageReviews`, `banco page|pages|page-review`, the block `Lessons::Blocks::FreePage` with `lesson/blocks/page.js` and `lesson/free_page.js`, `approve_topic` `pages_confirmed`, `BANCO_PAGES_ENABLED`. Tests: `test/integration/pages_*_test.rb`, `test/validation/page_*_test.rb` (Chrome), `test/system/pages_system_test.rb`, `test/lib/pages_kit_test.rb`.
- The skill map (D-221): `Teacher::GraphMap` (layout), `GraphMapContext` (pins, entry, seconda lines), `teacher/graphs/_map*.erb`, `graph_map_controller.js`; on the graph page and the report.
- Rich lessons (D-244..D-251; formats in R0, parser, renderer, events and render check in R1 to R4): `banco.lesson/2` (cards of typed
  blocks; `config/banco/schemas/lesson.json`, `$defs.body2`) and the diagram DSL `banco.diagram/1` (`diagram.json`, nine types of release 1),
  `config/banco/lesson_palette.yml` (colour roles, carriers, step verbs) and `icons.yml` (Lucide 1.54.0 subset in `public/vendor/lucide@1.54.0/`,
  `bin/build-icons --check`), the `lesson2:` block of `validation_rules.yml` (rules version 8, `lesson.accept_schema1`), briefs `lesson` (v2),
  `lesson-v1`, `lesson-review` (v2). Fixtures: `test/fixtures/lesson2` (demos, `bad/` with `manifest.json`, `numbers.json`, `whitelist.json`,
  `context.json`), `test/fixtures/diagrams/vectors.json`, the role and link cases in `test/fixtures/markup/v2.json` (`"options"`).
- Rich lessons, Ruby side (R1, D-252): `lib/lessons/{parser2,directives,blocks,diagrams,num,palette,icons,student_body,checks,convert1to2}.rb`
  (`Parser2` the fence-aware splitter; `Blocks::*` per-type checks; `Diagrams::*` the nine types and the state overlay; `StudentBody` the whitelist
  served to the page; `Checks.grade` the server's grading of an inline check; `Convert1to2` the lesson/1 draft), `Validation::Lesson2Checks`
  (`Validation::LessonChecks.call` dispatches on `schema:`), `Review::LessonChecklist.for`. Tests: `test/lib/lessons`, `test/validation/lesson2_checks_test.rb`,
  `test/integration/lesson2_api_test.rb` (`PROP_RUNS=300` for the StudentBody sentinel property).
- Maps family (T5, D-276): `lesson/diagrams/maps/{map,insolation,cross_section,geo}.js`, `lesson/diagrams/scene_extras.js`, `Lessons::Diagrams::{Map,Insolation,CrossSection,GeoFormat}`, `Maps::Base`, vectors `test/fixtures/diagrams/types/{map,insolation,cross_section}.json` (`maps_types_test.rb`, `maps.test.mjs`), gallery `test/system/maps_gallery_test.rb`.
- Console decisions (D-260): `bin/rails banco:decide` (`lib/tasks/decide.rake`, `DecisionConsole`, origin `DecisionRecorder::Console`) is the operator's only non-browser way to decide; dry run unless `CONFIRM=1`; `approve_topic` alone takes `ATTEST_IT="<operator's words>"`, which waives only the page-opened requirement and is recorded in the payload and shown on the topic page and course path; the row says `console` (address and group); no route, no CLI command. Tests: `test/integration/decision_console_test.rb`, `test/integration/console_attestation_test.rb`.
- Rich lessons, wave 2 (W2-0 contracts, D-262 to D-271, `docs/lessons-wave2.md`): `config/banco/lesson_types.yml` says what authors may use (`Lessons::Types`,
  `status` available, reserved or draft; `bin/build-lesson-types` makes `lesson/diagrams/registry.js`, `lesson/checks/registry.js`, `lesson/voices.js`); the
  component contract v2 is `lesson/diagrams/contract.js` and `Lessons::Diagrams::Contract` (stubs of the 29 types under `lesson/diagrams/FAMILY/` and
  `lib/lessons/diagrams/`); palette v2 (eleven subjects, `same_as`, `data-palette`), `config/banco/voices.yml`, the vetted tables of `config/banco/data/`
  (`Lessons::VettedData`), the libraries of `lib/lessons/{chrono,dates,num_words,money,chem,words,verbs,bits,program_grammar,sheet}.rb` with their JS twins
  in `lesson/lib/`, the caps `lesson2.types` (rules version 9) and the subject briefs `briefs/lesson-SUBJECT.md`. A track makes its piece `available` in
  the commit of its look gate.
- Wave 2 core checks (T1, D-273): `tiles`, `ordering` and `select` (`lesson/checks/{tiles,ordering,select}.js` with the pure `sequence_model.js` and `select_model.js`,
  `howto.js` for the first-use line and "Come si risponde", `draw.js` `mode: select`; Ruby `Lessons::Checks`, `Lessons::SelectTargets`, `Lessons::Blocks::Check`), the options
  `thousands`, `profile` and `verify` (`Lessons::Verify`, `Grading::Spec#thousands`, `Grading::Closed::Contractions` held until `english/contractions` is written), the truth
  rules L3 to L5 (`Lessons::Blocks::Truth`, which reads the figure types' optional hooks `target_names` and `select_signatures`), `lesson/preload.js` (lazy types and components
  are loaded before the page draws), `sentence` neutral. Texts `config/locales/lesson_checks.it.yml`, styles `app/assets/stylesheets/lesson/checks.css`. Tests:
  `test/lib/lessons/checks_wave2_test.rb`, `student_body_wave2_test.rb`, `test/validation/lesson_checks_wave2_test.rb`, `lesson/test/checks_t1.test.mjs`,
  `test/system/lesson_checks_system_test.rb` (select over a probe figure: no available type offers targets yet).
- The docs family (T8, D-278): `Lessons::Money` (Ruby, `lesson/lib/money.js`, `test/fixtures/lesson2/money.json`), `Lessons::Diagrams::Document` and
  `lesson/diagrams/docs/document.js` (invoice, sheet and cascade), `lib/lessons/blocks/docs.rb` (`source` legal, `reveal`, `oral`), `Lessons::Oral` (the
  outline graded as an ordering by `CheckAnswer`, the model answer withheld), `lesson/blocks/{flip,source,reveal,oral}.js` (`mistake` is on `flip`),
  `Lessons::Blocks.apparatus_words` (`E-LESSON-APPARATUS-WORDS`), `LessonPagesHelper#lesson2_family_stylesheets` and `t.FAMILY` texts. Tests:
  `test/lib/lessons/{money,document,docs_blocks}_test.rb`, `test/integration/docs_blocks_test.rb`, `test/system/docs_family_test.rb` (gallery
  `test/fixtures/lesson2/gallery/docs-lesson.md`), `lesson/test/{money,document}.test.mjs`.
- Charts (W2-1, T6, D-280, `docs/lessons-charts.md`): the axis engine `lesson/diagrams/chart/axis.js` (with `format.js`, `climate.js`), `climograph`, `bar_model` (parts, percent) and `seats` in `lesson/diagrams/chart/` and `lib/lessons/diagrams/{climograph,bar_model,seats,chart_support}.rb`; stations `config/banco/data/geo/stations.yml` and its second table `stations_expected.yml`; the controls of any type `lesson/diagrams/controls.js`; the leak rules L4, L5 and L7 in `Lessons::Diagrams.answer_leaks` and `Lesson2Checks`. Tests: `chart_axis` and `chart_types` (node), `test/lib/lessons/chart_types_test.rb`, `test/lib/stations_test.rb`, `test/system/lesson_chart_gallery_test.rb`.
- Third reviewer (D-222): role `arbiter` (`FindingAssessment`, `FindingOpinion`, `Teacher::FindingField`, `banco findings assess`, `briefs/arbiter.md`); first opinion claude-opus-5-5, second claude-haiku-4-5-20251001 (`config/banco/providers.yml`); blocker and major findings stay a teacher click ("Segui il parere", `follow_opinions`), minor ones are closed or marked to fix as derived state by the first opinion alone (D-239); no effect on `Review::Gate` or `Approval::BlueprintGate`.
- The student's front door and menu (D-240): `GET /` (`HomeController`) sends a student to `/today`, the teacher and a guest to `/teacher`; `/today` is the student's home (entry test block, then the course); `shared/_student_menu` (helpers `student_menu_*`) is on every student page, one item "Pausa: torna a Oggi" in a sitting and none in the teacher's preview; `/settings` holds the theme and size.
- The course path and the guided review (D-241): the course page is the subject's path (`Teacher::CourseReview#steps`, badges, `?only=ready`), the topic page has four steps (lesson as S sees it, exercises drawn by `items/frozen_slot.js`, findings through `teacher/tests/_finding`, approval); `Teacher::TopicSeen` and `POST /teacher/topic-revisions/:id/seen` keep app events `teacher_read_lesson` and `teacher_saw_exercise`, never decisions; the gate is unchanged. Tests: `test/support/course_path_world.rb`.
- The lesson/2 renderer (R2, D-253): `app/javascript/lesson/` (`render.js` the page, `cards.js`, `blocks/*`, `diagrams/*` with `registry.js`, `draw.js`, `text.js`, `num.js`, `schema.js`; generated `palette.js` and `diagram_schema.js`), `student_controllers/lesson2_controller.js` and `lesson2_preview_controller.js`, `lessons/show2.html.erb`, `teacher/topics/_lesson2_box`, `lesson.css`, generated `lesson_roles.css` (`bin/build-palette`, `bin/build-diagram-schema`, `bin/build-icons`, each with `--check` in CI), `Banco::Lesson2` (`BANCO_LESSON2_ENABLED`). Tests: `node --test 'app/javascript/lesson/test/*.test.mjs'` (the lesson modules import by importmap names: a test file imports `./setup.mjs` first and the module with `await import`), `test/system/lesson2_page_test.rb`, `test/integration/lesson2_page_test.rb`, served-form fixtures `test/fixtures/lesson2/served/`.
- Words and languages (W2-1, T3, D-284): `Lessons::Words` (Ruby, `lesson/lib/words.js`, vectors `test/fixtures/lesson2/{spanish_words,split}.json`: the split notation, Spanish syllables, stress and the tilde rule; `present` is W2-2), `word_parts` and `mirror` in `lesson/diagrams/words/` (with `texts.js`, the twin of `config/locales/lesson_words.it.yml`) and `lib/lessons/diagrams/{word_parts,mirror}.rb`, the `dialogue` block `lesson/blocks/dialogue.js` with `lib/lessons/blocks/dialogue.rb` (the glosses are served whole and read only once opened; the voice controls show only with an accepted voice). Vectors `test/fixtures/diagrams/types/{word_parts,mirror}.json` (`words_types_test.rb`, `words_types.test.mjs`), galleries `gallery/words.md` and `words-english.md` (`test/validation/lesson_words_gallery_test.rb`, `test/system/words_family_test.rb`, `test/content/words_gallery_lesson_test.rb`).
- Computing, wave 2 (T9, D-274, D-275): the grid engine `lesson/diagrams/grid/{api,engine}.js` (geometry only); `Lessons::Bits` with `lesson/lib/bits.js` (vectors `test/fixtures/lesson2/bits.json`);
  `register` (row and ring) and `column_calc`: `lesson/diagrams/computing/{register,register_ring,column_calc,bits_common}.js`, `lib/lessons/diagrams/{register,column_calc,bits_view}.rb`,
  vectors `test/fixtures/diagrams/types/{register,column_calc}.json`, `app/assets/stylesheets/lesson/computing.css`, the generic native controls `lesson/diagrams/controls.js` (draw.js builds what `controls()` declares);
  `input: bits` `lesson/checks/bits_input.js` (`Lessons::Checks.bits_switches?`); the L4 and L5 checks `Lessons::Leaks`. Tests: `lesson/test/{grid,bits,computing}.test.mjs`, `test/content/computing_types_test.rb`,
  `test/lib/lessons/{bits,bits_input,leaks}_test.rb`, `test/validation/computing_gallery_test.rb` (Chrome), `test/system/computing_system_test.rb`. Gallery `test/fixtures/lesson2/gallery/computing.md`.
- Lesson events and checks (R3, D-254): `lesson_events` (append-only, `LessonEvent`; read only by `Lessons::Progress`), `LessonEventsController` (card_seen batch), `LessonChecksController` with `Lessons::CheckAnswer` (grades with `Lessons::Checks`, tries counted by the server, never the practice ledger), `Teacher::LessonRevisionsController` (`full.json` and the box's checks with the seed "preview"), `student_questions.card`, `Lessons::Progress.resume_card` for Oggi, the teacher's lesson line (`lesson_progress_line`). No practice, diagnosis, teacher or course read model names the table. Tests: `test/integration/lesson_events_test.rb`, `lesson_teacher_test.rb`, `test/system/lesson_events_system_test.rb`.
- The dashboard and the menu (D-242, D-243): `/teacher` is the Cruscotto (`Teacher::Dashboard`, `DashboardDigest`, `dashboard_controller.js` polls `/teacher/dashboard/state` and fetches `/fragment`); every teacher page has the menu (`teacher/_menu`, `TeacherMenuHelper`, `menu_controller.js`), a breadcrumb and a subject switcher; dashboard links open in new tabs.
- The text layer (wave 2, T2, D-282): spans `[[en:..]]`, `[[es:..]]`, `[[la:..]]`, `[[code:..]]`, `[[g:term]]` and `[[role|it:..]]` in `Lessons::Markup` and `items/markup_parser.js` (shared cases `test/fixtures/markup/v2.json`, `options.target`); `Lessons::Lang` (which subject teaches which language, keys `_en|_es|_la`), `Lessons::Lexicon` with `config/banco/lexicon/{en,es}.txt` (frequency lists for `W-LANG-LEVEL`, licence in its README), `Lessons::ChemSymbols` (`E-CHEM-SYMBOL`), the lint split and the glossary checks in `Validation::Lesson2Checks`; the browser side `lesson/{lang,text,cards}.js` (spans, glossary bubble and the list under a card), mhchem `public/vendor/katex@0.19.0/contrib/mhchem.mjs` (`katex/mhchem`, loaded for chemistry and biology by `lesson/preload.js`). Tests: `test/validation/lesson2_text_layer_test.rb`, `test/system/lesson_text_system_test.rb`, the bad fixtures `lang-*`, `chem-symbol-unknown`, `apparatus-glossary`.
- "Ascolta" (wave 2, T2, D-283): `lesson/speech.js` is the frozen contract (gate, `speechOf` walker, `speak`, `stopAll`); `speech_state.js`, `speech_device.js` (voices, switches, `localVoices`), `speech_ui.js` (the card's "Ascolta", `speakerButton`), `speech_math.js` (how formulas, chemistry, code and bits are said), `checks/listen.js` (the `listen` option, `text_shown`), `student_controllers/voices_controller.js` ("Prova le voci" on `/settings#voci`); `config/banco/voices.yml` stays empty until the operator has heard the voices on the student's device (no speaker is shown before); `Diagnosis::Preferences` keeps `listen` and `slower`. Tests: `lesson/test/speech.test.mjs` (a tiny DOM), `test/system/lesson_text_system_test.rb` (a stand-in `speechSynthesis`), `test/system/lesson_speech_golden_test.rb` with `test/fixtures/lesson2/speech/*.json` (`GOLDEN=1` rewrites them).
- The map bases (wave 2, T5, D-272): `bin/build-maps` makes `public/vendor/banco-maps@1/` offline from `config/banco/data/geo/source/` (Natural Earth, World Bank; `--fetch` refreshes them), `lib/maps/` and its JS twin `app/javascript/lesson/lib/map_projection.js` (`Geom`, `Sources`, `Tables`, `Pleiades`, `Builder`); vetted tables `config/banco/data/geo/{names,countries}.yml` and `history/{places,regions}.yml` (each with a schema, `places_expected.yml` is the second table); tests `test/lib/maps`; licences in the directory's `LICENSE` and `PROVENANCE.md` (AWMC not used: ODbL).
- `docs/decisions.md`: every deviation and operator answer (`## D-NNN`, index at the
  top). Change the design only by adding an entry.
- `prep/`: private working material, git-ignored, never committed.

## Conventions

- Never UPDATE or DELETE a ledger row; add rows.
- Identity comes only from `EdgeTrust` (peer address plus listener); never from
  `request.remote_ip`, `request.port` or a client header alone.
- Tests that need `prep/` or Chrome skip with a clear message when absent.
- No real student or household data in git, no secrets, no `.env` reads.
- Small tested steps, commit messages in English; verify (run the commands above).
- Science family (W2-1, T7, D-285 to D-288): `formula`, `molecule`, `periodic_table`, `strand` in `lesson/diagrams/science/{formula,molecule,periodic_table,strand}.js` (with `common.js` and `molecule_draw.js`) and `lib/lessons/diagrams/{formula,molecule,periodic_table,strand,science_support}.rb`; the chemistry tables `config/banco/data/chem/{elements,molecules,terms}.yml` (and `elements_expected`, `molecules_expected`), `Lessons::Chem` and `lesson/lib/chem.js` (`test/fixtures/lesson2/chem_formulas.json`); vectors `test/fixtures/diagrams/types/{formula,molecule,periodic_table,strand}.json`. Tests: `test/content/science_types_test.rb`, `science_colours_test.rb`, `test/lib/chem_data_test.rb`, `test/lib/lessons/chem_test.rb`, `science.test.mjs` and `chem.test.mjs` (node), `test/system/science_system_test.rb`, `test/validation/science_gallery_test.rb` (gallery `test/fixtures/lesson2/gallery/science.md`).

