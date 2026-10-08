# Practice rules, version 1 (`practice/1`)

Regole dell'esercizio guidato, versione 1.

This note is the prose of the rules the practice engine applies. The numbers live in
`lib/practice/rules/v1.rb` (`Practice::Rules::V1`); a test (`test/lib/practice/rules_test.rb`) fails when the two drift
apart. Every serve records `rules_version`. A change to a constant bumps the version, and all skill states are
re-derived from the stored rows (nothing is rewritten). The note is generic: one student, a teacher who is also
the operator, eleven subjects. Facts about a real student never go in this repository.

Il testo di riferimento è in inglese, come il codice. Le frasi che lo studente legge sono citate in italiano.

Practice is deterministic (firm rule 1): feedback, hints, messages and solutions are approved stored text chosen
by code. No model is in the student's path. The practice ledger is separate from the diagnosis ledger (D-228).

## 1. Constants

| Name | Value | Meaning |
|---|---|---|
| `RULES_VERSION` | `practice/1` | recorded on every serve |
| `DEMONSTRATE_CORRECT_UNAIDED` | 3 | distinct fingerprints answered correctly without help |
| `DEMONSTRATE_DISTINCT_DAYS` | 2 | Europe/Rome calendar days |
| `DEMONSTRATE_MIN_LOW_GUESS` | 2 | of those fingerprints; low guess as `Diagnosis::Rules::V1.low_guess?` |
| `CONSOLIDATE_AFTER_DAYS` | 14 | days after `demonstrated_at` |
| `REVIEW_BACK_CORRECT` | 2 | correct unaided tries to leave `to_review` |
| `MAX_WRONG_TRIES` | 2 | counted W tries per serve |
| `MAX_NEAR_MISS_RETRIES` | 1 | a second near miss closes the serve |
| `MAX_TRIES` | 3 | stored tries per serve (follows from the two above) |
| `ADVANCE_AFTER_CORRECT_UNAIDED` | 2 | per pinned item, before the next item in pin order |
| `OPEN_SERVE_HOURS` | 24 | an older open serve is abandoned |
| `TIME_CAP_SECONDS` | 600 | cap on the time of one try |
| `SUGGESTIONS_MAX` | 3 | suggestions in Oggi |
| `ZONE` | `Europe/Rome` | calendar days |
| `STATES` | `not_seen to_recover to_learn in_study demonstrated consolidated to_review` | |

## 2. Outcome of one graded try

`Grading::Evidence.key` (the diagnosis table, same item declarations) gives the evidence key.

| Evidence key | Evidence | Outcome | Message |
|---|---|---|---|
| `correct` | C | `correct`, or `correct_aided` when the try is aided | `practice.correct` / `practice.correct_aided` |
| `orthography_slip` | C | as correct, plus `practice.accents_note` | |
| `wrong_form_declared` | C | as correct, plus the form message | |
| `typical_error` | W | `typical_error` (codes) | the catalogue `message_it` of the first code |
| `wrong` | W | `unrecognised` | `practice.unrecognised` |
| `wrong_form_skill` | W | `form` | the form message, fallback `practice.form` |
| `near_miss` | N | `near_miss` | `practice.near_miss` |
| `undetermined`, `float_method`, `wrong_form_undeclared` | N | `undetermined` | `practice.undetermined` |
| `invalid` | none | not a try (app event `practice_invalid_input`) | the grader's message |

A try is **aided** when a hint of the serve was shown before it, or a W try exists on the serve, or the serve's
reason is `reseen`. A near miss does not make the next try aided. **C_unaided** = C and not aided.

In breve: la risposta giusta senza aiuti conta. Con un aiuto, o su un esercizio già visto, non conta per
dimostrare l'abilità.

## 3. Serve state machine

A serve is **open** unless a row below closed it. An open serve older than `OPEN_SERVE_HOURS` is
**abandoned** (closed, no outcome). `W` = W tries so far, `NM` = near-miss tries so far.

