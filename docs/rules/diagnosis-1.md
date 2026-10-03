# Diagnosis rules, version 1 (`diagnosis/1`)

Regole della diagnosi d'ingresso, versione 1.

This note is the prose of the rules the engine applies. The numbers live in
`lib/diagnosis/rules/v1.rb` (`Diagnosis::Rules::V1`); a test fails when the two
drift apart (`test/lib/rules_v1_test.rb`). Every diagnosis run records
`rules_version`. A change to a constant bumps the version, and runs already made
keep the version they were made under. The note is generic: it describes one
student, a teacher who is also the operator, and eleven subjects. Facts about a
real student never go in this repository.

Ogni sezione ha una riga in italiano per il docente: «In breve». Il testo
completo e di riferimento è in inglese, come il codice.

Decision ids (X-, A-, B-, C-, E-) refer to the decision register of the design;
operator answers are D-entries in `docs/decisions.md`.

## 1. Words with one meaning

- **Outcome (esito)**: what the grader says about one answer: correct, typical
  error, wrong, "I do not know", wrong form, near miss, undetermined, invalid.
- **State (stato)**: what the engine says about one skill: `demonstrated`,
  `to_recover`, `not_assessed`, `pending`, each with a reason (section 7).
- **Entry test** (code: blueprint): the starting skills and the items chosen for
  one subject. The words "entry" alone is never used: say "starting skill".
- **Evidence**: each graded answer weighs as one of three pieces: **C** credit,
  **W** wrong, **D** "I do not know". Not to be confused with the operator's
  grading option C (hybrid); that is only the name of the choice.

In breve: esito = risultato di una risposta; stato = risultato di un'abilità;
test d'ingresso = abilità di partenza e item di una materia.

## 2. From the outcome to the evidence (X-03, X-04)

`Rules::V1::EVIDENCE` maps the latest machine grading, or a teacher's
`resolve_attempt`, to evidence. Error codes come from one registry,
`config/banco/error_codes.yml`, in snake_case; a name that differs between the
grader and the rules would switch a mask off in silence.

| Outcome | Evidence |
| --- | --- |
| correct (choice, ordering, matching by id; exact rationals; exact normalized text; expressions by an exact method) | **C** |
| typical_error(code) | **W**, with the code |
| ORTHOGRAPHY_SLIP: the grader says typical_error with a code in `ORTHOGRAPHY_ALLOWLIST` (`es_accents`, `it_accents`, `it_apostrophe_accent`) and the item says `accent_policy: flag` (it does not measure accents). The grader has already ruled out a slip whose unaccented form is one of the item's `paradigm_forms`: that is another word, so wrong. With `accent_policy: strict` the item measures accents and the slip is **W** | `ORTHOGRAPHY_SLIP = :credit`: **C** on the item's skill plus an observation on the orthography skill, no descent |
| wrong, certain | **W**, unclassified |
| dont_know ("Non lo so", "Non l'ho ancora studiato") | **D**, never shown to the student as wrong |
| wrong_form where the form is the skill itself (reduce, factor, expand) | **W** |
| wrong_form declared in the item with a `form_skill` different from the item's skill and inside its prerequisite closure | `WRONG_FORM_DECLARED = :credit`: **C** on the item's skill plus `form_skill` as a tail suspect |
| wrong_form not declared | pending |
| near_miss: 5 or more characters, one Damerau edit from an accepted answer, item with `spelling_policy: near`, colliding with no declared wrong answer | `NEAR_MISS = :pending`: pending, and another instance is served meanwhile |
| undetermined, or the float method | pending |
| short answer | pending until `confirm_grade` |
| ungraded (grader stopped or slow) | **not an outcome yet**: it counts as soon as a retry appends a grading with a certain verdict; after the last failed retry it goes to the teacher as `verdict_pending` |
| invalid (blank, unreadable, ambiguous exponent, ambiguous mixed number or digits separated by a space, dot decimal where not allowed, empty box) | not an attempt: Italian message, `app_event invalid_input` |

The three named constants `NEAR_MISS`, `WRONG_FORM_DECLARED` and
`ORTHOGRAPHY_SLIP` each take `:credit` or `:pending`. Their defaults are the
operator's recommended defaults for Q10 (a one-letter typo goes to the teacher; a
right value in an undeclared form is credited with an observation; an accent or
apostrophe slip where spelling is not measured is credited with an observation).
Changing one bumps `rules_version`. Language-form items (Spanish, English,
Italian spelling) use `spelling_policy: exact`; numbers are always exact.

