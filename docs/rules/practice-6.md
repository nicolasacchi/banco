# Practice rules, version 6 (`practice/6`)

Regole dell'esercizio guidato, versione 6. Le versioni da 1 a 5 restano in `practice-1.md`, `practice-2.md`, `practice-3.md`, `practice-4.md` e `practice-5.md` come memoria.

Version 6 (D-366) changes one number, `ADVANCE_AFTER_CORRECT_UNAIDED`, from 2 to 1: the selector changes item after each right
try without help (rule 6 of section 7), so a run of right answers goes through the pinned items one by one instead of two on each. What
counts to demonstrate a skill is not touched (3 distinct fingerprints right without help, 2 of them hard to guess). The line
«esercizio simile» (rule 10) says «ne serve uno giusto». A serve already stored keeps the version it was made under; no state
is re-derived differently, because the fold does not read `ADVANCE_AFTER_CORRECT_UNAIDED`.
Version 5 (D-348) changes the selector, not a number: when a skill has no unseen instance left, the selector no longer serves a seen
one on its own (the old `reseen` fallback of the automatic choice is gone); it records the fact once (`PracticePoolExhaustion`) and the
page says so. The student can still redo an exercise by choosing it (`item`, «Rifai»): that serve keeps the reason `reseen`.
Version 4 (D-341) drops the two-days condition: a skill is demonstrated on 3 distinct exercises right without help, 2 of them
hard to guess, even on the same day (`DEMONSTRATE_DISTINCT_DAYS` is gone). Every other constant is as in version 3. Version 3
(D-339) changed the feedback, not the numbers: a typo or one missing or added word is a near miss; the student can send a try
she believes right to the teacher (a **contest**, «Fai controllare»; since D-389 «Per me va bene così», on every try that is not right).

This note is the prose of the rules the practice engine applies. The numbers live in
`lib/practice/rules/v6.rb` (`Practice::Rules::V6`); a test (`test/lib/practice/rules_test.rb`) fails when the two drift
apart. Every serve records `rules_version`. A change to a constant bumps the version, and all skill states are
re-derived from the stored rows (nothing is rewritten). The note is generic: one student, a teacher who is also
the operator, eleven subjects. Facts about a real student never go in this repository.

Il testo di riferimento è in inglese, come il codice. Le frasi che lo studente legge sono citate in italiano.

Practice is deterministic (firm rule 1): feedback, hints, messages and solutions are approved stored text chosen
by code. No model is in the student's path. The practice ledger is separate from the diagnosis ledger (D-228).

## 1. Constants