| # | Serve now | Event and outcome | Serve after | Solution sent | Hint sent | Actions |
|---|---|---|---|---|---|---|
| 1 | open, W=0 | correct / correct_aided | closed `correct` | yes (`after_correct`) | none | `next`, `back` |
| 2 | open, W=0 | typical_error (code c) | closed `wrong` | no | none | `prova_questo`, `show_solution`, `back` |
| 3 | open, W=0 | unrecognised | open, W=1 | no | next unseen hint, `auto: true` (none left: none) | `retry`, `show_solution` |
| 4 | open, W=0 | form | open, W=1 | no | none | `retry`, `show_solution` |
| 5 | open, W=1 | correct (aided by rule) | closed `correct` | yes (`after_correct`) | none | `next`, `back` |
| 6 | open, W=1 | typical_error / unrecognised / form | closed `wrong` | yes (`after_last_try`) | none | typical: `prova_questo`, `after_solution`, `back`; else `after_solution`, `back` |
| 7 | open, NM=0 | near_miss | open (W, aided unchanged) | no | none | `retry` |
| 8 | open, NM=1 | near_miss | closed `near_miss` | yes (`after_last_try`) | none | `after_solution`, `next`, `back` |
| 9 | open | undetermined | closed `undetermined` | yes (`after_undetermined`) | none | `next`, `back` |
| 10 | open | invalid | unchanged (only the app event) | none | none | unchanged |
| 11 | open | hint `n` = shown + 1 and at most the total | open; later tries aided | none | hint n | unchanged |
| 12 | open | "Mostrami la soluzione" | closed `solution` | yes (`requested`) | none | `after_solution`, `back` |
| 13 | closed `wrong` (row 2) | "Mostra la soluzione" | unchanged | yes (`after_wrong`) | none | `after_solution`, `back` |
| 14 | closed, solution already sent | "Mostra la soluzione" | unchanged | the same solution, no new event | none | unchanged |
| 15 | closed or abandoned | answer, hint | unchanged; HTTP 409 `{"status":"closed"}` | none | none | none |

Actions: `next` = new serve without follow; `prova_questo` = new serve with follow
`{serve_id, kind: "prova_questo"}`; `after_solution` = follow `{serve_id, kind: "after_solution"}`; `retry` =
answer the same serve; `back` = the topic page. At most three stored tries follow from rows 3 to 8.

## 4. Atomicity

- **Serve creation**: one transaction (SQLite `BEGIN IMMEDIATE`) reads the student's open serve on the skill and
  inserts only if there is none. Two tabs, an outbox retry or a reload get the same serve.
- **Answer**: grade first, outside any transaction; then one short transaction re-derives the serve state,
  refuses with 409 if closed, and inserts the attempt (`try_number` = stored tries + 1) and the grading. The
  unique (`practice_serve_id`, `try_number`) and the unique `client_attempt_id` make a concurrent duplicate fail;
  a repeated `client_attempt_id` returns the stored answer. Expression worker down: HTTP 503
  `{"status":"retry"}`, nothing stored, the outbox resends.
- **Hint**: the request carries `n`; the event is written only if `n` = shown + 1; `n` at most shown returns
  hint n again; anything else is 422.

## 5. Skill states

Fold per skill over the tries in time order:

- Start: the seed (section 6), else `not_seen`.
- Any try while `not_seen`, `to_recover` or `to_learn` gives `in_study`.
- `in_study` gives `demonstrated` at the first try after which the C_unaided tries cover at least 3 distinct
  fingerprints, on at least 2 distinct days, with at least 2 of those fingerprints low-guess
  (`demonstrated_at` = that try's time).
- `demonstrated` gives `consolidated` at a C_unaided try on a fingerprint first served at that serve, at least
  14 days after `demonstrated_at`.
- `demonstrated` or `consolidated` gives `to_review` at a W try that is not aided; it remembers the previous state.
- `to_review` returns to the previous state after 2 C_unaided tries on distinct fingerprints since entering.
- Tries on voided item revisions are skipped.

Output per skill: state, since, `demonstrated_at`, `consolidated_at`, seed, counts (serves, tries,
correct_unaided, correct_aided, wrong, typical per code, unrecognised, near_miss, undetermined, hints,
solutions_requested, abandoned, seconds), and `why` (a code and its parameters). Seconds per try run from the
serve (try 1) or the previous try to the answer, capped at `TIME_CAP_SECONDS`.

The topic status for the student: `done` when every skill is `demonstrated` or `consolidated`; `in_progress`
when any try or a `lesson_opened` exists; else `todo`. The tag "Da riprendere" shows when a skill is
`to_recover` or `to_review`.

Days: the loader computes `Try.day` as `answered_at` in Europe/Rome; the fold receives dates and never touches a
zone. Tests cover the 2026-10-25 change to winter time.

## 6. Seeds and voids

The seed comes from the student's latest non-voided closed diagnosis run in the subject (trial students use
their own runs):