Invariants, each with a test: *pending* and *ungraded* count neither way for the
descent; no path leads from an uncertain outcome to `demonstrated` without a
teacher decision row; outcomes recorded after a skill has resolved are logged but
ignored. Uncertainty always resolves away from `demonstrated`: a false
"demonstrated" hides a gap until the exam.

In breve: il certo vale subito; l'incerto (refuso, forma non dichiarata,
espressione indecisa, risposta breve) va al docente; un guasto del correttore non
è un esito e si ritenta.

## 3. Sequencing, stopping and guessing per skill (B-02)

The rule is applied to each skill on that skill's items only.

- Item 1 is **low-guess** (server-derived: `number`, `fraction`, `expression`,
  `normalized_text`, `ordering` of 4 or more, `matching` of 4 or more pairs),
  unless the skill has a `choice_only_reason` the teacher reads. Item 2 is a
  different item where the pool has one, otherwise an unseen instance.
- **D on item 1** gives `to_recover(dont_know)`. A D later counts as W.
- **C C** gives `demonstrated(two_of_two)`, or `two_of_two_choice` when both were
  choice (weaker: phase 2 maps it to "in study" with one credit).
- **W W** gives `to_recover(two_wrong)`.
- **Mixed** (one C, one W): a third low-guess unseen item. `demonstrated
  (two_of_three)` needs C on it and at least one low-guess C, otherwise
  `to_recover(mixed)`. With no low-guess item available the state is
  `to_recover(mixed)`.
- **Pending or ungraded** answers are not outcomes: another instance is served, up
  to `MAX_SERVED_PER_SKILL` (5) served per skill. At the cap with answers
  outstanding the state is `pending`.
- **Testlets** (a reading passage with 5 closed sub-items) are served as one unit.
  Each sub-item is an attempt on its own skill. At most one outcome per skill per
  testlet counts toward a pair (`TESTLET_OUTCOMES_PER_SKILL = 1`); the second must
  come from another item, because two answers on one passage are correlated
  evidence. The time budget is checked before serving a testlet, using its
  `expected_seconds`.
- Choice options are shuffled by seed with key-position balance across the
  session; the shown order is logged; ids are compared, never positions.

Why these numbers (computed once, by a script, from the rule): a learner who knows
the skill and slips 1 time in 10 on typed items is `demonstrated` with probability
0.972 (strict two-of-two would send 19% of them to `to_recover`). A guesser with
four options passes a naive best-of-3 15.6% of the time; with this rule 6.25% when
the first item had to be a choice, and 0% when item 1 is typed.

In breve: due giuste dimostrano, due sbagliate no, una e una chiede un terzo item
non indovinabile; l'item 1 non si indovina; un brano conta una prova per abilità.

## 4. Descent, composite skills, cross-subject reuse (B-03)

- The frontier starts as the blueprint's ordered entries (starting skills).
- Descent happens **only when a skill resolves to `to_recover`**. The targets are
  the `implicates` of its typical errors, plus all direct prerequisites if any
  outcome was W unclassified or D. Targets go to the head of the frontier
  (depth-first).
- Never below a demonstrated skill. A prerequisite implicated on a demonstrated
  skill goes to the tail as a suspect.
- A skill's state comes only from its own items.
- **Composite skills**: a multi-step item whose catalogue implicates 2 or more
  distinct prerequisites must belong to a composite skill listing them
  (`E-COMPOSITE`), so a notable-products bug does not mislabel a
  linear-equation skill.
- **Cross-subject**: a target already resolved in any non-voided run is reused;
  otherwise `not_assessed(cross_subject_unavailable)`, reported as a check. There
  are no visits to other subjects during a sitting; the subject order makes the
  owner subject go first.
- **Guest starting skills**: an entry test may list as a starting skill a skill of
  an approved graph of another subject (`guest_of_subject`). Its result goes to the
  owner subject and is reused as above. The teacher sees it in the entry test.
- **Gate on learn chains** (a decision of this note): a starting skill whose
  prerequisite in the same subject is already `to_recover` with kind `learn` is not
  served; it ends `not_assessed(prerequisite_to_recover)`. Reason: asking about
  fractional equations after the student has not yet seen factoring measures nothing
  and tires the student. A newer approved revision of the entry test lifts it.
- Flat subjects run the same engine as a fixed form; the report says "test a forma
  fissa".