| Name | Value | Meaning |
|---|---|---|
| `RULES_VERSION` | `practice/6` | recorded on every serve |
| `DEMONSTRATE_CORRECT_UNAIDED` | 3 | distinct fingerprints answered correctly without help |
| `DEMONSTRATE_MIN_LOW_GUESS` | 2 | of those fingerprints; low guess as `Diagnosis::Rules::V1.low_guess?` |
| `CONSOLIDATE_AFTER_DAYS` | 14 | days after `demonstrated_at` |
| `REVIEW_BACK_CORRECT` | 2 | correct unaided tries to leave `to_review` |
| `MAX_WRONG_TRIES` | 2 | counted W tries per serve |
| `MAX_NEAR_MISS_RETRIES` | 1 | a second near miss closes the serve |
| `MAX_TRIES` | 3 | stored tries per serve (follows from the two above) |
| `ADVANCE_AFTER_CORRECT_UNAIDED` | 1 | per pinned item, before the next item in pin order |
| `OPEN_SERVE_HOURS` | 336 | 14 days: an older open serve is abandoned (an exercise left half done is kept two weeks) |
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
| `nearly_correct` (D-301; never a judge of two options nor one option for every row, D-314) | C | as correct, plus the line «Giusto, tranne una coppia: …» (`Grading::PairNote`) | |
| `wrong_form_declared` | C | as correct, plus the form message | |
| `typical_error` | W | `typical_error` (codes) | the catalogue `message_it` of the first code |
| `wrong`, no near (see below) | W | `unrecognised` | `practice.unrecognised` (`practice.unrecognised_no_hint` when the item has no hint) |
| `wrong`, near `typo` | N | `near_miss` | `practice.near_typo` |
| `wrong`, near `one_word` | N | `near_miss` | `practice.near_one_word` |
| `wrong_form_skill` | W | `form` | the form message, fallback `practice.form` |
| `near_miss` (the grader's own, `spelling_policy: near`) | N | `near_miss` | `practice.near_miss` |
| `undetermined`, `float_method`, `wrong_form_undeclared` | N | `undetermined` | `practice.undetermined` |
| none: the student sent the try to the teacher (a contest, section 3) | N | `contested` | `practice.contested` |
| `invalid` | none | not a try (app event `practice_invalid_input`) | the grader's message |

**Near** (`Outcome.call(evidence_key:, aided:, near:)`): `near` is `nil`, `:typo` or `:one_word`, the answer of
`Grading::NearText.kind(answer, candidates, case_sensitive: false)`. It is set only for a `normalized_text` item and
the evidence key `wrong` (never when a declared error, an accent slip or an accepted form matched). `:typo` = the same
number of words as a candidate, exactly one word differs by one letter (two when the word has 8 letters or more, and
the word has at least 4 letters); `:one_word` = the answer is a candidate with one whole word missing or added, never
a substitution. A near miss is N: the rows 7 and 8 of section 3 apply (one retry, then the serve closes with the
solution). `contested` is N too: a contested try counts neither way in the fold.

**The loader's near rule.** For every stored try whose evidence key is `wrong` on a `normalized_text` item,
`Practice::Instances.grade` derives `near` from the graded text: the grading's `normalized` when stored (when the
grader saw a whole sentence around `___` it graded the words between, and `normalized` holds them), else the attempt's
raw answer. The candidates are the key of the instance and its accepted answers plus the item's. The rule is
deterministic, so a try stored before version 3 is derived the same way, and the same function runs when the
answer is recorded. A try with a `PracticeContest` row (one per attempt, append-only) has the outcome `contested`.

A try is **aided** when a hint of the serve was shown before it, or a W try exists on the serve, or the serve's
reason is `reseen`. A near miss does not make the next try aided. **C_unaided** = C and not aided.

In breve: la risposta giusta senza aiuti conta. Con un aiuto, o su un esercizio già visto, non conta per
dimostrare l'abilità. Se manca poco (un errore di battitura, una parola in meno o in più) la risposta non conta né a
favore né contro: ci sei quasi, riprova.

## 3. Serve state machine

A serve is **open** unless a row below closed it. An open serve is **abandoned** (closed, no outcome) when it is
older than `OPEN_SERVE_HOURS`, or when it is **superseded**: a newer serve of the same student on the same item
(the item, any revision) exists. A serve the student skips is not closed: it stays open, with what she typed
kept as a draft (not a try), and she can come back to it. `W` = W tries so far, `NM` = near-miss tries so far.
A **contest** is the student's act on the LATEST try of a serve («Per me va bene così», D-389; «Fai controllare» before): it is
allowed when that try's outcome is `typical_error`, `unrecognised`, `form` or `near_miss` (every try that is not right) and it is
not contested yet, on an open serve or on a serve closed `wrong`, `near_miss` or `solution` (the solution he asked for on an open serve,
D-395); never without a try, after a correct or undetermined answer, twice, or on a serve closed in another way (`correct`, `undetermined`).
The try's outcome becomes `contested` (N), the serve is closed `contested`, and the solution is sent (`after_contest`)
unless it was already sent. The actions of a serve include `contest` exactly when a contest is allowed on it.

