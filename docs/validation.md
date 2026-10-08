# Mechanical validation (M5)

What happens between `banco work submit` and the teacher's screen. The codes are in
`config/banco/error_codes.yml`, the numbers in `config/banco/validation_rules.yml`
(its version is stored with every validation), the decisions in `docs/decisions.md`
(D-042 to D-044). Everything here is generic: no student, no programme text.

## The cycle of the content agent

```
banco status                          where each subject stands
banco skill-graph open|submit|coverage --subject KEY
banco blueprint open|submit --subject KEY
banco work open ITEM [--role author|verifier]     writes a folder (item.json, generator.mjs, verify.mjs, assets/)
banco work submit DIR [--dry-run]     new revision; --dry-run validates now and stores nothing
banco work status REV [--wait] [--timeout S]   exit 0 passed, 3 failed (codes on stderr), 6 error or timeout (default 900 s); the status has queue_ahead and current_rules_version
```

Order for a generated item: the author submits `item.json` and `generator.mjs`; the
validation fails with `E-VERIFY-MISSING` but the 24 instances are stored; a verifier
opens the item with `--role verifier` (item, tests, every stored instance with their expected
answers, never `generator.mjs`) and submits `verify.mjs` on the same base; the
validation then passes. After a later author revision the base's `verify.mjs` is carried forward; when it rejects the new seeds the code is `E-VERIFY-STALE` (D-141) and `banco status` counts the item under `awaiting_verifier` (with the first-submit `E-VERIFY-MISSING`), not `failed`; a verifier refreshes it. No command approves anything: the agent stops at
`awaiting_teacher` (firm rule 2).

A submission is **refused with nothing stored** only when it is not a revision: 422
`E-FILES` (unreadable or missing files), 413 `E-TOO-LARGE`, 404 `E-NOT-FOUND`, 409
`E-STALE-BASE`. Anything else is stored as a revision with a validation row:
`passed`, `failed` (never approved) or `error` (Chrome or the grader did not answer:
retried, never a pass). A graph or a blueprint is validated in the request and
refused with 422 and every code when it has an error (they have no validation table).
Files left out of a submission are carried forward from the base revision.

## The phases of an item revision

1. **Schema** (`E-SCHEMA`): `banco.item/1`. A failure stops the run.
2. **Ruby phase** (`ItemChecks`): skills against the graph (`E-SKILL-UNKNOWN`,
   `E-COMPOSITE`, `E-TESTLET-SKILLS`), sources (`E-SOURCE`), assets (`E-ASSET`), `E-ACCENT-POLICY`,
   `E-PROVA-A-PARAMS`, `E-QUOTE-REF`, the readability of every `*_it` text
   (`E-READ` with a rule, `E-PHRASE`, `E-MESSAGE`, the `W-` warnings), and the scan of
   `generator.mjs` and `verify.mjs` (`E-CODE-GLOBAL`: banned globals, network and
   navigation primitives, imports other than the two libraries, external resources).
   A code-scan error means Chrome is not started.