- **Scope**: `in_progress` and `not_in_prima` skills follow the same rule; their
  item-1 button reads "Non l'ho ancora studiato" (D), and the descent goes into
  in-scope prerequisites, never into an in-progress block.

In breve: si scende solo da un'abilità da recuperare, verso gli errori che
indicano la causa, mai sotto un'abilità dimostrata; una catena da imparare non si
interroga oltre il primo anello mancante.

## 5. Stopping (B-03, B-05)

`Rules::V1::END_REASONS` = `frontier_empty`, `time_budget`, `item_cap`,
`teacher_close`. They are checked **between serves**. `MAX_ITEMS_PER_SITTING` is
30 and ends a sitting with `item_cap`.

## 6. Time: budget, sittings, short-answer reserve, daily caps (B-05, B-12, Q11)

- No timer on screen. The counted time of an item is `min(answered_at - served_at -
  paused - hidden, ITEM_CAP_SECONDS)`, with `ITEM_CAP_SECONDS` = 600 (a testlet caps
  at `TESTLET_CAP_SECONDS` = 1200). Pause and visibility events are posted only on
  change; a request every 10 minutes while the page is visible keeps the session
  alive. An item left open for `ABANDON_GAP_SECONDS` (1800) is logged
  `item_abandoned` and a fresh instance of the same skill is served.
- **Sitting budget** (`SITTING_BUDGET_MINUTES`): **30 minutes for mathematics, 25
  for every other subject**. `OPEN_RESERVE_MINUTES` is 7.
- **Second sitting, automatic** (operator decision Q11; `SITTINGS_PER_SUBJECT = 2`,
  `AUTO_SECOND_SITTING = true`): when the budget is reached and skills remain to
  explore, the subject continues in a second sitting, from the next calendar day,
  up to 60 minutes in total for mathematics and 50 for the others. The student's
  total time is about 6 to 10 hours. When the last allowed sitting reaches the
  budget with an unresolved frontier, the run closes with `time_budget`. The
  teacher can extend (`extend_diagnosis_run`, one more sitting) or close
  (`close_diagnosis_run`).
- **Short answer** (one per discursive subject): served at the earlier of "frontier
  empty" and "budget minus `OPEN_RESERVE_MINUTES`". If a sitting ends before it was
  served and another sitting exists, it is the first item of that sitting. If the run
  closes without it, its skill is `not_assessed(time_budget)`.
- **Daily caps** (default, changeable): at most `DAILY_MAX_SUBJECTS` = 2 subjects and
  `DAILY_MAX_MINUTES` = 75 counted minutes a day, in dependency order, mathematics
  first. Two first sittings use at most 55 minutes; the 75 is a safety ceiling.
- The subject is final when the run closes; solutions appear only then. The
  warm-up is outside the budget and outside the log of runs.
- **Dependencies** (`depends_on_subjects`): a subject can start when the first
  sitting of each dependency is closed.

In breve: 30 minuti per matematica e 25 per le altre; la seconda seduta parte da
sola se restano abilità da esplorare (fino a 60 o 50 minuti); al massimo 2 materie
e 75 minuti al giorno.

## 7. States and reasons (B-04)

Four states, each with a reason enum (`Rules::V1::REASONS`):

- `demonstrated`: `two_of_two`, `two_of_two_choice`, `two_of_three`,
  `short_answer_above_threshold`.
- `to_recover`: `dont_know`, `two_wrong`, `mixed`, `short_answer_below_threshold`.
- `not_assessed`: `below_demonstrated`, `time_budget`, `item_cap`, `not_needed`,
  `cross_subject_unavailable`, `no_unseen_items`, `voided`, `not_started`,
  `prerequisite_to_recover`.
- `pending`: `grade_unconfirmed`, `verdict_pending` (uncertain, or ungraded after
  the last retry), `grader_unavailable` (retries still running; resolves without the
  teacher if a retry grades it certainly).

"Inferred" exists only as `not_assessed(below_demonstrated)` and never counts.

Phase 2 mapping: `two_of_two` and `two_of_three` become "dimostrata" (via the
diagnosis, first review within about 7 study days); `two_of_two_choice` and
`short_answer_above_threshold` become "in studio" with one credit; `not_assessed`
becomes "non vista".

In breve: quattro stati, ognuno con il suo motivo; «non valutata» non è un
giudizio.

## 8. Recover or learn, and scope (B-01, B-04)