| Diagnosis state (kind) | Seed | Why the student reads |
|---|---|---|
| demonstrated | `demonstrated`, `demonstrated_at` = run close | "Dimostrata nella diagnosi del %{date}." |
| to_recover (recover) | `to_recover` | "Nella diagnosi: da riprendere." |
| to_recover (learn) | `to_learn` | "Nella diagnosi: da imparare." |
| not_assessed, reason `below_demonstrated` | `demonstrated` (implied), same date | "Non serviva verificarla: hai dimostrato un'abilità che la usa." |
| not_assessed (other), pending | no seed | none |

A seeded `demonstrated` consolidates by the same rule. Course skills of the second year have no seed.

Voids: the loader reads the `void_revision_attempts` decisions and drops the official student's practice tries on
those item revisions. The diagnosis derivation is not changed.

## 7. Serving

Input: student, visible topic revision, skill, optional follow `{serve_id, kind}`, clock.

1. An **open** serve of the student on this skill is returned as is, whatever the follow says.
2. `prova_questo` (the followed serve is the student's, closed `wrong` with a typical try of code c on item
   revision R): the first unseen instance of R whose stored errors have c; else of another pinned item of the
   skill; else rule 4 (reason `next`, parent set). Reason `prova_questo`, error code c.
3. `after_solution` (the followed serve had its solution sent): an unseen instance of the same item revision;
   else rule 4 (reason `next`, parent set).
4. Next: the pinned items of the skill in pin order; the current item is the first with fewer than
   `ADVANCE_AFTER_CORRECT_UNAIDED` C_unaided tries by this student (any revision); when all have them, the item
   served least recently. Pick its first unseen instance; if none, the next pinned item with one.
5. "Unseen" = the instance **fingerprint** was never served to this student in practice. Among candidates the
   order is `sha256("#{student_id}:#{fingerprint}")` ascending.
6. No unseen instance in the skill's pinned items: the instance whose last serve is the oldest, reason `reseen`
   (its tries are aided; the page says "Questo esercizio l'hai già visto: non conta per dimostrare l'abilità.").
7. The display is re-keyed as in the diagnosis (`Diagnosis::Rekey`, seed per serve).

A follow that names another student's serve, an open serve, or a serve that does not allow it: 422
`{"status":"bad_follow"}`.

## 8. Oggi

1. **Riprendi**: the visible topic of the student's latest serve or `lesson_opened`, unless it is done.
2. **Suggestions**, at most three, from visible topics that are not done and not the Riprendi topic:
   a. topics holding a `to_recover` skill, ordered by the skill's position in the topological order of the
      subject's union graph (graph plus course map; Kahn, ties by key), then by course order; subjects
      interleaved round-robin by subject position;
   b. topics holding a `to_learn` skill, same order;
   c. topics holding a `to_review` skill;
   d. the remaining visible topics in course order.
   Each carries its reason code (`to_recover`, `to_learn`, `to_review`, `course_next`) and the skill.
3. Skills `to_recover` or `to_learn` with no visible topic are never suggested; the subject page names them and
   the teacher's progress page lists them.
4. No diagnosis run in a subject: only rule d for it.

"Prima conviene fare: X" on the subject page: X is an `after` topic of the topic that is visible and not done.
The topic stays openable.

## 9. Hints and the solution

Hints are on request or automatic (row 3), counted, and make later tries aided. A practice instance has 2 to 4
effective hints (item `hints_it`, or the instance's own); a hint never carries the instance key
(`E-HINT-KEY`). The worked solution is sent after a correct answer, after the last try, after an undetermined
answer, or on request. The student never sees a solution before the item is closed or asked for.