3. **Instances**: listed ones (static items, testlets, the short answer's prompt), or
   generated: seeds 1..200 run in the harness in two fresh Chrome contexts
   (`E-GEN-THROW`, `E-GEN-TIMEOUT`, `E-GEN-SCHEMA`, `E-GEN-NONDETERMINISTIC`,
   `E-GEN-POOL`). The first 24 clean seeds are materialized as `item_instances`
   (append-only, once per revision), even when verify is missing.
4. **Instance checks** on each instance: the key must not reach what the student reads
   (`E-DISPLAY-KEY`, `E-SOLUTION-IN-DISPLAY`, `W-ANSWER-IN-STEM`, `W-MESSAGE-GIVES-KEY`; in a testlet also `W-TESTLET-LEAK`), the size rules of
   choice, ordering and matching, coded distractors, component fit, the solution
   against the key (`E-STEP-INCONSISTENT`), and the supports `answer_format_it` and `steps_it`
   (`E-SUPPORT-LEAK` for the key or a declared error value, `W-STEPS-METHOD`; D-216).
5. **Round trip** (`Roundtrip`): the grader accepts the key, gives each error value its
   own code, treats two error values as different answers, and accepts none of 200
   random well-formed answers (`E-ROUNDTRIP`, `E-ERROR-NEVER-GENERATED`,
   `E-ACCEPTS-RANDOM`).
6. **Verify**: `verify` accepts every clean seed and rejects the catalogue error values
   and the +1 and sign-flip mutants (`E-VERIFY-MISSING`, `E-VERIFY-REJECTS`,
   `E-VERIFY-VACUOUS`). Verify runs on every clean seed of the 200, not only the 24 stored; the
   `E-VERIFY-REJECTS` detail lists all rejected seeds, the reasons and `first_rejected` (the display and answer of the first one), `rejected_samples` (up to 8 rejected instances with reason, display, answer and `in_stored_pool`, false for a seed `work open --role verifier` did not list), and `details.verify`
   reports `checked` and `rejected` (dry run included).

`E-VERIFY-AUTHOR` and `E-SESSION-NOT-INDEPENDENT` are the submit-time rules of the next
section; they refuse a submission and store nothing.

## Sessions, independence, review and blind solve (M6)

Every write of the content cycle carries `X-Banco-Session`: the CLI sends the id in
`BANCO_SESSION`, which `banco session new --role R --agent A --model M --id` prints. A
session has one role (author, verifier, reviewer, solver, grader) and declares its model;
`config/banco/providers.yml` maps models to families. The rules guard against mistakes,
not against intent: the model is declared, not proven.

- `work submit`: only a verifier session adds or changes `verify.mjs`
  (`E-VERIFY-AUTHOR`, also in a dry run); a verifier sends nothing else; an author's
  resubmission carries `verify.mjs` forward unchanged. `item_revisions.file_sessions`
  records who wrote each file as it stands.
- `work open --role verifier` (the session's role decides) never returns `generator.mjs`.
- The sessions that authored `item.json` or `generator.mjs`, the verifier, the reviewer
  and the solver of one item are disjoint (`E-SESSION-NOT-INDEPENDENT`), and a second
  round of review or solve uses a session that did not see the first.
- Reviewer and blind solver: a model different from the model of every author session (the family may be the same, D-070);
  grader: Claude only (`E-PROVIDER-NOT-ALLOWED`). Reviewer and solver receive item
  text only; the grader reads the student's answers.
- `banco review open|submit REV`: `review open` also reads without a session (D-158); `banco.review/1` with the 11-point checklist. Refused:
  evidence that says nothing, repeated or under 4 words (`E-REVIEW-EMPTY`), a fail
  without a finding, a quote that is not an exact substring of the item text or of the
  instance it names (`E-QUOTE-NOT-FOUND`). The item text is item.json, the instances
  shown (every stored instance for the reviewer, D-133; the blind solver gets 8 of a generator item) and the programme lines the skill cites.
- `banco solve open|submit REV`: display-only instances; the server grades with the
  student's graders. A disagreement is a blocker finding `E-BLIND-SOLVE-MISMATCH`; a
  `dont_know` is a major one; a short answer is recorded and not graded.
- Findings are append-only. Their dispositions are decisions of the teacher
  (`dispose_finding`, M9b). `Review::Gate.approvable?(revision)`: validation passed, a
  review and a blind solve on the exact revision, every blocker and major finding
  disposed, none of them as `fix_requested`.
- Short answers: `banco submissions --pending --json` (grader session) and
  `banco grade propose ATTEMPT --file grade.json`: rubric points exactly once, integer
  scores, quotes that are exact substrings of the student's text after normalization
  (`E-QUOTE-NOT-FOUND`), no grader that authored the item (`E-GRADER-IS-AUTHOR`).
  A proposal counts only after a `confirm_grade` decision (M9a/b).

## Chrome and the harness

Agent code runs only in Chrome (firm rule 3). In production Chrome is the
`banco-chrome` sidecar: `BANCO_CHROME_HOST` is resolved to an IP before Ferrum
connects, one browser context per run is disposed in `ensure`, and a reaper disposes
the contexts that no live run owns. Test, development and CI launch a local Chrome
(`BROWSER_PATH`) with Ferrum's `ignore_default_browser_options` and curated flags
(never `--disable-web-security`). Every use goes through `ChromeRunner`'s shared
`flock` (`tmp/chrome.lock`); a dry run waits for it up to 25 s
(`BANCO_DRY_RUN_CHROME_WAIT`) and answers 409 `E-CHROME-BUSY` when it is still taken.

Chrome loads `/h/<run-token>/harness.html` from the harness listener (port 3200,
internal): a cookie-less page with a CSP that allows no connection, no image and no
frame, holding no token and no secret. `Math.random`, `Date`, `performance.now` and
`crypto` throw inside it. The run token is an HMAC bound to a stored revision or to
the staged files of a dry run, valid for 10 minutes. `BANCO_HARNESS_URL` says where
Chrome reaches the listener (`http://banco-harness:3200` in production).

## Tests

`bin/rails test test/validation/` (every `E-` and `W-` code has a fixture in
`code_fixtures_test.rb`; the good fixture passes with 24 instances),
`bin/rails test test/validation/cli_fixtures_test.rb` (the compiled CLI against the
API listener), `node --test 'lib/harness/test/*.test.mjs'`. Chrome tests skip when
`BROWSER_PATH` is not set. `contract/examples/` is written by the integration tests
with `UPDATE_CONTRACT=1`; CI runs them and fails on a dirty diff.

Generator `tests` (D-078, D-080): `must_accept`, `must_reject` and `blank` run on the first stored instance, which is the first clean seed (seed 1 unless seed 1 throws or is rejected; `banco work submit --dry-run` lists the instances); keep `must_accept` empty when the key changes with the seed. E-ACCEPTS-RANDOM ignores a random expression that equals the key in value. A listed instance may carry its own `tests` (`must_accept`, `must_reject`, D-085) for its own `accept`; an instance may also carry `accept` (D-081, normalized_text) for variants that depend on the seed, e.g. `didn't go` / `did not go`; skill-graph `*_it` texts get `W-GRAPH-READABILITY` when an item would fail E-READ.

## The author answers the findings (D-220)

After a review or a blind-solve round the author answers every blocker and major finding with `banco findings respond ID --file response.json`: `item_right` with a short proof, or `fixed` with the later revision that fixes it. `banco findings list --subject S --open` lists what is left. The teacher reads the key, the solver's raw answer and the author's note on the skill screen, then decides. A response never disposes of a finding.
