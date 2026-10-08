# banco: agent guide

banco is a study app for one private-candidate student preparing an Italian
upper-secondary exam. Rails 8.1 app with a deterministic engine (no LLM in the
student's path) plus a Go CLI (`banco`) that the teacher's AI agent uses.
Phase 1a: the entry diagnosis.

## Firm rules (change only after talking to the operator)

1. The student talks only to the software: no chat and no model in the student's path.
2. Decisions are taken by the teacher in the browser (web listener only). No
   `/api/v1` route creates a decision; the CLI has no decision command.
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
(cd cli && go test ./...) && go build -o bin/banco ./cli   # CLI: test, build
bin/hygiene                                   # public-repo checks (also in CI)
# the forbidden terms are private: HYGIENE_TERMS (CI secret) or untracked prep/hygiene-terms, one per line
bin/check-structure                           # db/structure.sql equals a fresh dump of the migrations (also in CI)
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
- The course (Phase 1b, `docs/course.md`): `Lessons::Parser` and `Lessons::Markup` (lesson.md and markup v2, `lib/lessons/`),
  `Validation::LessonChecks|CourseChecks|TopicChecks`, `Review::LessonIntake`, `LessonSessions`, `Course::State|TopicStage|Status|Decisions`,
  the API controllers `Courses|Lessons|LessonReviews|Topics|PracticeProgress`; `banco course|lessons|lesson|lesson-review|topics|topic|practice`.
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