- `kind` is `learn` for scope `in_progress` and `not_in_prima`, and `recover` for
  `studied`, `integration_studied` and **`middle_school`**. `middle_school` (skills
  from lower school, such as signed numbers or unit conversions) is `recover`:
  without that scope a lower-school prerequisite would be labelled "not in the prior
  year" and the student would read "to learn" about things already seen. It carries a
  `scope_reason_it` and no prior-year citations (`E-SCOPE`).
- The blueprint's `kind_overrides[]` (`{skill, kind, reason_it}`) change one skill,
  for example when a block in progress has been finished.
- What each reader sees:

| State and scope | The student reads | The teacher reads |
| --- | --- | --- |
| `to_recover`, recover | "Da riprendere" | to revisit, with the observed error |
| `to_recover`, in progress | "Da imparare" | expected gap: integration still in study |
| `to_recover`, not in the prior year | "Da imparare" | to teach: new topic |
| `not_assessed`, in progress | counted in "Non te l'abbiamo chiesto" | not assessed: integration in progress |
| `demonstrated`, any scope | "Sai già fare" | demonstrated, with the reason |

- The in-progress marker is a scope on the skill, not a new state; there is no
  "in study" state in the diagnosis (that name belongs to phase 2).
- Only in-progress blocks that are a direct prerequisite of a first-term topic of
  the next year are measured; the others sit in the graph and end
  `not_assessed(not_needed)`.

In breve: «da riprendere» solo per ciò che è stato studiato (anche alle medie);
«da imparare» per ciò che è in corso o nuovo.

## 9. Short answers (B-06)

Exactly one per discursive subject (Italian, English, Spanish, history, geography,
law and economics, biology). A rubric `points[{id, weight 1-3, expected_it}]` (at
least 2), `threshold` (default `SHORT_ANSWER_DEFAULT_THRESHOLD` = 0.6) and
`model_answer_it`. State `pending(grade_unconfirmed)` until the teacher confirms,
then `demonstrated(short_answer_above_threshold)` or
`to_recover(short_answer_below_threshold)`, with evidence 1. The model answer is
never shown before confirmation. The proposal of the agent never counts by
itself.

## 10. Calculator (operator decision)

`CALCULATOR`: **no** in mathematics, **yes** in business and chemistry, said in the
items ("Puoi usare la calcolatrice"); `W-CALCULATOR` flags a numeric item that
lacks the sentence. In the other subjects the numbers are chosen for hand
calculation. The entry test carries a `calculator` field and the start screen shows
one line about it. Changeable at approval.

## 11. Skill keys and pools

- A skill key is `<subject>.<kebab-slug>`, for example
  `math.linear-equation-integer` (`Rules::V1::SKILL_KEY_PATTERN`). Subject keys:
  `math`, `italian`, `english`, `spanish`, `history`, `geography`,
  `law_economics`, `business`, `computer_science`, `biology`, `chemistry`. The short
  prefixes of the skill inventory map through `INVENTORY_PREFIXES`: mat, it, hist,
  geo, eng, es, inf, che, bio, eca, dir.
- Pools: generators give 24 clean seeds of 1..200; a static item has at least 2
  instances. For redo, each skill of an entry test has at least 6 distinct instances
  over at least 2 items, 3 of them low-guess (`E-POOL-REDO`), or declares
  `redo_reserve: false`.
- Entry tests have 4 to 10 starting skills (`E-BLUEPRINT-ENTRIES`; the design said
  4 to 8, see `docs/decisions.md`).
- **The descent pool is pinned** (D-038, which resolves D-034): the blueprint's
  required `descent[]` has, for every skill the descent can reach from the
  starting skills (`Plan#descent_targets`: parents and the implicates of typical
  errors, transitively, same subject, never an `in_progress` skill itself), either
  `{skill, items[]}` or `{skill, not_assessed_reason_it}`; a reachable skill that is
  in neither is `E-BLUEPRINT-UNPINNED-DESCENT`. The engine serves only pinned
  items, so everything the student sees went through the teacher's approval of the
  blueprint (firm rule 2). A skill declared not assessed is not asked and ends
  `not_assessed(no_unseen_items)`; the teacher reads the reason.

## 12. Changing these rules

A rule changes only with a new `rules_version` and an entry in
`docs/decisions.md`. Lessons from the first wave of content become version 2 of the
briefs (`briefs/*.md`), not edits of version 1.

## 13. The engine, the log and the dry run (M8)

