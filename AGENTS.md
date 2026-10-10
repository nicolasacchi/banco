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
   (a derived state, never a decision row): D-222, D-239.
3. Agent-written code runs only in browsers (the server's Chrome at validation).
   Rails and the grader worker never execute it.
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
- Third reviewer (D-222): role `arbiter` (`FindingAssessment`, `FindingOpinion`, `Teacher::FindingField`, `banco findings assess`, `briefs/arbiter.md`); first opinion claude-opus-5-5, second claude-haiku-4-5-20251001 (`config/banco/providers.yml`); blocker and major findings stay a teacher click ("Segui il parere", `follow_opinions`), minor ones are closed or marked to fix as derived state by the first opinion alone (D-239); no effect on `Review::Gate` or `Approval::BlueprintGate`.
- The student's front door and menu (D-240): `GET /` (`HomeController`) sends a student to `/today`, the teacher and a guest to `/teacher`; `/today` is the student's home (entry test block, then the course); `shared/_student_menu` (helpers `student_menu_*`) is on every student page, one item "Pausa: torna a Oggi" in a sitting and none in the teacher's preview; `/settings` holds the theme and size.
- The course path and the guided review (D-241): the course page is the subject's path (`Teacher::CourseReview#steps`, badges, `?only=ready`), the topic page has four steps (lesson as S sees it, exercises drawn by `items/frozen_slot.js`, findings through `teacher/tests/_finding`, approval); `Teacher::TopicSeen` and `POST /teacher/topic-revisions/:id/seen` keep app events `teacher_read_lesson` and `teacher_saw_exercise`, never decisions; the gate is unchanged. Tests: `test/support/course_path_world.rb`.
- The lesson/2 renderer (R2, D-253): `app/javascript/lesson/` (`render.js` the page, `cards.js`, `blocks/*`, `diagrams/*` with `registry.js`, `draw.js`, `text.js`, `num.js`, `schema.js`; generated `palette.js` and `diagram_schema.js`), `student_controllers/lesson2_controller.js` and `lesson2_preview_controller.js`, `lessons/show2.html.erb`, `teacher/topics/_lesson2_box`, `lesson.css`, generated `lesson_roles.css` (`bin/build-palette`, `bin/build-diagram-schema`, `bin/build-icons`, each with `--check` in CI), `Banco::Lesson2` (`BANCO_LESSON2_ENABLED`). Tests: `node --test 'app/javascript/lesson/test/*.test.mjs'` (the lesson modules import by importmap names: a test file imports `./setup.mjs` first and the module with `await import`), `test/system/lesson2_page_test.rb`, `test/integration/lesson2_page_test.rb`, served-form fixtures `test/fixtures/lesson2/served/`.
- Lesson events and checks (R3, D-254): `lesson_events` (append-only, `LessonEvent`; read only by `Lessons::Progress`), `LessonEventsController` (card_seen batch), `LessonChecksController` with `Lessons::CheckAnswer` (grades with `Lessons::Checks`, tries counted by the server, never the practice ledger), `Teacher::LessonRevisionsController` (`full.json` and the box's checks with the seed "preview"), `student_questions.card`, `Lessons::Progress.resume_card` for Oggi, the teacher's lesson line (`lesson_progress_line`). No practice, diagnosis, teacher or course read model names the table. Tests: `test/integration/lesson_events_test.rb`, `lesson_teacher_test.rb`, `test/system/lesson_events_system_test.rb`.
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