In breve: un esercizio lasciato a metà resta aperto per due settimane. Se lo rifai, quello vecchio si chiude.

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
| 16 | open, latest try typical_error, unrecognised, form or near_miss | contest | closed `contested`; the try is `contested` (N) | yes (`after_contest`) | none | `next`, `back` |
| 17 | closed `wrong` (rows 2, 6), closed `near_miss` (row 8) or closed `solution` (row 12), latest try not right | contest | closed `contested`; the try is `contested` (N) | yes (`after_contest`) unless already sent | none | `next`, `back` |
| 18 | closed `contested` | contest again | unchanged; the same answer, no new event, no second contest | none | none | unchanged |

Rows 2, 3, 4, 6, 7 and 8 carry the action `contest`, last, when the latest try allows it (rows 16 and 17): `retry`, `show_solution`,
`contest` on an open serve (`retry`, `contest` after a near miss); `after_solution`, `back`, `contest` (or `show_solution`, `back`, `contest`,
or with `prova_questo` after a typical error) on one closed `wrong`; `after_solution`, `next`, `back`, `contest` on one closed `near_miss`; `after_solution`, `back`, `contest` on one closed `solution` after a try that is not right.
A contest not allowed (any other state, the serve closed otherwise, abandoned): HTTP 409 `{"status":"not_contestable"}`.

Actions: `next` = new serve without follow; `prova_questo` = new serve with follow
`{serve_id, kind: "prova_questo"}`; `after_solution` = follow `{serve_id, kind: "after_solution"}`; `retry` =
answer the same serve; `back` = the topic page; `contest` = «Per me va bene così»: send the latest try to the teacher. At most three stored tries follow from rows 3 to 8.

In breve: se pensi che la tua risposta sia giusta, premi «Per me va bene così»: la vede il docente. L'esercizio si chiude,
vedi la soluzione e non conta né a favore né contro.

## 4. Atomicity

- **Serve creation**: one transaction (SQLite `BEGIN IMMEDIATE`) reads the student's open serves on the skill
  and inserts only if the item to serve has none (at most one open serve per student, skill and pinned item).
  Two tabs, an outbox retry or a reload get the same serve.
- **Answer**: grade first, outside any transaction; then one short transaction re-derives the serve state,
  refuses with 409 if closed, and inserts the attempt (`try_number` = stored tries + 1) and the grading. The
  unique (`practice_serve_id`, `try_number`) and the unique `client_attempt_id` make a concurrent duplicate fail;
  a repeated `client_attempt_id` returns the stored answer. Expression worker down: HTTP 503
  `{"status":"retry"}`, nothing stored, the outbox resends.
- **Contest**: one transaction writes the contest row, the comment for the teacher and, unless sent, the solution
  event; a second click answers the same.
- **Hint**: the request carries `n`; the event is written only if `n` = shown + 1; `n` at most shown returns
  hint n again; anything else is 422.

## 5. Skill states

Fold per skill over the tries in time order:

- Start: the seed (section 6), else `not_seen`.
- Any try while `not_seen`, `to_recover` or `to_learn` gives `in_study`.
- `in_study` gives `demonstrated` at the first try after which the C_unaided tries cover at least 3 distinct
  fingerprints, with at least 2 of those fingerprints low-guess, on one day or on several
  (`demonstrated_at` = that try's time).
- `demonstrated` gives `consolidated` at a C_unaided try on a fingerprint first served at that serve, at least
  14 days after `demonstrated_at`.
- `demonstrated` or `consolidated` gives `to_review` at a W try that is not aided; it remembers the previous state.
- `to_review` returns to the previous state after 2 C_unaided tries on distinct fingerprints since entering.
- A `contested` try is N: it counts neither way (it is no W, so it never sends a skill to `to_review`).
- Tries on voided item revisions are skipped.

Output per skill: state, since, `demonstrated_at`, `consolidated_at`, seed, counts (serves, tries,
correct_unaided, correct_aided, wrong, typical per code, unrecognised, near_miss, undetermined, hints,
solutions_requested, abandoned, seconds), and `why` (a code and its parameters). Seconds per try run from the
serve (try 1) or the previous try to the answer, capped at `TIME_CAP_SECONDS`.

The topic status for the student: `done` when every skill is `demonstrated` or `consolidated`; `in_progress`
when any try or a `lesson_opened` exists; else `todo`. The tag on a topic shows when a skill is
`to_recover` (the student reads "Dal test: da ripassare") or `to_review` ("Da ripassare"); the first tag of each kind on a page
carries one line saying what it means (D-348).

Days: the loader computes `Try.day` as `answered_at` in Europe/Rome (the dates of the reasons the student reads); the fold
receives dates and never touches a zone. Tests cover the 2026-10-25 change to winter time.

## 6. Seeds and voids

The seed comes from the student's latest non-voided diagnosis run in the subject that is **complete** (trial
students use their own runs). Complete is the sense of the list of tests (`Diagnosis::Conductor#completed?`, D-298,
D-325): the run is closed, or no item is open and the engine either holds the run for pending answers or has nothing
left to ask, so that only the `run_closed` row is missing. A finished test that S never opened again seeds the course
as a closed one does; a pending skill (an answer waiting for the teacher) is not seeded. In breve: ogni test finito
conta, anche se non è stato chiuso.

The seed of each skill:

| Diagnosis state (kind) | Seed | Why the student reads |
|---|---|---|
| demonstrated | `demonstrated`, `demonstrated_at` = the last event of the run (its close; the last item served when only the close row is missing) | "Dimostrata nella diagnosi del %{date}." |
| to_recover (recover) | `to_recover` | "Dal test d'ingresso: da ripassare." |
| to_recover (learn) | `to_learn` | "Nella diagnosi: da imparare." |
| not_assessed, reason `below_demonstrated` | `demonstrated` (implied), same date | "Non serviva verificarla: hai dimostrato un'abilità che la usa." |
| not_assessed (other), pending | no seed | none |

A seeded `demonstrated` consolidates by the same rule. Course skills of the second year have no seed.

Voids: the loader reads the `void_revision_attempts` decisions and drops the official student's practice tries on
those item revisions. The diagnosis derivation is not changed.

## 7. Serving

Input: student, visible topic revision, skill, optional item key `item`, optional follow `{serve_id, kind}`,
`advance`, clock. "Open serves" are the student's open serves on this skill whose item is pinned. **Touched** =
the latest of a serve's creation, its last try and its last draft.

1. `item` (an item key): the item must be pinned on the skill (else 404 `not_pinned`). Its open serve is
   returned as is. Without one: a new serve of that item with its first unseen instance (rule 7), reason `next`;
   none unseen: the instance whose last serve is the oldest, reason `reseen` (a redo the student asked for).
2. `follow`: a candidate whose item has an open serve is skipped, the next candidate is taken (rules 3 and 4).
   Only such candidates left: the open serve of the followed item, else the one touched least recently.
3. `prova_questo` (the followed serve is the student's, closed `wrong` with a typical try of code c on item
   revision R): the first unseen instance of R whose stored errors have c; else of another pinned item of the
   skill; else rule 5 (reason `next`, parent set). Reason `prova_questo`, error code c.
4. `after_solution` (the followed serve had its solution sent): an unseen instance of the same item revision;
   else rule 5 (reason `next`, parent set).
5. `advance` («Avanti», «Salta»): rule 6 over the pinned items WITHOUT an open serve. Every pinned item has an
   open serve: the open serve touched least recently. With nothing asked (the first load of the page): the open
   serve touched most recently, to resume it; no open serve: rule 6.