The engine is a pure fold: `Diagnosis::Engine.next_action(plan, events, clock)`
and `Diagnosis::Derivation.result(plan, events)` read a **plan** (the pinned
blueprint, the skill graph, the pool of instances, what other runs resolved and
what the student has seen) and a **list of events**, and use no database, no
random source and no wall clock. `Diagnosis::PlanLoader`, `EventLoader` and
`RunAdapter` (in `app/models/diagnosis/`) are the only code that reads rows.
`Diagnosis::Simulator` plays a `ScriptedStudent` on a `FakeClock` against the same
engine; `banco diagnosis simulate` is that, over the API, with no writes.

Events (a hash with `kind`, `at`, `seq`): `sitting_started`, `sitting_closed
{reason}`, `run_closed {reason}`, `item_served {instance}` (its `seq` is the serve
id), `answered {serve, verdict, error_code?, orthography_slip?, form?, form_skill?,
retry_state?}`, `grading` (a later grading, same keys), `resolve_attempt {serve,
verdict}`, `confirm_grade {serve, passed}`, `item_abandoned {serve}`, `paused`,
`resumed`, `hidden`, `visible`, `extend_diagnosis_run`, `close_diagnosis_run`.
Decision rows reach the log with these payloads: `resolve_attempt {attempt_id,
verdict, error_code?}`, `confirm_grade {attempt_id, passed}`,
`extend_diagnosis_run {run_id}`, `close_diagnosis_run {run_id}`,
`void_diagnosis_run {run_id}` (every skill of that run becomes
`not_assessed(voided)` and its results are no longer reused) and
`void_revision_attempts {item_revision_id}` (the answers on that revision leave the
log).

How the fold reads the rules above:

- An answer becomes an **outcome** the first time it is certain (C, W or D), in the
  order of the log. Once a skill resolves, later outcomes are logged and ignored.
  A `resolve_attempt` on an answer that had already counted is applied in place, at
  the position of the original answer.
- **Descent** (section 4) never goes into a skill whose scope is `in_progress`, into
  a skill below a demonstrated one (the transitive prerequisites and composite
  parts of a demonstrated skill, a suspect excepted), or into a skill of another
  subject, which is reused when resolved there and is
  `not_assessed(cross_subject_unavailable)` otherwise. The tail suspects are the
  implicates of the typical errors seen on a demonstrated skill and the declared
  `form_skill` of a credited wrong form.
- The **gate on learn chains** applies to starting skills only, by the direct
  prerequisites of the same subject (a prerequisite that is itself gated counts).
- **Per-skill cap**: after `MAX_SERVED_PER_SKILL` serves, or with no unseen
  instance, a skill that is unresolved ends `pending` if answers are outstanding,
  `not_assessed(item_cap)` or `not_assessed(no_unseen_items)` otherwise. A mixed
  pair with no unseen low-guess instance left ends `to_recover(mixed)`.
- **Next item**: the head of the frontier, the instance chosen by a hash of the
  run's `seed_salt`, the skill and the instance fingerprint (no random state), so a
  run replays exactly. A testlet is chosen only when its `expected_seconds` fit in
  the sitting's remaining time minus `OPEN_RESERVE_MINUTES`.
- **Closing**: `frontier_empty` is checked first (the short answer is served last),
  then `item_cap`, then `time_budget`, always between serves. A run never closes
  `frontier_empty` while an answer of it is pending or ungraded and its skill is
  not resolved (a retry or the teacher can still settle it): the engine answers
  `wait` (reason `pending_answers`), the derivation says `waiting_on:
  pending_answers`, and the close comes after the resolution. The teacher can
  always close the run (`close_diagnosis_run`). A short answer awaiting
  `confirm_grade` holds the run in the same way. With another sitting
  allowed (`SITTINGS_PER_SUBJECT`, `AUTO_SECOND_SITTING`, plus one per
  `extend_diagnosis_run`) the answer is `end_sitting` and the next sitting may start
  from the next calendar day; otherwise `close_run`. An `extend_diagnosis_run` after
  a run closed on `time_budget` or `item_cap` reopens it. A `close_diagnosis_run`
  closes it for good (`teacher_close`).
- **Daily caps** are `Diagnosis::DailyPlan`, a pure function over the facts of each
  subject: waiting for a dependency, continuing tomorrow, or full for today
  (`DAILY_MAX_SUBJECTS`, `DAILY_MAX_MINUTES`), in dependency order with mathematics
  first. Every sitting records `condition: unsupervised`.

In breve: il motore è una funzione pura sul registro; `simulate` lo fa girare su un
alunno a copione senza scrivere nulla.