6. Next: the pinned items of the skill in pin order; the current item is the first with fewer than
   `ADVANCE_AFTER_CORRECT_UNAIDED` C_unaided tries by this student (any revision); when all have them, the item
   served least recently. Pick its first unseen instance; if none, the next pinned item with one.
   **Hard to guess first** (D-390): when the C_unaided tries of the skill, one per fingerprint, leave `DEMONSTRATE_MIN_LOW_GUESS` short and the
   exercises still missing in all are no more than the hard ones missing (every one still to come must be hard to guess), the
   unseen instances taken into account are the hard-to-guess ones (`Practice::Instances.low_guess?`) when any is unseen, and the
   choice runs over them as above. Only the automatic choice (rule 6, not `item`, `prova_questo` or `after_solution`) follows it.
7. "Unseen" = the instance **fingerprint** was never served to this student in practice. Among candidates the
   order is `sha256("#{student_id}:#{fingerprint}")` ascending.
8. **No unseen instance left in the skill** (every instance of every pinned item has been served to this student), on a
   choice the student did not make (no `item`: first load, `advance`, `follow`): nothing is served on its own, as
   version 4 did with `reseen`. The selector records one `PracticePoolExhaustion` row (append-only; unique per student, topic
   revision and skill: a second call, a second tab or a retry add none) and answers `exhausted`; the page says "Hai visto tutti gli
   esercizi di questa abilità. Ne stiamo preparando altri." The list of exercises and «Rifai» stay: choosing an exercise
   is rule 1, which serves its oldest instance with reason `reseen` (its tries are aided; the page says "Questo esercizio
   l'hai già visto: non conta per dimostrare l'abilità."). An open serve of the skill is resumed first (rule 5), as before.
   Not every instance seen, but none unseen outside the items with an open serve: the open serve is resumed.
   The teacher reads the row on the practice page of the subject and as `pool_exhausted_at` of the skill in the practice progress API.
9. The display is re-keyed as in the diagnosis (`Diagnosis::Rekey`, seed per serve).
10. **Same exercise again.** The selector keeps the student on the current item until it has `ADVANCE_AFTER_CORRECT_UNAIDED`
    C_unaided tries (rule 6). When the serve the page shows is of the same item as the previous serve of the skill, was not
    chosen from the list, and the item has fewer of those tries, the page says "Ti propongo un esercizio simile: per passare al
    prossimo ne serve uno giusto." It is a line on the page, not a rule: nothing is stored. With the constant at 1 it shows only after a try that did not count (wrong, aided, a solution).
11. **End of a topic** (D-366). When the topic is `done` (section 5: every skill `demonstrated` or `consolidated`, by the practice or
    by the entry test's seed), `POST /practice/serves` without `item` serves nothing: the reply is `{type: "topic_done"}` and the
    page says "Hai finito questo argomento!", then "Vuoi farne un altro? Eccolo: <title>" with two buttons, one to that topic and one
    "Torna a Oggi". The next topic is the one of `Course::StudentView#next_topic` (what `banco next` gives for the subject); when none is
    left there is no offer, only «Torna a Oggi». It is a screen, not a lock: `item` (the list, «Rifai») still serves an exercise (rule 1)
    and the screen comes back when that exercise is over and he asks for the next. No state, no row and
    no number changes; the screen speaks of the topic only.
12. **Every exercise done, the skill not shown** (D-390). When every exercise of a skill in the list is `done` and the skill is not
    `demonstrated` (its why still names what is missing), the list of exercises of that skill carries `all_done_it`, one line:
    «Hai fatto tutti gli esercizi. Per chiudere ne serve ancora uno giusto da scrivere, abbinare o mettere in ordine (or: senza aiuto):
    premi «Un altro esercizio», ne arriva uno nuovo.» «Hard» when every exercise still to come must be hard to guess (as rule 6). The page
    shows it under the skill's state. No state, no row and no number changes.

In breve: lo studente può saltare un esercizio e tornarci; la scelta dell'esercizio nuovo non tocca quelli lasciati a metà.

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
