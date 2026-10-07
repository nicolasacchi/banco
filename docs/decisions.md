# Decisions

Every deviation from the design and every answer of the operator is recorded here, as a new entry. Entries are added, never rewritten: a changed decision gets a new entry that supersedes the old one.

Entry format: `## D-NNN · date · title`, then Design ref, Design said, We do, Why, Cost, Status, Back-port.

## Index

| Id | Date | Title | Status |
|---|---|---|---|
| D-001 | 2026-10-02 | operator G · diagnosis grading is hybrid | decided |
| D-002 | 2026-10-02 | operator Q1 · release all together | decided |
| D-003 | 2026-10-02 | operator Q2 · no daily teacher budget | decided |
| D-004 | 2026-10-02 | operator Q11 · automatic second sitting | decided |
| D-005 | 2026-10-02 | operator Q5 · Authelia with second factor and a cookie-only endpoint | decided |
| D-006 | 2026-10-02 | operator Q6 · production steps and the secret in .env | decided |
| D-007 | 2026-10-02 | operator Q7 · local-only backups | decided |
| D-008 | 2026-10-02 | operator Q8 · other-family reviewer and blind solver, grader on Claude | decided |
| D-009 | 2026-10-02 | operator Q9 · English names for routes, users and hosts | decided |
| D-010 | 2026-10-02 | operator Q4 · no supervision | decided |
| D-011 | 2026-10-02 | operator Q10 · near-miss answers | decided (changeable) |
| D-012 | 2026-10-02 | operator days · daily limits | decided (changeable) |
| D-013 | 2026-10-02 | operator calculator · calculator policy | decided (changeable) |
| D-014 | 2026-10-02 | operator Q3 · facts about the programmes (open) | open (defaults in force) |
| D-015 | 2026-10-03 | public repo hygiene | decided |
| D-016 | 2026-10-03 | three listeners and edge trust by address | implemented in M1 (placeholders for /diagnosis, /teacher, /api/v1/schema) |
| D-017 | 2026-10-03 | Rails skeleton without Solid Cache, Solid Cable and Active Storage | implemented in M1 |
| D-018 | 2026-10-03 | Go CLI: standard library, module at the repository root | implemented in M1 (commands: version, schema) |
| D-019 | 2026-10-03 | names in English | implemented in M1 |
| D-020 | 2026-10-03 | CI runs the tests natively | open |
| D-021 | 2026-10-03 | deferred question: which Visual Basic | deferred |
| D-022 | 2026-10-03 | public repo hygiene: no programme file in the repository | implemented in M2 |
| D-023 | 2026-10-03 | M2 ledger shape: every table append-only, item_served as a detail table | implemented in M2 |
| D-024 | 2026-10-03 | programme import: origin tagging, sub-line addresses, Constitution source | implemented in M2 |
| D-025 | 2026-10-03 | M3 frozen formats: schema members, entry counts, fixtures shipped in the image | implemented in M3 |
| D-026 | 2026-10-03 | M3 briefs: names, front matter and the brief endpoint | implemented in M3 |
| D-027 | 2026-10-03 | M3 rules note: gate on learn chains, guest skills, skill keys, Q11 constants | implemented in M3 |
| D-028 | 2026-10-03 | M3 agent tokens: api_tokens reshaped to D-05 | implemented in M3 |
| D-029 | 2026-10-03 | M4 expression worker: promoted checker, vendored engine, protocol and limits | implemented in M4 |
| D-030 | 2026-10-03 | M4 how an answer reaches the grader: raw encodings, "Non lo so", id map | implemented in M4 |
| D-031 | 2026-10-03 | M4 what a grading row carries: inverted pairs, give-up marker, retry schedule | implemented in M4 |
| D-032 | 2026-10-03 | M4 closed graders: text policies, form violation names, number input | implemented in M4 |
| D-033 | 2026-10-03 | M8 engine shape: Plan, Fold, Engine, Derivation and the event vocabulary | implemented in M8 |
| D-034 | 2026-10-03 | M8 pool: descent targets draw on the subject's passed items | resolved: descent items pinned (D-038) |
| D-035 | 2026-10-03 | M8 readings of the rules where the register is silent | implemented in M8 |
| D-036 | 2026-10-03 | M8 simulate: bundle format, flat bare blueprint, --subject, scripts | implemented in M8 |
| D-037 | 2026-10-03 | M8 adapter approximations to revisit when the item and grader code lands | open |
| D-038 | 2026-10-03 | M5 descent pool pinned: banco.blueprint/1 gains a required descent | implemented in M5 |
| D-039 | 2026-10-03 | M5 a run waits while an answer is pending or ungraded | implemented in M5 |
| D-040 | 2026-10-03 | M5 ORTHOGRAPHY_SLIP: the rules note follows the code (accent_policy flag) | implemented in M5 |
| D-041 | 2026-10-03 | M5 banco.item/1 gains optional case_sensitive | implemented in M5 |
| D-042 | 2026-10-03 | M5 validation pipeline: job, harness, Chrome, retries, stored columns | implemented in M5 |
| D-043 | 2026-10-03 | M5 readings of the A-06 codes where the register is silent | implemented in M5 |
| D-044 | 2026-10-03 | M5 the content agent's API and CLI: submit semantics, folders, status stages | implemented in M5 |
| D-045 | 2026-10-03 | M10 serve-time re-keying: ids, seeds, redraws and replay | implemented in M10 |
| D-046 | 2026-10-03 | M10 which blueprint a run is pinned to, who can start, what "released" means | implemented in M10 |
| D-047 | 2026-10-03 | M10 testlet instances: stored shape, one attempt, aggregated verdict | implemented in M10 (question for the operator) |
| D-048 | 2026-10-03 | M10 the outbox in localStorage, resend, and what "Accedi di nuovo" does | implemented in M10 |
| D-049 | 2026-10-03 | M10 delivery of the student's pages: own importmap, CSP, figures by digest | implemented in M10 |
| D-050 | 2026-10-03 | M10 the warm-up: where it lives, how it is graded, when the editor is given up | implemented in M10 |
| D-051 | 2026-10-03 | M10 end-of-subject screen, solutions, and the flag | implemented in M10 |
| D-052 | 2026-10-03 | M10 the verify commands as Rails 8.1 runs them | implemented in M10 |
| D-053 | 2026-10-03 | Integration: a run held open for pending answers in the student's pages | implemented in the M5 and M10 merge |
| D-054 | 2026-10-03 | M6 sessions: integer ids, X-Banco-Session, roles and where the rules sit | implemented in M6 |
| D-055 | 2026-10-03 | M6 providers.yml: families by pattern, per-role rules | implemented in M6 |
| D-056 | 2026-10-03 | M6 expert review and blind solve: what is checked, what is stored | implemented in M6 |
| D-057 | 2026-10-03 | M6 the gate approvable? and awaiting_teacher | implemented in M6 |
| D-058 | 2026-10-03 | M6 grade proposals: codes, normalization, pending lists | implemented in M6 |
| D-059 | 2026-10-03 | M9a DecisionRecorder, its guards and the decision routes | implemented in M9a |
| D-060 | 2026-10-03 | M9a approval gates and what a run pins | implemented in M9a |
| D-061 | 2026-10-03 | M9a release, consent, kind_override and confirm with edits | implemented in M9a |
| D-062 | 2026-10-03 | M9a bin/reconcile-decisions reads the ledger only | implemented in M9a, proxy log later |
| D-063 | 2026-10-03 | M9b the teacher's screens, Rimanda and the measured minutes | implemented in M9b |
| D-064 | 2026-10-03 | M9b the report (B-09): shape, no student text in the API | implemented in M9b |
| D-065 | 2026-10-03 | M9b banco health and bin/preflight | implemented in M9b, host measures with M7 |
| D-066 | 2026-10-03 | M9b Atkinson Hyperlegible and the student's theme and size | implemented in M9b |
| D-067 | 2026-10-03 | M9b structure.sql check and the Chrome lock test | implemented in M9b |
| D-068 | 2026-10-03 | M9b how the teacher's forms decide and word refusals | implemented in M9b |
| D-069 | 2026-10-03 | review fixes: privacy of the list, image and log; engine and grading corrections | implemented |
| D-070 | 2026-10-04 | operator Q8-bis · reviewer and blind solver need another model, not another family | implemented |
| D-071 | 2026-10-04 | agent sessions are bound to their token; token roles limit session roles | implemented |
| D-072 | 2026-10-04 | production host authorization | implemented |
| D-073 | 2026-10-04 | audit lows: seq in the transaction, thousands, Unicode variants, punctuation keys, counted abandon, mixed at the cap | implemented |
| D-074 | 2026-10-04 | reference texts: agents list and read, the operator imports | implemented |
| D-075 | 2026-10-04 | partial exclusions, per-line coverage detail, inherited block markers, W-SCOPE-MARKER | implemented |
| D-076 | 2026-10-04 | a form that is the item's own skill carries its first violation as the error code | implemented |
| D-077 | 2026-10-04 | solution items accept an inequality (x < a) as the answer and as typical errors | implemented |
| D-078 | 2026-10-04 | generator items run tests; leak scan folds exponent braces and product dots | implemented |
| D-079 | 2026-10-04 | `isolate` form (letter = expression) and `exclude_params` on banco.item/1 | implemented |
| D-081 | 2026-10-04 | per-instance `accept`; item prompt in the leak scan; W-FORM-SKILL-CLOSURE; E-MATCHING-RIGHT-MARKUP | implemented |
| D-082 | 2026-10-05 | step consistency reads LaTeX decimal commas; teacher skill page renders solution markup | implemented |
| D-083 | 2026-10-05 | W-ANSWER-IN-STEM ignores a key inside a «quoted» sentence; brief on accent_policy and per-instance accept | implemented |
| D-084 | 2026-10-05 | W-NEGATIVE-STEM ignores «quoted» and $math$ spans; CLI reports a missing contract header as E-NETWORK | decided |
| D-085 | 2026-10-05 | per-instance `tests`; W-GRAPH-READABILITY | implemented |
| D-086 | 2026-10-05 | matching: each answer once (hint and greyed-out entries) | implemented |
| D-087 | 2026-10-05 | W-ERROR-NOT-IN-GRAPH; an ordering is never shown as a declared error permutation | implemented |
| D-088 | 2026-10-05 | passage_it on short_answer is shown everywhere; allowed on diagnosis_item | implemented |
| D-089 | 2026-10-05 | fingerprints ignore stored order and ids of shuffled columns (validation rules v2); end-of-subject message from the item that erred | implemented |
| D-090 | 2026-10-05 | source kind legal_text; brief says which instance tests run on | implemented |
| D-091 | 2026-10-05 | deferred_prerequisites and deferred_implicates: cross-subject edges that wait for approval; banco --help | implemented |
| D-092 | 2026-10-05 | matching as a classification (`display.reuse_right`); generator `tests` confirmed already run | implemented |
| D-093 | 2026-10-05 | graph findings per skill; 2-category classification; number `accept` and form `scientific` | implemented |
| D-094 | 2026-10-05 | testlet passage in the leak scan; `da solo` is not an absolute word | implemented |
| D-095 | 2026-10-05 | binary profile reports declared errors; arrows and spreadsheet function names pass the readability lint | implemented |
| D-096 | 2026-10-05 | testlet low-guess and choice per skill; accent-slip observation skill; graph `notes_it` | implemented |
| D-097 | 2026-10-05 | a dry run waits up to 25 s for Chrome before E-CHROME-BUSY | implemented |
| D-098 | 2026-10-05 | a testlet is charged as a serve to its first skill only; its sub items must share one skill (E-TESTLET-SKILLS) | implemented |
| D-099 | 2026-10-05 | one instance of a testlet item per run; a bare blueprint dry run loads the pinned graph and items | implemented |
| D-100 | 2026-10-05 | E-VERIFY-REJECTS names every rejected seed with its reason; the dry run reports the verify phase | implemented |
| D-101 | 2026-10-05 | the blueprint's intro_note_it, not_measured_it, calculator and per-skill flags are shown | implemented |
| D-102 | 2026-10-05 | amounts with the Italian thousands dot | implemented |
| D-103 | 2026-10-05 | thousands with spaces are `thousands_separator`; an instance `display.unit` overrides the item unit | implemented |
| D-104 | 2026-10-05 | DDT in caps_allowlist (rules v4); `--help` anywhere in the CLI line | implemented |
| D-105 | 2026-10-05 | E-PHRASE matches banned phrases on word boundaries | implemented |
| D-106 | 2026-10-05 | `calculation: false` exempts counting items from W-CALCULATOR | implemented |
| D-107 | 2026-10-05 | the number unit suffix matches after NFKC (`cm3` = `cm³`); content-agent reports on generator tests and per-instance unit were already done | implemented |
| D-108 | 2026-10-05 | content-agent reports (english): tests run on the first clean seed, per-instance accept exists, it_accents is the code for any non-Spanish accent slip; documented, no code change | implemented |
| D-109 | 2026-10-05 | under accent_policy flag a declared error typed without its accent still hits it (spanish report); tests of generator items already run (D-078) | implemented |
| D-112 | 2026-10-05 | testlet units carry the typical error codes of their sub items; the Italian lint skips passage_it and model_answer_it in english and spanish (rules v5) | implemented |
| D-113 | 2026-10-05 | binary answers written in groups of bits ("1110 1100") are read as one string | implemented |
| D-114 | 2026-10-05 | binary profile: a declared error value written exactly (padding_missing) is a typical error, not wrong_form; plain normalized_text bit/letter codes typed with spaces are `invalid` (`spaces_in_code`); CS acronyms in caps_allowlist (rules v6); generator tests already run | implemented |
| D-115 | 2026-10-05 | `work open` warns inside a git work tree; cloze pages repeating a form use D-092 `reuse_right` | implemented |
| D-116 | 2026-10-05 | binary profile: a declared error value that is not a bit string (1121) is a `typical_error`, not `invalid`; undeclared non-bit answers stay `invalid` | implemented |
| D-117 | 2026-10-05 | W-SCOPE-MARKER reads the stars inside the cited fragment first (a line with several ☆ fragments has no line marker); matching as a 3-category classification already exists (D-092) | implemented |
| D-118 | 2026-10-05 | a table cell (header or row) may be the empty string, for spreadsheet grids; arrows already pass the lint in every `_it` field (D-095) | implemented |
| D-119 | 2026-10-05 | `work open --role verifier` returns every stored instance (the whole pool of 24), not the first 8 | implemented |
| D-120 | 2026-10-05 | `banco items list`: the revisions of a subject's items with status and a current marker | implemented |
| D-121 | 2026-10-05 | W-SHORT-SKILL-CLOSED: closed items pinned beside a short answer are never served and leave the redo pool count; the teacher's traces confirm pending and short answers | implemented |
| D-122 | 2026-10-05 | `banco work submit --dry-run` repeats itself on E-CHROME-BUSY (6 times, 10 s apart) | implemented |
| D-123 | 2026-10-05 | `work status` says `retrying` while an error row awaits its retry | implemented |
| D-124 | 2026-10-05 | `E-VERIFY-REJECTS` shows up to 8 rejected instances | implemented |
| D-125 | 2026-10-05 | a ref's programme section is shown and checked (`W-REF-OTHER-SUBJECT`); items the blueprint does not pin are a derived reserve | implemented |
| D-126 | 2026-10-05 | the short answer is indicative by definition | decided |
| D-127 | 2026-10-05 | the whole arrows block is allowed in `*_it` text | implemented |
| D-128 | 2026-10-05 | W-TESTLET-LEAK: a sub-item key in the passage or in another sub-item | implemented |
| D-129 | 2026-10-06 | guest skills from a draft graph (W-GUEST-UNAPPROVED); `items list` carries what a blueprint pins | implemented |
| D-130 | 2026-10-06 | a pending testlet answer holds its skill: no further testlet until it is settled | implemented |
| D-131 | 2026-10-06 | a testlet that does not fit the sitting is deferred to the next one, not replaced by a repeat of the item already used | implemented |
| D-132 | 2026-10-06 | reviewers: `items list` already lists revision ids; own scratch directory per subject and round | implemented |
| D-133 | 2026-10-06 | `review open` lists every stored instance of a generator item | implemented |
| D-134 | 2026-10-06 | `items list --subject` accepts keys with an underscore (computer_science) | implemented |
| D-135 | 2026-10-06 | `round_to` on a number error; item implicates into another subject's draft graph; ready marker on deferred edges | implemented |
| D-136 | 2026-10-06 | a pinned item revision that a newer passed revision replaced is `W-STALE-PIN` | implemented |
| D-137 | 2026-10-06 | `skill-graph coverage` lists the error codes of passed items that the graph lacks | implemented |
| D-138 | 2026-10-06 | the blueprint's item order decides which item is served first; a star block survives short bullets | implemented |
| D-139 | 2026-10-06 | W-SCOPE-MARKER reads a star just before the cited fragment; `banco work open` defaults to `$TMPDIR/banco-work/ITEM` | implemented |
| D-140 | 2026-10-06 | `banco work open --role verifier` gets its own default folder and refuses the other role's folder | implemented |
| D-141 | 2026-10-06 | `E-VERIFY-STALE`: a carried-forward verify.mjs that rejects a changed item is the verifier's to refresh; `banco status` has `awaiting_verifier` | implemented |
| D-142 | 2026-10-06 | a star block ends at a short heading after a finished sentence; W-SCOPE-MARKER counts unmarked lines; descent item order is kept | implemented |
| D-143 | 2026-10-06 | W-REF-OTHER-SUBJECT is quiet when the skill's scope_reason_it names the line number | implemented |
| D-144 | 2026-10-06 | W-TESTLET-MULTI-SKILL: a pinned testlet stored with sub items on several skills is warned and refused at approval | implemented |
| D-145 | 2026-10-06 | W-ERROR-UNREACHABLE: a matching error value that repeats a right-hand id can never fire and is warned | implemented |
| D-146 | 2026-10-06 | `diagnosis simulate` warns W-STALE-PIN for each stale pin it serves | implemented |
| D-147 | 2026-10-06 | `banco status` counts passed items validated under older rules (`older_rules`) | implemented |
| D-148 | 2026-10-06 | the programme's star markers (U+2605, U+2606) are not emoji for the readability rule | implemented |
| D-149 | 2026-10-06 | W-RULES-OUTDATED names pinned revisions that passed under older rules (blueprint dry run, status) | implemented |
| D-150 | 2026-10-06 | a carried-forward verify.mjs that accepts wrong answers is E-VERIFY-STALE (awaiting_verifier), not E-VERIFY-VACUOUS | implemented |
| D-152 | 2026-10-06 | graph and blueprint submits record the author session and refuse an invalid session header; --agent accepts parentheses | implemented |
| D-153 | 2026-10-06 | with a sidecar Chrome the harness URL defaults to banco-harness, and banco health probes Chrome-to-harness | implemented |
| D-154 | 2026-10-06 | an identical resubmission of a revision that passed under older rules is validated again under the current rules | implemented |
| D-155 | 2026-10-06 | a dotted abbreviation (a.C., d.C., m.c.m.) counts as one word in the readability rules | implemented |
| D-151 | 2026-10-06 | skill-graph coverage follows the engine for testlets (first skill) and lists stored multi-skill testlets | implemented |
| D-156 | 2026-10-06 | the reuse_right widget label says answer, not category | implemented |
| D-157 | 2026-10-06 | `items list` and `work status` show `awaiting_verifier` like `banco status` | implemented |
| D-158 | 2026-10-06 | `review open` reads without a session | implemented |
| D-159 | 2026-10-06 | `blueprint open` returns the submittable document | implemented |
| D-160 | 2026-10-06 | `work status` shows the queue and the current rules version; `--wait` waits 900 s; identical dry runs are cached | implemented |
| D-161 | 2026-10-06 | an author dry run whose only findings are E-VERIFY-MISSING or E-VERIFY-STALE answers 200 `awaiting_verifier` | implemented |
| D-162 | 2026-10-06 | `banco health` shows `validation_queue.waiting` | implemented |
| D-163 | 2026-10-06 | the solve brief carries a complete `banco.solve/1` example | implemented |
| D-164 | 2026-10-06 | brief session examples use the placeholder AGENT | implemented |
| D-165 | 2026-10-06 | E-REVIEW-EMPTY names the rule each weak point failed | implemented |
| D-166 | 2026-10-06 | the solve brief states the testlet and short_answer answer shapes | implemented |
| D-167 | 2026-10-06 | the review brief tells reviewers to allocate a unique scratch directory | implemented |
| D-168 | 2026-10-06 | the solve brief says a short_answer takes a sample answer, not `dont_know` | implemented |
| D-169 | 2026-10-06 | the solver and reviewer see the item prompt (an ordering's direction) | implemented |
| D-170 | 2026-10-06 | E-SCHEMA says in plain words what a wrong constant or non-string root member must be | implemented |
| D-171 | 2026-10-06 | W-MESSAGE-GIVES-KEY: an error message that states an instance's key | implemented |
| D-172 | 2026-10-06 | `blueprint open` shows `awaiting_verifier` in items[] like `banco status` | implemented |
| D-173 | 2026-10-06 | the solve brief says one submit per session and what `--dry-run` is for; no retraction | implemented |
| D-174 | 2026-10-06 | solver answer-format complaints: the stem names the format; `isolate` already accepts `y = expr` | implemented |
| D-175 | 2026-10-06 | solver sees no question on an instance: D-169 already shows the prompt; otherwise a content mistake | implemented |
| D-176 | 2026-10-06 | solve brief root fields: already in the brief since D-166; no change | implemented |
| D-177 | 2026-10-06 | reviewer scratch collision: already in the review brief since D-167; no change | implemented |
| D-178 | 2026-10-06 | review open: programme_lines also list the lines the item's own sources cite, with cited_by | implemented |
| D-179 | 2026-10-06 | solver display of an ordering item: the prompt (direction) is already shown (D-169) | implemented |
| D-180 | 2026-10-06 | solve brief root fields of answers.json (biology report): already documented (D-166, D-176); no change | implemented |
| D-181 | 2026-10-07 | work status and work open (author) carry review_findings: the reviewers' and blind solvers' findings | implemented |
| D-182 | 2026-10-07 | solve brief root fields of answers.json (biology, solve1:3): already documented (D-166, D-176, D-180); no change | implemented |
| D-183 | 2026-10-07 | solve brief on short_answer and author view of review findings: already shipped (D-168, D-181); no change | implemented |
| D-184 | 2026-10-07 | solve/review display: item prompt already shown (D-169); a testlet's sub items now carry their prompt; blueprint open status already D-172 | implemented |
| D-185 | 2026-10-07 | solve open without stem_it (law_economics): prompt stem shown since D-169; answers.json root already documented (D-180, D-182); no change | implemented |
| D-186 | 2026-10-07 | resets on first submits were a production restart (deploy); ordering direction and brief envelope already shipped (D-169, D-180); no change | implemented |
| D-187 | 2026-10-07 | testlet answer shape in the solve brief already shipped (D-166); no change | implemented |
| D-188 | 2026-10-07 | unique scratch folder (D-167), transient E-NETWORK and unreachable matching errors (D-145, D-147) already covered; no change | implemented |
| D-189 | 2026-10-07 | `solo` as "single" after a noun (un giorno solo) is not an absolute word; the author already reads review findings (D-181) | implemented |
| D-190 | 2026-10-07 | solver prompt.stem_it already shipped (D-169, D-184); transient connection reset on the API was a restart; no change | implemented |
| D-191 | 2026-10-07 | solve brief root fields (italian, solve1:1): already documented with a minimal example (D-166, D-176); no change | implemented |
| D-192 | 2026-10-07 | review brief states the evidence minimum (4 words, no stock phrase); seconda:224 on italian.complements is a content mistake, not a defect | implemented |
| D-193 | 2026-10-07 | solve brief root fields (chemistry, solve2:0): same as D-191, already documented; no change | implemented |
| D-194 | 2026-10-07 | W-ERROR-UNREACHABLE also reads pair-list error values; the warning is in `work submit` output, not the review dry-run | implemented |
| D-195 | 2026-10-07 | solve brief root fields (subject history, solve1:0): third repeat of D-191; no change | implemented |
| D-196 | 2026-10-07 | solve brief root fields and testlet shape (history, solve1:1): fourth repeat of D-191; no change | implemented |
| D-198 | 2026-10-07 | review brief: evidence on absence points needs the fields read (example added) | implemented |
| D-199 | 2026-10-07 | solve brief root fields (history, solve1:2): fifth repeat of D-191; no change | implemented |
| D-200 | 2026-10-07 | blind solve on a short_answer and solve brief root fields (history, solve1:3): already shipped (D-168, D-183, D-191); no change | implemented |
| D-201 | 2026-10-07 | solve brief root fields and testlet answer shape (english, solve2:0): sixth repeat of D-191; already documented; no change | implemented |
| D-202 | 2026-10-07 | solve brief root fields (spanish, solve2:0): seventh repeat of D-191; already documented; no change | implemented |
| D-203 | 2026-10-07 | `banco work open` prints review_findings and teacher_comments (the CLI dropped them); W-REF-OTHER-SUBJECT reads a range N-M in scope_reason_it | implemented |
| D-204 | 2026-10-07 | solve brief root fields and testlet shape (geography, solve2:0): eighth repeat of D-191; already documented; no change | implemented |
| D-205 | 2026-10-07 | solve brief root fields (math, solve2:0): ninth repeat of D-191; already documented; no change | implemented |
| D-206 | 2026-10-07 | `items list`: an older revision that would read `awaiting_verifier` reads `superseded` | implemented |
| D-207 | 2026-10-07 | `solve open` of a superseded revision is E-STALE-BASE; the hint names `solve open LATEST` (also `review`); root fields and ordering direction need no change | implemented |
| D-208 | 2026-10-07 | W-ACCEPT-ITEM-LEVEL: item-level accept not within one edit of every instance key | implemented |
| D-209 | 2026-10-07 | `review open` adds `current` and `superseded_by`; `next` says a superseded revision cannot be filed and names the latest | implemented |
| D-210 | 2026-10-07 | `solve open` adds `file_root`: the root keys of answers.json, `revision` a string (english, solve3:0; tenth repeat of D-191) | implemented |
| D-211 | 2026-10-07 | `review open` may be read with the item's own author session; the solve brief lists short_answer in its Format (history, pfix1; repeat of D-168, D-183) | implemented |
| D-212 | 2026-10-07 | author reads review findings: already shipped (D-181, D-203) as `review_findings`; the key is not `findings` and not `teacher_comments`; no change (math, pfix2) | implemented |
| D-213 | 2026-10-07 | solve brief root fields (law_economics, solve3:0): repeat of D-195; the brief has the four keys and a complete example; no change | implemented |
| D-214 | 2026-10-07 | operator decision: the calculator is allowed in mathematics too; W-CALCULATOR not extended to mathematics | implemented |
| D-215 | 2026-10-07 | operator request: all the questions of a test on one page; approve by confirming they were seen; close the preview | implemented |
| D-216 | 2026-10-07 | operator request: more instructions in the test, steps and answer format on items, the formula sheet as a declared support | implemented |
| D-217 | 2026-10-07 | operator request: trial students, two teachers who act, one guest who only reads | implemented |

## D-001 · 2026-10-02 · operator G · diagnosis grading is hybrid

- **Design ref:** Operator answer to the review panel's questions
- **Design said:** Answers are graded by the agent, or by the browser.
- **We do:** Option C: only what is certain is graded immediately (choice, ordering and matching by id, exact numbers and fractions, exact normalized text). Uncertain answers (expressions the checker cannot settle, short answers) go to the evening: the agent proposes, the teacher confirms. Table Rules::V1::EVIDENCE.
- **Why:** The agent never decides alone and the student gets instant feedback where it is safe.
- **Cost:** An evening review step for uncertain answers.
- **Status:** decided
- **Back-port:** The design pages predate this answer; none yet updated.

## D-002 · 2026-10-02 · operator Q1 · release all together

- **Design ref:** Operator answer to the review panel's questions
- **Design said:** Release in waves.
- **We do:** The student starts when all 11 subjects are approved; the Diagnosis screen shows every subject at once. release_diagnosis requires 11 approved subjects.
- **Why:** A uniform experience was preferred over earlier starts.
- **Cost:** The start date depends on teacher approval time.
- **Status:** decided
- **Back-port:** The design pages predate this answer; none yet updated.

## D-003 · 2026-10-02 · operator Q2 · no daily teacher budget

- **Design ref:** Operator answer to the review panel's questions
- **Design said:** A daily cap on teacher time.
- **We do:** No cap: show everything, the teacher handles it. Approval must be efficient; the opening date is computed from the measured pace (teacher_minutes).
- **Why:** The teacher prefers to see everything and then work through it.
- **Cost:** None beyond the stated behaviour.
- **Status:** decided
- **Back-port:** The design pages predate this answer; none yet updated.

## D-004 · 2026-10-02 · operator Q11 · automatic second sitting

- **Design ref:** Operator answer to the review panel's questions
- **Design said:** A single sitting per subject.
- **We do:** A second sitting starts automatically while skills remain to explore: up to 60 minutes in total for mathematics and 50 for the others, in blocks of 30 and 25. SITTINGS_PER_SUBJECT = 2, AUTO_SECOND_SITTING = true.
- **Why:** Better coverage of the skill graph without a manual step.
- **Cost:** Total student time of roughly 6 to 10 hours.
- **Status:** decided
- **Back-port:** The design pages predate this answer; none yet updated.

## D-005 · 2026-10-02 · operator Q5 · Authelia with second factor and a cookie-only endpoint

- **Design ref:** Operator answer to the review panel's questions
- **Design said:** Basic and Bearer pass on every protected route today.
- **We do:** TOTP and WebAuthn; a forward-auth endpoint that accepts only the session cookie; rules teacher = two_factor and student = one_factor; the student user only in the student group; one restart outside study hours; password and TOTP seed out of reach of the agent. Decision routes stay off until the operator's proofs pass.
- **Why:** The decision routes are protected by identity, so the identity gate must be strong.
- **Cost:** A restart that logs everyone out of every site.
- **Status:** decided
- **Back-port:** The design pages predate this answer; none yet updated.

## D-006 · 2026-10-02 · operator Q6 · production steps and the secret in .env

- **Design ref:** Operator answer to the review panel's questions
- **Design said:** A secret file materialized from the password manager.
- **We do:** DNS record, router and middleware, a dedicated edge network with the proxy at a fixed address, up --no-deps, deploy freeze during sittings. The single secret goes in .env like the other applications; the password manager stays the source.
- **Why:** Consistency with the other applications on the host.
- **Cost:** The value is visible in docker inspect, as for the other applications.
- **Status:** decided
- **Back-port:** The design pages predate this answer; none yet updated.

## D-007 · 2026-10-02 · operator Q7 · local-only backups

- **Design ref:** Operator answer to the review panel's questions
- **Design said:** Off-site copies.
- **We do:** Nightly sqlite3 .backup with rotation, local only; the host backup excludes the data directory and the copies. No student data leaves the house.
- **Why:** Privacy of the student's data.
- **Cost:** Accepted risk: a disk failure loses the ledger.
- **Status:** decided
- **Back-port:** The design pages predate this answer; none yet updated.

## D-008 · 2026-10-02 · operator Q8 · other-family reviewer and blind solver, grader on Claude

- **Design ref:** Operator answer to the review panel's questions
- **Design said:** Same provider for everything.
- **We do:** The reviewer and the blind solver run on a model from a different family than the author and receive only the item text; the answer grader runs on Claude. Rules in config/banco/providers.yml.
- **Why:** Independence of the review; the student's answers stay with the provider already in use.
- **Cost:** None beyond the stated behaviour.
- **Status:** decided
- **Back-port:** The design pages predate this answer; none yet updated.

## D-009 · 2026-10-02 · operator Q9 · English names for routes, users and hosts

- **Design ref:** Operator answer to the review panel's questions
- **Design said:** Italian route names.
- **We do:** /diagnosis, /teacher, /teacher/grades, user student, a pages host in phase 1b. Texts for the student and the teacher stay Italian.
- **Why:** Firm rule 6.
- **Cost:** None beyond the stated behaviour.
- **Status:** decided
- **Back-port:** The design pages predate this answer; none yet updated.

## D-010 · 2026-10-02 · operator Q4 · no supervision

- **Design ref:** Operator answer to the review panel's questions
- **Design said:** A supervised sitting.
- **We do:** Sittings are unsupervised; each sitting records condition: unsupervised and the report shows it. There is no record_sitting_condition decision.
- **Why:** The student works alone.
- **Cost:** None beyond the stated behaviour.
- **Status:** decided
- **Back-port:** The design pages predate this answer; none yet updated.

## D-011 · 2026-10-02 · operator Q10 · near-miss answers

- **Design ref:** Operator answer to the review panel's questions
- **Design said:** All near misses are wrong.
- **We do:** (a) A one-letter typo in a written answer goes to the teacher. (b) A right value in a form the measured skill does not ask for earns credit on the item skill plus an observation, only when the form is a declared separate skill. (c) An accent or apostrophe slip when the item does not measure spelling earns credit plus an observation. NEAR_MISS = :pending, WRONG_FORM_DECLARED = :credit, ORTHOGRAPHY_SLIP = :credit.
- **Why:** Recommended default accepted; fair measurement of the intended skill.
- **Cost:** A change raises rules_version.
- **Status:** decided (changeable)
- **Back-port:** The design pages predate this answer; none yet updated.

## D-012 · 2026-10-02 · operator days · daily limits

- **Design ref:** Operator answer to the review panel's questions
- **Design said:** No limit.
- **We do:** At most 2 subjects and about 75 counted minutes a day, in dependency order, mathematics first. Engine constants DAILY_MAX_SUBJECTS = 2 and DAILY_MAX_MINUTES = 75; two first sittings use at most 55 minutes.
- **Why:** Recommended default accepted.
- **Cost:** A slower start.
- **Status:** decided (changeable)
- **Back-port:** The design pages predate this answer; none yet updated.

## D-013 · 2026-10-02 · operator calculator · calculator policy

- **Design ref:** Operator answer to the review panel's questions
- **Design said:** No policy.
- **We do:** No calculator in mathematics, yes in business economics and chemistry, stated in the items; a calculator field in the entry test and a line on the start screen; lint W-CALCULATOR flags a missing sentence.
- **Why:** Recommended default accepted.
- **Cost:** Per-subject wording in items.
- **Status:** decided (changeable)
- **Back-port:** The design pages predate this answer; none yet updated.

## D-014 · 2026-10-02 · operator Q3 · facts about the programmes (open)

- **Design ref:** Operator answer to the review panel's questions
- **Design said:** Unknown.
- **We do:** Open question. Until answered, prudent defaults: a marked line means not yet studied; a marker on one line covers only the next line and the following lines are flagged to the teacher; factoring, algebraic fractions and fractional or literal equations are 'to learn'; a foreign-language report counts as the programme, flagged on the graph. Corrected at approval with kind_override.
- **Why:** The programme files do not settle these points.
- **Cost:** Wrong defaults cost a correction at approval.
- **Status:** open (defaults in force)
- **Back-port:** The design pages predate this answer; none yet updated.

## D-015 · 2026-10-03 · public repo hygiene

- **Design ref:** E-08, brief step 2 (programme files in db/syllabus/)
- **Design said:** Only prep/ stays out of git; the first-year programme is copied into db/syllabus/ and imported by the production seed.
- **We do:** The repository is public. Nothing about the student or the household is committed: no real name, school, city, exam session or programme files. prep/ is git-ignored and never committed. Both programmes are imported from files outside the repo (locally from prep/; in production by the operator with docker compose exec -T banco bin/rails banco:syllabus:import SOURCE=... FILE=- < file). Tests use small synthetic programmes under test/fixtures/syllabus/. The real-programme verify is a local rake task; tests that need prep/ skip with a clear message when it is absent, so CI passes without it. bin/hygiene (run by CI) fails when git ls-files prep is non-empty, when a forbidden term is found (the list lives in that script) or when a programme file is tracked. Documents describe the software generically (one student, the teacher/operator).
- **Why:** A public repository must not leak a minor's data, and CI must be reproducible without private material.
- **Cost:** The real-programme check cannot run in CI; the production seed no longer carries the first-year programme.
- **Status:** decided
- **Back-port:** Brief step 2 and the E-08 artifact list: the first-year programme is not copied into db/syllabus/.

## D-016 · 2026-10-03 · three listeners and edge trust by address

- **Design ref:** D-02, D-04; design page 05 'Deploy e accesso'
- **Design said:** Two listeners; user identity trusted by container address.
- **We do:** One Puma with three binds, WEB_PORT 3000, API_PORT 3100, HARNESS_PORT 3200 (never PORT). Banco::ListenerTag tags each request from the accepted socket's local port (env["puma.socket"]), never from request.port or Host; the test seam env["banco.test_listener"] is honoured only in the test environment. Remote-User and Remote-Groups are read with get_header only when remote_addr is inside BANCO_EDGE_PROXY (a single address) and the request came on the web listener; remote_ip is never used; trusted_proxies is that address only (or a never-matching value when unset). A comma in Remote-User is a 400. The teacher role needs group banco-teacher and a login in BANCO_TEACHER_USERS. Every route group is a 404 on the other listeners.
- **Why:** The host has an address on every bridge, so a wide network trusts the host and the agent; remote_ip trusts a forged X-Forwarded-For.
- **Cost:** A third listener and a constraint on every route group.
- **Status:** implemented in M1 (placeholders for /diagnosis, /teacher, /api/v1/schema)
- **Back-port:** Design 04 and 05: describe three listeners and trust by the proxy address.

## D-017 · 2026-10-03 · Rails skeleton without Solid Cache, Solid Cable and Active Storage

- **Design ref:** E-01; design page 05 'Lo stack'
- **Design said:** Solid Cable and Active Storage in phase 1a.
- **We do:** rails new with the skip flags, then Solid Cache and Solid Cable removed; cache_store :memory_store; Solid Queue in its own database, production paths under BANCO_DATA_DIR (primary and queue only); schema_format sql for the primary database (schema.rb loses triggers) and ruby for queue. json_schemer is in the default group because production validates E-SCHEMA. Active Storage and Action Cable are deferred (E-09).
- **Why:** Single node, single process; fewer moving parts and files to back up.
- **Cost:** None known.
- **Status:** implemented in M1
- **Back-port:** Design 05 stack list.

## D-018 · 2026-10-03 · Go CLI: standard library, module at the repository root

- **Design ref:** E-05; design page 05 'Lo stack' (cobra), page 04 'La CLI'
- **Design said:** A cobra-based CLI with an idempotency key.
- **We do:** Standard library only, table-driven dispatch, first positional lifted before flag parsing. go.mod (module banco) sits at the repository root and contract/ is a small Go package that go:embeds commands.json, because go:embed cannot reach outside a package directory; the CLI lives in cli/ and is built with go build -o bin/banco ./cli. X-Banco-Contract carries the sha256 of the contract file, not only its version, so any drift is caught. Errors are {code, field, message, next} on stderr; exits 0, 2, 3, 4, 5, 6. The token comes from BANCO_TOKEN or a pass-cli read with a 5 second timeout.
- **Why:** Zero dependencies and exact drift detection.
- **Cost:** go test is run from the repository root or cli/; both find the module.
- **Status:** implemented in M1 (commands: version, schema)
- **Back-port:** Design 04 and 05.

## D-019 · 2026-10-03 · names in English

- **Design ref:** E-07 (see operator Q9)
- **Design said:** Italian paths such as /oggi and /docente.
- **We do:** Routes, keys, identifiers and comments are English; Italian texts live in config/locales/it.yml under English keys; keys that hold Italian text end in _it.
- **Why:** Firm rule 6.
- **Cost:** None.
- **Status:** implemented in M1
- **Back-port:** Design 05 'Il layout del codice'.

## D-020 · 2026-10-03 · CI runs the tests natively

- **Design ref:** E-02
- **Design said:** CI builds the same Dockerfile with a test target that adds the headless shell.
- **We do:** CI uses ruby/setup-ruby with the version from .ruby-version, actions/setup-go and actions/setup-node, and the runner's Chrome for system tests (BROWSER_PATH). The Dockerfile is built by a separate job to prove it still builds. There is no Docker test target yet.
- **Why:** Faster feedback and a cached bundle; the production image stays free of test tooling.
- **Cost:** The test environment and the image can drift; the image build job limits that.
- **Status:** open
- **Back-port:** E-02.

## D-021 · 2026-10-03 · deferred question: which Visual Basic

- **Design ref:** brief 'Domande aperte'
- **Design said:** Ask the operator which Visual Basic the school course uses.
- **We do:** Deferred to phase 1b: it is second-year content and no entry-diagnosis skill depends on it.
- **Why:** The question does not block phase 1a.
- **Cost:** None in 1a.
- **Status:** deferred
- **Back-port:** Brief open questions.

## D-022 · 2026-10-03 · public repo hygiene: no programme file in the repository

- **Design ref:** brief 'I programmi e la Costituzione in produzione' (prima in db/syllabus/); B-08 programme sources
- **Design said:** The prima programme lives in db/syllabus/ and the production seeds import it; the seconda stays in prep/.
- **We do:** The repository became public after the brief was written, so neither programme is committed. Both are imported from files outside the repo: locally from prep/, in production by the operator with `docker compose exec -T banco bin/rails banco:syllabus:import SOURCE=... FILE=- < file`, then the same with banco:syllabus:verify. Tests use small synthetic programmes under test/fixtures/syllabus/. The test that checks the real programmes skips with a message when the files are absent (CI). bin/hygiene refuses tracked programme files and forbidden terms.
- **Why:** The programmes describe one student and the school; the repository is public.
- **Cost:** The production seeds do not create the programme sources; the operator imports them once. The prima sha256 is verified by the import itself.
- **Status:** implemented in M2
- **Back-port:** Brief 'infrastruttura'; B-08.

## D-023 · 2026-10-03 · M2 ledger shape: every table append-only, item_served as a detail table

- **Design ref:** B-08, A-01, X-01, B-07, D-08, E-09; review finding on schema_migrations
- **Design said:** item_served is an event kind of diagnosis_events; triggers on every table.
- **We do:** Triggers (BEFORE UPDATE and BEFORE DELETE, RAISE(ABORT,'append-only')) on every table of the primary database except schema_migrations, ar_internal_metadata and sqlite_sequence; the list is read from sqlite_master in the test. Things that change are modelled as new rows: item_validations (a revision never changes), api_token_revocations, attempt_gradings (seq). item_served is a table linked one-to-one to its diagnosis_events row (kind item_served), holding skill, shown order and id map, so the key-bearing id map never sits in a free-form payload; attempts.served_event_id points to the event and is unique. attempts.context also allows 'warmup' (review finding on the warm-up) and then has no served event. Tables added beyond the brief's M2 list: students (S and preview, seeded), items, item_validations, reference_texts. Not yet created: skills, comments, reviews, findings, submissions, grades, verdict_proposals, student_flags (later milestones). Seeds insert missing rows and never update.
- **Why:** The log cannot change; state that changes needs rows of its own.
- **Cost:** Deferred tables arrive with later migrations. Reading 'current status' is always a query over the latest row.
- **Status:** implemented in M2
- **Back-port:** B-08 and E-09 in the design.

## D-024 · 2026-10-03 · programme import: origin tagging, sub-line addresses, Constitution source

- **Design ref:** B-07 citations, FACTS (transcriber lines, sub-line address); brief 'La Costituzione'
- **Design said:** origin pdf|transcript; sub-line address such as 412:A3; the Constitution text from an official source such as the Senate.
- **We do:** A line is a newline-terminated physical line; a file without a final newline is refused. Origin is decided by generic rules: blank lines, a preamble (when the file opens with a '# ' title, everything up to the first '---'), '## ' headings, a single italic line, '**Pagina N**' markers and '> [Figura:' placeholders are transcript (never cited); the rest is pdf; 'operator' is reserved for lines added by hand. syllabus_lines.marker keeps a leading star marker (★, ☆, ★☆). parts_json holds sub-line addresses A1, A2... for the cells of a table row and for lines with several '•' items. Importing identical text again is a no-op; a different text under an existing key is refused. The Constitution (arts. 1-12) comes from governo.it (Presidenza del Consiglio), because senato.it answers automated requests with a bot challenge; the URL, fetch date and sha256 are in db/syllabus/costituzione-artt-1-12.source.yml and checked by the seed.
- **Why:** Rules that do not depend on one file keep the importer testable on synthetic fixtures.
- **Cost:** Inline markers inside a line (a ☆ mid-line) are not addressable yet; the graph milestone can extend parts_json.
- **Status:** implemented in M2
- **Back-port:** B-07 and the brief's M2 verify (prima is verified from prep/, not db/syllabus/).

## D-025 · 2026-10-03 · M3 frozen formats: schema members, entry counts, fixtures shipped in the image

- **Design ref:** A-03, A-05, A-06 (E-BLUEPRINT-ENTRIES), B-07, C-01, E-01 (json_schemer), brief 'La validazione meccanica'
- **Design said:** banco.skill_graph/1, item/1, blueprint/1, review/1, solve/1 with schema_version; a blueprint has 4-8 entries (brief proposal: 4-10); json_schemer is a production gem; a production-env boot test validates one good and one bad fixture.
- **We do:** Schemas in config/banco/schemas/<name>.json (JSON Schema 2020-12, additionalProperties false at every object level), loaded by Banco::Schemas (lib/banco/schemas.rb) with json_schemer, which is in the default Gemfile group. Every document carries `schema: "banco.<name>/1"` and `schema_version: 1`; a change after authoring starts means /2 plus a draft migration. Blueprint entries are 4-10 (the brief's proposal, because the inventory has up to 10 core skills in mathematics and Italian). The blueprint schema has no simulate traces: they are computed and stored by the server, not authored. Item kinds are diagnosis_item, short_answer, testlet (no warmup, no hints); a testlet has exactly 5 sub_items; `blank` in tests is the constant "invalid". Skill refs name a syllabus source by key (pattern) so the schema does not know the programmes. Fixtures (synthetic, generic) live in test/fixtures/content/<name>/{good,bad}/; `Banco::Schemas.validate_fixture_pair` checks the first good and the first bad file of every schema, and .dockerignore re-includes test/fixtures/content so the same check runs in the production image.
- **Why:** The formats freeze before the content agents write; one source of fixtures serves the tests and the production boot check.
- **Cost:** A few KB of test fixtures in the image. Rules that need the programme or the database (E-SOURCE, E-SCOPE, E-NEEDED-BY, E-POOL-REDO) are not in the schema; they are validation codes of M5 and later.
- **Status:** implemented in M3
- **Back-port:** A-03, A-06 (4-10), B-07 and the brief's M3 row.

## D-026 · 2026-10-03 · M3 briefs: names, front matter and the brief endpoint

- **Design ref:** C-03, brief 'Regole per chi scrive', E-05
- **Design said:** briefs/diagnosis-item.md, skill-graph.md, review.md, blind-solve.md, grading.md, served by `banco brief show KIND`.
- **We do:** Six briefs at version 1 in briefs/: diagnosis-item, skill-graph, blueprint, review, solve, grade (blueprint is added because the entry test has its own format; blind-solve and grading are named solve and grade, after their formats and commands). Each file starts with front matter (name, version, formats); Brief (app/models/brief.rb) serves {name, version, sha256, body} at GET /api/v1/briefs/:name (token required, API listener only), and the CLI command is `banco brief show NAME [--json]` (JSON is the only output; the flag is accepted). The sha256 is of the whole file and is what a revision records as brief_sha256. Briefs are written in English (agent-facing instructions) with the Italian text rules inside them. The 14 writing rules of the brief are in diagnosis-item.md; the public-repository rules are in every brief.
- **Why:** Agents read one file per task; names that match commands are easier to find.
- **Cost:** The brief's file names differ from the design's.
- **Status:** implemented in M3
- **Back-port:** C-03 file names.

## D-027 · 2026-10-03 · M3 rules note: gate on learn chains, guest skills, skill keys, Q11 constants

- **Design ref:** Brief 'Che cosa decide chi costruisce' (three proposals), B-04, B-05, Q11, X-03, X-04
- **Design said:** Reconcile three points in the rules note: a gate on chains that are not in the prior-year programme, guest starting skills, and the skill key format. B-05 sets SITTINGS_PER_SUBJECT = 1 until Q11 is answered.
- **We do:** (1) The gate is adopted as proposed: a starting skill whose same-subject prerequisite is already to_recover with kind learn is not served and ends not_assessed(prerequisite_to_recover), a new reason in B-04 (REASONS). (2) Guest starting skills are adopted as proposed: an entry test may list a skill of an approved graph of another subject (guest_of_subject); the result goes to the owner subject and is reused as in B-03. (3) Skill keys are `<subject>.<kebab-slug>` with a table of the inventory prefixes (Rules::V1::INVENTORY_PREFIXES). (4) Q11 is answered, so SITTINGS_PER_SUBJECT = 2 and AUTO_SECOND_SITTING = true; the time constants, the three Q10 cases, the daily caps and the calculator per subject are Rules::V1 constants, with the prose in docs/rules/diagnosis-1.md. (5) The error-code registry config/banco/error_codes.yml has validation codes, API codes, verdicts and the codes the grader emits, and a test checks that the orthography allowlist is a subset of the grader's.
- **Why:** The gate and the guest skills are what the skill inventory needs; fixed keys let the schema check them.
- **Cost:** The engine (M8) implements the gate and the guest rule.
- **Status:** implemented in M3 (constants and prose); engine behaviour in M8
- **Back-port:** B-03, B-04 (new reason), B-05 (Q11).

## D-028 · 2026-10-03 · M3 agent tokens: api_tokens reshaped to D-05

- **Design ref:** D-05, E-09
- **Design said:** api_tokens(id, role agent_claude|agent_omp|ci, label, secret_sha256); format bnc_<8-char id>_<43-char base64url>; issuance by a rake task that prints the token once.
- **We do:** The M2 table had token_digest and other roles, before the token format was fixed. A migration (20261003100004) recreates api_tokens and api_token_revocations (it refuses to run if they hold rows) with public_id (8 characters, unique), secret_sha256 (64 hex), role agent_claude|agent_omp|ci, label, and the append-only triggers. ApiToken.issue! returns the token string once; `bin/rails banco:token:issue ROLE=... [LABEL=...]` prints it on stdout and stores only the hash; `banco:token:revoke ID=<public id>` adds a revocation row. Banco::TokenAuth reads the registry through ApiToken.lookup (revoked tokens are unknown) and keeps the replaceable seam for tests.
- **Why:** The lookup by public id plus a hash comparison is what D-05 says; the table had no column for the id.
- **Cost:** One more migration; the M2 shape is superseded (the table was empty everywhere).
- **Status:** implemented in M3
- **Back-port:** D-05.



## D-029 · 2026-10-03 · M4 expression worker: promoted checker, vendored engine, protocol and limits

- **Design ref:** A-01, X-01, brief 'I correttori', 'La resa nell'app' (libraries in public/vendor)
- **Design said:** A persistent Node worker running our checker with Compute Engine 0.146.0 copied into the repo; JSON lines with request id, a mutex, a 2 s timeout, restart on exit; libraries copied under public/vendor/<name>@<version>/ with SHA256SUMS checked in CI.
- **We do:** The spike checker is app/javascript/grader/checker.mjs with CHECKER_VERSION 1.0.0 (one change: a result carries `normalized`, the LaTeX that was graded). The worker is app/javascript/grader/worker.mjs: JSON lines, a `ready` line first, then one reply per request id (ops check, compile, ping), compiled items cached by key. Compute Engine 0.146.0 is vendored as the three esm files it needs (compute-engine.js and two chunks) in app/javascript/grader/vendor/compute-engine/ with LICENSE and SHA256SUMS; a Node test checks the version and the sums. This is the server's copy; the browser copy of the same version under public/vendor/ comes with the item renderer (M10). Grading::Expression keeps one Grading::Expression::Worker per Process.pid, started on first use (never in an initializer), with a mutex and a 2 s timeout per request; a timeout, crash or closed pipe kills the process, raises Grading::Expression::Unavailable and the next request starts a fresh one. Starting is separate: up to 20 s for the `ready` line, because loading the engine takes about a second and the host can be loaded. In a forked child the parent's entries are dropped (pipes closed, process untouched). Node runs with --max-old-space-size=256 (BANCO_NODE overrides the binary). app/javascript is on Propshaft's load path through importmap-rails, which would digest 3.8 MB of server-only files into public/assets and serve them, so config/initializers/propshaft_grader.rb filters app/javascript/grader out of the load path. The image gets the commit sha through `ARG GIT_SHA` (BANCO_GIT_SHA), since it has no .git directory; CI passes github.sha.
- **Why:** Same design, with the failure modes made explicit (a loaded host must not make a cold start look like a hung grader).
- **Cost:** 3.8 MB of vendored, minified JS in the repository; a small Propshaft patch.
- **Status:** implemented in M4
- **Back-port:** A-01 (startup timeout, asset-path exclusion), brief 'La resa nell'app' (server copy of the engine).

## D-030 · 2026-10-03 · M4 how an answer reaches the grader: raw encodings, "Non lo so", id map

- **Design ref:** X-01, E-03, B-04
- **Design said:** The browser posts {served_event_id, client_attempt_id, raw, source}; "Non lo so" is a recorded outcome D; options, ordering rows and matching columns are shuffled and re-keyed by the server.
- **We do:** attempts.raw is the typed text for number, normalized_text, expression and choice (the shown option id), and JSON text for fraction ({"n","d"} and an optional "w" for the whole part of a mixed number), ordering (an array of shown ids) and matching ({left id: right id}). "Non lo so" and "Non l'ho ancora studiato" send the raw text `{"dont_know":true}` (Grading::DONT_KNOW_RAW) whatever the component, and grade as verdict dont_know. attempts.source keeps meaning the input channel (mathlive or text for expressions). Grading.grade takes an optional id_map {shown id => canonical id}, applied before comparison, so the serve layer's shuffle is undone in one place; ids not in the item's display are invalid (unparseable).
- **Why:** The schema has no column for the "dont know" intent and attempts.source is already the channel the expression checker needs.
- **Cost:** The M10 UI and the M8 serve layer must produce these encodings.
- **Status:** implemented in M4
- **Back-port:** X-01 (raw formats), E-03.

## D-031 · 2026-10-03 · M4 what a grading row carries: inverted pairs, give-up marker, retry schedule

- **Design ref:** A-01, X-03
- **Design said:** Ordering stores inverted_pairs; GradePendingJob retries at 30 s, 2 min and 10 min; after the last failure the attempt goes to the teacher.
- **We do:** attempt_gradings has no column for inverted pairs, so ordering and matching put them in `normalized` as JSON ({"order":[...],"inverted_pairs":n}; {"pairs":{...},"correct_pairs":k}); number and fraction store the exact value ("7/2"), text the normalized string, expressions the normalized LaTeX. invalid answers are not attempts: Grading::Recorder.append refuses them (the caller answers with Result#message_it). The retry schedule counts from the failure: the sync grade that failed schedules GradePendingJob 30 s later (Recorder.schedule_retry); a second failure waits 2 minutes, a third 10 minutes, and the job runs at most three times. When the last run fails the job appends a retry row with verdict undetermined and error code grader_unavailable, so the attempt shows as verdict_pending (evidence :pending) and a later job can still settle it; a retry that succeeds appends the real verdict. Nothing is ever updated; the latest row is the derived outcome.
- **Why:** The ledger is append-only and the brief wants the give-up visible to the teacher; the marker row is the only place to say it.
- **Cost:** The derivation (M8) must treat a latest row with grader_unavailable as verdict_pending.
- **Status:** implemented in M4
- **Back-port:** A-01 (normalized carries the inverted pairs; give-up row).

## D-032 · 2026-10-03 · M4 closed graders: text policies, form violation names, number input

- **Design ref:** A-01, E-03, X-03, X-04, operator Q10
- **Design said:** normalized_text with NFC, trim, whitespace collapse, apostrophe and quote unification, case per item, trailing punctuation stripped, accent policy strict|flag and spelling policy exact|near; a Spanish accent slip is ORTHOGRAPHY_SLIP when the unaccented form is not a paradigm form; numbers exact from the Italian comma; fractions with declared forms.
- **We do:** (1) Accents are never folded into "correct": an accent or apostrophe slip is verdict typical_error with code es_accents (subject spanish), it_accents or it_apostrophe_accent, so «está» against «esta» is never correct under either policy. The credit of X-03 is decided by Grading::Evidence: it applies only when the item says accent_policy flag (it does not measure accents) and the codes are in ORTHOGRAPHY_ALLOWLIST; strict makes the slip W. If the unaccented form is itself a paradigm form the answer is a different word: wrong. Only the grave and the acute are folded: ñ and ü are letters. A word-final apostrophe after a vowel is read as an accent only when the answer is not otherwise exact (un po' stays). (2) Case is folded; banco.item/1 has no field to declare case sensitivity, so Spec#case_sensitive is false for every stored item and is the seam for a later schema version. (3) English contractions: curly apostrophes are unified; "do not" against "don't" goes through accept[], as E-03 says. Spelling is exact unless the item declares near; near_miss needs 5+ characters and one Damerau (adjacent transposition) edit from an accepted answer, after the declared errors are checked. (4) The binary profile (width, leading_zeros) is graded in normalized_text: digits 0 and 1 only; with required zeros a short answer with the right value is wrong_form (leading_zeros). (5) Number: the answer must be one decimal (comma; U+2212 and other dash variants as minus; NBSP, narrow NBSP and thin space trimmed); digits separated by a space are invalid (ambiguous_mixed_number) because the schema cannot declare a thousands separator; a slash is invalid (a non-decimal key needs a fraction item); the key may be a JSON number, a decimal string or "7/2"; an optional unit suffix is stripped. (6) Fraction violations carry the registry names lowest_terms (not reduced), improper (an improper fraction where mixed is declared) and mixed (the opposite); expression violations are the checker's own names (radicand_not_reduced, not_lowest_terms, ...). (7) Expression methods: exact and exact-sampled count as exact; anything that touched floating point (nested radicals, pi, large exponents) is method float and its evidence is pending whatever the verdict.
- **Why:** Each rule closes a path by which a certain-looking answer could be credited without the item having measured it.
- **Cost:** Expression form-violation names are not all in the registry's grader_codes (the list belongs to the checker); the registry gained grader_unavailable and leading_zeros.
- **Status:** implemented in M4
- **Back-port:** A-01, E-03, X-03, X-04.
## D-033 · 2026-10-03 · M8 engine shape: Plan, Fold, Engine, Derivation and the event vocabulary

- **Design ref:** B-08, B-10
- **Design said:** A pure core, `Diagnosis::Rules::V1`, SkillOutcome, Frontier, TimeAccount, `Engine.next_action(snapshot, log, clock)`, `Derivation.states(student, as_of:)`.
- **We do:** `lib/diagnosis/` holds `Plan` (blueprint, graph and pool as plain data), `SkillOutcome` (the per-skill rule), `Fold` and `State` (the log folded to the frontier, outcomes, serves and sittings; the frontier is a plain list inside `State`, not a class of its own), `Candidates` (which instance next), `TimeAccount` (counted seconds), `Engine.next_action(plan, events, clock)` (an `Action`: serve, abandon_item, wait, start_sitting, end_sitting, close_run, none), `Derivation.result(plan, events, voided:)` (states, reasons, time account, end reason) and `DailyPlan`. `Derivation.states(student, as_of:)` becomes `RunAdapter#result`, because a plan belongs to one run; the cross-run part (reuse, seen instances, voids) is `PlanLoader`. The event vocabulary and the decision payloads are in `docs/rules/diagnosis-1.md` section 13. Outcomes are folded in log order; a teacher `resolve_attempt` on an answer that already counted is applied in place at the original position, and outcomes after a resolution are ignored. The next instance is chosen by sorting the candidates on `sha256(seed_salt|skill|fingerprint)`, with no random state, so replay is exact.
- **Why:** One fold lets the app, `simulate` and the property tests share the code that decides. Taking the facts from the plan rather than from a student keeps the core free of Rails.
- **Cost:** `Derivation.states(student, as_of:)` has no `as_of`: replay at a past time is a prefix of the event list.
- **Status:** implemented in M8
- **Back-port:** B-08, B-10.

## D-034 · 2026-10-03 · M8 pool: descent targets draw on the subject's passed items

- **Design ref:** B-03, B-07, C-01
- **Design said:** The blueprint pins `entries[]` (4 to 10) with the items of each; descent reaches prerequisites that are not entries.
- **We do:** The pinned items serve their entries. A skill reached by descent that is not an entry is served from the latest revision of any item of the subject whose latest validation `passed` and whose `skill` is that skill (`PlanLoader`). A skill with no such item ends `not_assessed(no_unseen_items)`. In `simulate` from a bare file, every skill of the graph without items gets one synthetic item of three instances.
- **Why:** The blueprint format has no place for items of skills that are not starting skills, and the descent needs them. The teacher approves the pinned items; the others are validated items of the same subject.
- **Cost:** Items outside the pinned set reach the student without being on the approval screen. The blueprint format (`banco.blueprint/1`) may want a `descent_items` member in version 2; the brief for the content agent says nothing yet.
- **Status:** resolved: descent items pinned (D-038 supersedes the pool rule; the engine now serves only pinned items)
- **Back-port:** B-07.

## D-035 · 2026-10-03 · M8 readings of the rules where the register is silent

- **Design ref:** B-02, B-03, B-04, B-05, B-12, B-13
- **Design said:** The rules of `docs/rules/diagnosis-1.md` sections 3 to 6 and 7.
- **We do:** (1) Descent never goes into a skill with scope `in_progress`, whatever the kind of the skill it starts from. (2) "Below a demonstrated skill" is the transitive closure of `prerequisites` and `composite_of`; a suspect is exempt. (3) The gate on learn chains looks at the direct prerequisites of the same subject, and a prerequisite that is itself gated counts; it applies to starting skills only. (4) A skill unresolved at the per-skill cap ends `pending` with answers outstanding, otherwise `not_assessed(item_cap)` (cap) or `not_assessed(no_unseen_items)`; `item_cap` as a skill reason therefore also means the per-skill cap, not only the 30-item sitting cap. (5) A run closed by `teacher_close` leaves the unserved skills `not_assessed(not_started)` and the partly served ones `time_budget`. (6) The 30-item cap ends a sitting like the time budget: the next sitting if one is allowed, otherwise the run closes with `item_cap`. (7) `extend_diagnosis_run` after a close on `time_budget` or `item_cap` reopens the run. (8) The short answer is not a member of the frontier: it is served at frontier empty, at budget minus the reserve, or as the first item of a later sitting; the skill it measures is judged only by it. (9) A testlet counts one outcome per (serve, skill). (10) The sitting budget comes from the blueprint (`budget.sitting_minutes`, `sittings`), which the schema bounds to 10..60 minutes and 1..2 sittings, defaulting to `Rules::V1`; `AUTO_SECOND_SITTING` false limits it to one plus the teacher's extensions.
- **Why:** Each is the smallest reading that keeps the property tests (termination within 5 x reachable + 1, never below a demonstrated skill, nothing served after the budget) true.
- **Cost:** A teacher who disagrees changes one reading and bumps `rules_version`.
- **Status:** implemented in M8
- **Back-port:** B-03, B-04, B-05.

## D-036 · 2026-10-03 · M8 simulate: bundle format, flat bare blueprint, --subject, scripts

- **Design ref:** B-10, M8 verify
- **Design said:** `banco diagnosis simulate --subject S | --blueprint FILE`, scripts all-correct, all-wrong, FILE; the verify names `test/fixtures/blueprints/three-skill.json`.
- **We do:** `POST /api/v1/diagnosis/simulate` (any agent token; a pure dry run). The file given to `--blueprint` is a `banco.blueprint/1` document (a flat subject: only the entries are asked) or a bundle `{blueprint, graph?, pool?, external?, seen?, seed_salt?}`; `--subject` takes the latest stored blueprint revision. `--script` is `all-correct`, `all-wrong`, `mixed` (the second item of each skill wrong) or a file `{default, seconds, confirm_short, rules[]}`. The answer has `end_reason`, `states`, `sittings`, `observations`, `suspects`, `checks` and the `trace` (the events). Simulate does not check the entry count of the blueprint (4 to 10 belongs to `E-BLUEPRINT-ENTRIES` at submission), so the three-skill fixture can have three. New codes `E-SIMULATE-INPUT` (422) and `E-BLUEPRINT-UNKNOWN` (404); a graph cycle is `E-GRAPH-CYCLE` (422).
- **Why:** The CLI sends the file inline, so the API needs nothing on the server's disk. A bundle is the only way to simulate a draft whose graph and pool are not stored yet.
- **Cost:** The contract has one more command; the Go client gained a request body.
- **Status:** implemented in M8
- **Back-port:** B-10.

## D-037 · 2026-10-03 · M8 adapter approximations to revisit when the item and grader code lands

- **Design ref:** X-03, X-04, B-08
- **Design said:** The grader and the item materialiser define the shapes of display, gradings and form declarations.
- **We do:** Written before M4 and M5 finish, so `EventLoader` and `PlanLoader` assume: the item body names `skill`, `component`, `kind`, `expected_seconds`, `form_skill`, `form`, `accent_policy` as in `banco.item/1`; an ordering or matching instance exposes `elements` or `left` in its display for the low-guess size (otherwise such an instance is not low-guess); an orthography slip is credited when the code is in the allowlist and `accent_policy` is not `strict`, but the observation on the orthography skill is only logged when the event carries `orthography_skill`, which no loader sets yet; a declared wrong form is credited without checking that `form_skill` is inside the prerequisite closure (the closure only gates the suspect); an attempt with no grading is `ungraded` with `retry_state` running unless an `app_events` row `grade_retries_exhausted` names it; a testlet attempt maps to one answer on the testlet's first skill.
- **Why:** The pure engine is fully specified and tested; these are the seams to the rows that other milestones own.
- **Cost:** Four small places to fix when M4 and M5 fix their shapes; the engine does not change.
- **Status:** open
- **Back-port:** none.

## D-038 · 2026-10-03 · M5 descent pool pinned: banco.blueprint/1 gains a required descent

- **Design ref:** Firm rule 2 (the teacher approves everything the student sees), B-03, B-07, D-034
- **Design said:** The blueprint pins the items of its starting skills; descent reaches prerequisites that are not entries (D-034 let them draw on any validated item of the subject, and asked the operator whether descent items should be pinned too).
- **We do:** Pinned. `banco.blueprint/1` has a required `descent[]`: for every skill the descent can reach from the starting skills (`Diagnosis::Plan#descent_targets`: direct prerequisites, composite parts and the implicates of typical errors, transitively, in the same subject, never an `in_progress` skill itself) the blueprint gives `{skill, items[]}` or `{skill, not_assessed_reason_it}` (exactly one of the two). A reachable skill in neither is refused with the new code `E-BLUEPRINT-UNPINNED-DESCENT` at submission; a skill in `descent[]` that is not reachable is accepted (the teacher may want it). `PlanLoader` serves only the items of `entries[]` and `descent[]`; a reachable skill without a pinned item ends `not_assessed(no_unseen_items)`. In `simulate` a bare file with a `descent` member serves only what it pins; a bare file without one keeps the synthetic items of D-036. The schema was amended in place, not bumped to /2: no content exists yet (M11 starts after M6 and M9), the fixtures were updated, and the brief (`briefs/blueprint.md`, still version 1 for the same reason) says what to write. The same choice is recorded for `case_sensitive` (D-041).
- **Why:** Firm rule 2. The teacher approves the blueprint's screen; anything the student can be asked has to be on it. An unpinned but validated item would have reached the student without that approval.
- **Cost:** The blueprint is longer by one entry per reachable skill; an agent that forgets one gets a code that names the skills.
- **Status:** implemented in M5
- **Back-port:** B-07 (approval units), A-03 (blueprint format), D-034 (resolved).

## D-039 · 2026-10-03 · M5 a run waits while an answer is pending or ungraded

- **Design ref:** B-03, B-04, X-03, D-031
- **Design said:** The run closes `frontier_empty` when nothing more can be served; skills with answers outstanding end `pending`.
- **We do:** `Engine.next_action` answers `wait` with reason `pending_answers` instead of `close_run frontier_empty` while an answer of the run is pending or ungraded and its skill is not resolved (including a short answer awaiting `confirm_grade`). `Derivation.result` reports `waiting_on: "pending_answers"`. The run closes after the resolution (a retry grading, `resolve_attempt` or `confirm_grade`), or when the teacher closes it (`close_diagnosis_run`). `Simulator.run` stops at such a wait and reports it; with `resolve_pending: "wrong"|"correct"` it plays the teacher resolving them (the property tests use it).
- **Why:** A run closed with an answer in flight froze the skill as `pending` although a retry a minute later could settle it, and a run closed before the short answer was confirmed looked finished.
- **Cost:** A subject can stay open until the evening confirmation; the report must say "in attesa" for a waiting run (M9/M14).
- **Status:** implemented in M5
- **Back-port:** B-03, B-04.

## D-040 · 2026-10-03 · M5 ORTHOGRAPHY_SLIP: the rules note follows the code (accent_policy flag)

- **Design ref:** X-03, operator Q10 (c), D-032
- **Design said:** ORTHOGRAPHY_SLIP applies to a code in the allowlist, an unaccented form that is not a paradigm form, and an item that does not measure spelling; the rules note repeated it.
- **We do:** The code is kept and the note changed. "The item does not measure accents" is the item's `accent_policy: flag` (D-032); `strict` means it measures them and the slip is W. The paradigm-form condition is decided by the grader, which already says `wrong` (not a slip) when the unaccented form is itself a paradigm form, so `Grading::Evidence` has no second check. `spelling_policy` is a different axis (near misses of whole words) and plays no part.
- **Why:** This is the reading consistent with the operator's Q10 default (credit when the item does not measure spelling) and it keeps one place, the item's declaration, that says whether an item measures accents.
- **Cost:** An item author must set `accent_policy: flag` explicitly on items that are not about accents; the item brief says so.
- **Status:** implemented in M5
- **Back-port:** X-03 wording.

## D-041 · 2026-10-03 · M5 banco.item/1 gains optional case_sensitive

- **Design ref:** D-032 (2), E-03
- **Design said:** The schema had no field for case sensitivity; `Spec#case_sensitive` was a seam, false for every stored item.
- **We do:** `banco.item/1` (and its sub-items) gain an optional boolean `case_sensitive`, default false, amended in place for the reason given in D-038. `Grading::Spec.from_instance` already reads the body, so the field reaches `Grading::Closed::Text`, which keeps case when it is true (a text answer and every accepted, declared and paradigm form compare with case).
- **Why:** Some answers are case-bearing (chemical symbols, the Spanish and English proper nouns an item is about).
- **Cost:** None for existing items.
- **Status:** implemented in M5
- **Back-port:** A-03 field list.

## D-042 · 2026-10-03 · M5 validation pipeline: job, harness, Chrome, retries, stored columns

- **Design ref:** A-02, A-06, A-07, E-05, brief 'La validazione meccanica'
- **Design said:** `ValidateItemRevisionJob` on the one-thread `chrome` queue runs a Ruby phase and a Chrome phase; `--dry-run` validates synchronously and stores nothing; Ferrum attaches to the sidecar by IP; the reaper inside the lock disposes all contexts; the harness page is served on port 3200 with a CSP; thresholds in `config/banco/validation_rules.yml`, whose version is stored; item_validations has `status`, `codes`, versions.
- **We do:** As designed, with these shapes. (1) Migration `20261003200001`: `item_revisions.files_json` (generator.mjs, verify.mjs, assets, so the harness can serve a stored revision and a later revision can carry files forward) and, on `item_validations`, `findings_json`, `rules_version`, `grader_version`, `harness_version`, `chrome_version`, `instances_sha256`, `attempt`. (2) The reaper disposes only orphan contexts (the ones this process does not own), because the lock is held and a context of ours may be open; the run's own contexts are disposed in `ensure`. In test, development and CI `ChromeRunner` launches a local Chrome (`BROWSER_PATH`, Ferrum `ignore_default_browser_options`, curated flags, `--host-resolver-rules` that resolves only the loopback) and keeps it for the process; `BANCO_CHROME_HOST` selects the sidecar (resolved with `Resolv.getaddress` before `Ferrum::Browser.new(url:)`). (3) The harness listener (`HarnessController`, an `ActionController::API`: no session, no cookie) serves `/h/<run-token>/{harness.html,runner.mjs,generator.mjs,verify.mjs}` and `/lib/{rng,fmt}.mjs`; the run token is an HMAC (key `banco/harness`) of `rev:<id>` or `stage:<id>`, 10 minutes; a dry run stages its files in the memory of the Puma process that handles the request (`Validation::Harness::Staging`), a job reads the stored revision. The page's CSP is `default-src 'none'; script-src 'self'; connect-src 'none'; img-src 'none'; base-uri 'none'; form-action 'none'`. `harness_version` is the sha256 of the libraries and the runner. (4) Chrome trouble is never a verdict: each failed attempt appends an `error` row and the job retries (3 attempts, 30 s and 60 s apart); after the last one the revision stays `error` (`settled` true), except a timeout inside the page, which fails it with `E-GEN-TIMEOUT` (a generator that never returns is the generator's fault). A dry run answers 409 `E-CHROME-BUSY` when the lock is taken and 503 `E-CHROME-UNAVAILABLE` (new API code) when Chrome or the grader worker does not answer. (5) Only the generator runs on all 200 seeds in two contexts; the rejection checks of verify (error values, +1 and sign-flip mutants) run on the first 24 materialized instances, the acceptance check on every clean seed. (6) Tests start real listeners in the test process (`test/support/validation_servers.rb`, the listener tag through the test seam) so that Chrome and the compiled CLI have a server to call.
- **Why:** Same design; each point is a detail the register left open. The local Chrome keeps CI and development free of the sidecar; orphan-only reaping is safe even if a health check ever shares the process.
- **Cost:** `lib/harness/` is served from disk by Ruby (a few KB). A dry run of a generated item takes seconds and holds the Chrome lock; parallel test processes that share the lock wait or retry on 409.
- **Status:** implemented in M5
- **Back-port:** A-02 (reaper wording), A-06 (retry and E-CHROME-UNAVAILABLE), E-01 (files_json).

## D-043 · 2026-10-03 · M5 readings of the A-06 codes where the register is silent

- **Design ref:** A-06, A-03, A-04, C-01, X-01
- **Design said:** A list of codes with some thresholds; the checks for "errors that collide" and "an expected answer that violates its own form" are named without a code; E-PROVA-A-PARAMS, E-ACCENT-POLICY and E-GEN-THROW have one-line descriptions.
- **We do:** (1) An error value equal to the key, or two error values that are the same answer, or an error value the grader does not return with its code: `E-ROUNDTRIP` (rule key, collision, error_value). A key that cannot be one for its component (a number that is not a finite decimal, a choice id that is not an option, an ordering that is not a permutation) is `E-GEN-SCHEMA` rule `answer_shape`, for listed instances too. (2) `E-DISPLAY-KEY`: any member of a display named answer, key, correct, solution, verdict, expected, errors, rubric, explanation (and similar); it is found before the schema, so it is not also an extra member. (3) The size rules of choice (3 to 5), ordering (3 to 7) and matching (at least 4 pairs, right column n+1) are raised from the instance as `E-CHOICE-OPTIONS` and `E-MATCHING-SIZE`; the schema's `minItems` and `maxItems` on those arrays are left to them. The blueprint's entry count (4 to 10) is `E-BLUEPRINT-ENTRIES` for the same reason. (4) Generated items: a seed is clean when generate did not throw, the output is at most 16 KB, fits the instance shape and has no instance error; `E-GEN-THROW` is raised when more than 20% of the seeds throw (fewer are tolerated problem seeds); `E-GEN-POOL` when fewer than 24 seeds are clean, more than 20% are problem seeds, or fewer than 20 of the 24 displays differ. (5) `E-PROVA-A-PARAMS`: an item whose sources include `prova_a_structure` and that has listed instances (fixed numbers) instead of a generator; there is no private list of the old numbers in the repository. (6) `E-ACCENT-POLICY`: `accent_policy` or `paradigm_forms` on an item that is not `normalized_text`, or `accent_policy: flag` with a paradigm form that differs from an accepted answer only by accents. (7) `E-SOURCE` on items: a `prima_line` or `seconda_line` source has `ref` `source-key:line` and a `fragment` that is an exact substring of a line that is not a transcriber line. (8) `E-QUOTE-REF`: `prompt.quote` and display quotes name an imported reference text and are an exact substring of it (whitespace folded). (9) `E-STEP-INCONSISTENT`: for number and fraction, the numbers in `solution.final` do not include the key; for choice, `final` names another option and not the key. (10) The readability lint reads only strings under keys ending in `_it`; texts in the language being taught are not linted. (11) Testlets support listed sub-item instances only (a generator in a sub-item is `E-GEN-SCHEMA`); their instances combine the k-th instance of each sub-item. A short answer stores one instance (its prompt, with the rubric as the answer). (12) Graph checks: `E-SOURCE` for a citation that is not an exact substring or cites a transcriber line, `E-SCOPE`, `E-NEEDED-BY` (a `needed_by` ref to a `seconda` source, or a transitive prerequisite of one), `E-GRAPH-EDGE-UNAPPROVED` (a cross-subject edge needs the skill in a graph with an `approve_skill_graph` decision), `E-GRAPH-CYCLE` first. (13) `skill-graph coverage` uses the line ranges of C-01 (config, line numbers only): uncovered are non-blank pdf-origin lines in the range that no ref cites and no exclusion explains. (14) E-POOL-REDO counts instances of the items pinned under a starting skill; `choice_only_reason_it` waives the hard-to-guess count, `redo_reserve: false` the whole check.
- **Why:** Each is the smallest mechanical reading of the register that a fixture can produce and a test can pin.
- **Cost:** Some readings are stricter than a human (a final that names another option's text); a false positive is a finding the agent can read and fix, never a silent pass.
- **Status:** implemented in M5
- **Back-port:** A-06 text.

## D-044 · 2026-10-03 · M5 the content agent's API and CLI: submit semantics, folders, status stages

- **Design ref:** E-05, A-04, B-07, C-04, brief 'I dati e la CLI'
- **Design said:** `work open ITEM [--role]`, `work submit DIR [--dry-run]`, `work status REV [--wait]`, `skill-graph`, `blueprint`, `status --json` with a stage per subject; sessions and `item new` are listed too; no command takes a decision.
- **We do:** (1) The first `work submit` of an item key creates the item (there is no `item new` in M5); a later submit needs `base` equal to the latest revision (409 `E-STALE-BASE` otherwise); identical files are a replay (`replayed: true`, no new revision, no job). Files left out are carried forward from the base. (2) `work open` writes a folder with `.banco/work.json` (item, base, role) so that `work submit DIR` needs no flags; a verifier's folder has `instances.json` and `tests.json`, no `generator.mjs`, and `work submit` from it sends `verify.mjs` only. The role is a query parameter: the server never sends `generator.mjs` to `role=verifier`. (3) Sessions arrive with M6: `author_session_id` and `file_sessions_json` are empty in M5, so `E-VERIFY-AUTHOR` and `E-SESSION-NOT-INDEPENDENT` are not raised yet; the verifier order still works because verify.mjs is carried by a separate revision. (4) A failing dry run is 422 with the first code at the top and `codes`, `findings` (code, severity, field, message, detail) and `dry_run: true`; the CLI prints it on stderr and exits 3. `work status REV --wait` polls until the validation is `settled` (passed, failed, or an error after the last attempt) and exits 0, 3 or 6. (5) The contract gains `flags` per command (documentation; the CLI parses its own flags) and `contract/examples/<command>.<variant>.json`, written by the integration tests with `UPDATE_CONTRACT=1`, compared otherwise; the Go test reads them with unknown fields refused and checks method, path and the error codes against the command. (6) `banco status` stages: `drafting` (no graph or entry test, or a pinned item failed), `validating` (an item's latest revision has no verdict or ended in error), `in_review` (graph and entry test submitted, every pinned item passed), `approved` (a teacher decision row exists for a graph and an entry test). `awaiting_teacher` is reachable only when the review and blind-solve machinery of M6 says it is done (`SubjectStage.review_done?` is false until then), so until M6 the agent never reads it. (7) A blueprint may be submitted against a graph the teacher has not approved yet (so it can be simulated); `briefs/blueprint.md` says the graph should be approved first. (8) D-037: the displays M5 materializes use `elements` for orderings and `left` for matchings, as the loaders assumed; the orthography observation skill is still not set by any loader.
- **Why:** The smallest cycle that lets an agent write, check and resubmit without a second command or a hidden state.
- **Cost:** The agent cannot see `awaiting_teacher` before M6; a blueprint on an unapproved graph can be wasted work.
- **Status:** implemented in M5
- **Back-port:** E-05 (flags, examples, status stages), A-04 (item creation by first submit).
## D-045 · 2026-10-03 · M10 serve-time re-keying: ids, seeds, redraws and replay

- **Design ref:** X-01, E-03
- **Design said:** Choice options, ordering elements and both matching columns are shuffled with the run seed and get fresh ids in shown order (o1..oN, r1..rN, l1..lN); an ordering equal to the key or its reverse is redrawn; the shown order and the id map are logged in item_served.
- **We do:** `Diagnosis::Rekey` (lib/diagnosis/rekey.rb, pure). The shuffle is seeded from sha256 of `seed_salt|serve seq|instance id`, so the same serve always gives the same result and a replay of the log can recompute it. Fresh ids are o1..oN (options), e1..eN (ordering elements), l1..lN and r1..rN (matching). An ordering is redrawn when it equals the key, the reverse of the key or its own stored listing; a matching is redrawn when the left column keeps its stored order, the right column keeps its stored order, or the rows line up with the pairs of the key (up to 200 redraws; lists of fewer than three cannot avoid every pattern and keep the last draw). item_served.id_map_json is {shown id => stored id} and shown_order_json is {column => stored ids in shown order}; a testlet nests both by sub item id. A page asked for again (reload, resume) rebuilds the display from the logged shown order (`Rekey.replay`), never from a new draw. The browser never receives the map or the order (diagnosis_payload_test scans 50 seeds for key and outcome fields).
- **Why:** The brief only says "shuffled"; a seed that includes the serve's own seq keeps two serves of one instance apart, and stored order makes a reload exact.
- **Cost:** Matching and ordering pools with fewer than three elements are not fully protected (the schema asks for at least three and four).
- **Status:** implemented in M10
- **Back-port:** X-01 (the redraw rules for matching, id prefixes, the replay).

## D-046 · 2026-10-03 · M10 which blueprint a run is pinned to, who can start, what "released" means

- **Design ref:** B-07, B-12, D-002, D-012
- **Design said:** A run is pinned to the approved blueprint revision; release_diagnosis is a teacher decision (M9); at most 2 subjects and 75 counted minutes a day, in dependency order.
- **We do:** M9 is not built, so `Diagnosis::Conductor.latest_blueprint` takes the latest blueprint revision of the subject (the one place to change when approvals land). "Released" is the existence of a decision row of kind release_diagnosis (`Diagnosis::Release.open?`); until then the student sees "La diagnosi non è ancora aperta." and the warm-up only, and every sitting endpoint answers 403. The subject list is `Diagnosis::Availability`: DailyPlan decides dependency waits and the daily caps; the labels are Da fare, Prima fai X, Domani, In pausa (a sitting is open), Resta una parte da fare (the first sitting closed with the frontier open), Fatto, Fatto · in correzione (closed with a pending skill), Da ripetere (the teacher voided the run). A sitting that closed today is not startable today. Starting a subject is a POST that finds or creates the run (`Conductor.run_for`: the latest run, or the next sequence after a voided one); the step endpoint of a run that cannot start today answers {type: "wait"} (a screen, not an error). The teacher's preview (/teacher/preview, route default preview: true read from path_parameters only) always starts a fresh run of a preview student, with attempts in context teacher_preview.
- **Why:** The parts that M9 owns are single seams; nothing is guessed about approval.
- **Cost:** Until M9, an unapproved blueprint can be played by S once the release row exists; the release row is only written by M9.
- **Status:** implemented in M10
- **Back-port:** B-07 (selection seam), B-11 (label wording per state).

## D-047 · 2026-10-03 · M10 testlet instances: stored shape, one attempt, aggregated verdict

- **Design ref:** A-03, B-02, D-037
- **Design said:** A testlet is served as one unit, each sub item an attempt on its own skill, one counted outcome per skill per testlet. attempts.served_event_id is unique, so a serve has one attempt.
- **We do:** (1) A testlet instance is stored as display {"sub_items":[{"id","display"}]}, answer {sub id => key}, errors {sub id => [{code, value}]} (M5 must write this shape, or tell us the one it writes). (2) The browser posts one raw answer: JSON text of {sub id => the sub item's raw answer in the encodings of D-030}; a sub item given up carries the "Non lo so" text. (3) `Grading::Testlet` grades each sub item with the grader of its component and settles the unit only when that is certain: all correct is correct, all given up is dont_know, all wrong or given up is wrong, any mixture is undetermined (it goes to the teacher and counts neither way); an invalid sub answer makes the whole answer invalid. The attempt maps to one answer on the testlet's first skill (D-037). (4) `PlanLoader` listed the sub items' skills without removing duplicates, so a testlet whose five sub items measure one skill counted five serves against the per-skill cap of 5 and the skill ended not_assessed(item_cap) after one testlet; the list is now unique.
- **Why:** The unique index forces one attempt per serve; certain-or-pending is the rule the engine already uses for anything it cannot settle.
- **Cost:** A testlet answered four right out of five goes to the teacher as undetermined instead of counting as a partial credit. A later schema version may give each sub item its own attempt.
- **Status:** implemented in M10; **question for the operator**: should a mostly right testlet count as correct?
- **Back-port:** A-03 (stored shape), B-02 (testlet aggregation), D-037 (testlet adapter item closed).

## D-048 · 2026-10-03 · M10 the outbox in localStorage, resend, and what "Accedi di nuovo" does

- **Design ref:** E-10, B-05
- **Design said:** The answer is written to localStorage as banco.outbox.<client_attempt_id>; only 200 {recorded|invalid} clears it; a redirect, 401, 403, 5xx or no network keeps it and shows [Rientra]. The M10 task text said "memory + sessionStorage".
- **We do:** localStorage, as E-10 says (sessionStorage would lose an answer when the tab or browser is closed during a login), mirrored in memory. The button is [Accedi di nuovo] (B-11 wording) and does a full reload: the edge proxy sends the browser through the login and back, and the page's first act is to flush the queue in order. While blocked the page also retries every 20 seconds. A blocked answer hides the work area and shows "La tua risposta è salvata su questo computer. Accedi di nuovo e continua." A reply is accepted only when it is a 200 with a JSON content type and a status of recorded or invalid (a 200 login page is not a reply). The server answers a repeated client_attempt_id, or a second answer to a serve that already has one, as recorded without writing again. The answer's time is the server's time when it arrives, so a long login gap in the middle of an item is not subtracted from its counted time beyond the per-item cap of 600 seconds.
- **Why:** The loss of an answer is the failure the design fears most.
- **Cost:** The counted time of an item answered after a login gap can be over-counted up to the cap.
- **Status:** implemented in M10
- **Back-port:** E-10 (button wording, retry timer, what counts as a reply).

## D-049 · 2026-10-03 · M10 delivery of the student's pages: own importmap, CSP, figures by digest

- **Design ref:** X-02, E-04
- **Design said:** One app page with Turbo disabled; CSP with a per-request nonce; MathLive 0.111.0, KaTeX 0.19.0 and Compute Engine 0.146.0 from public/vendor/<name>@<version>/ with SHA256SUMS; agent SVG only as an img from /assets/items/<sha256>.svg with nosniff and a sandbox policy.
- **We do:** (1) The student's pages use their own importmap (config/importmap.student.rb, rendered with `javascript_importmap_tags "diagnosis", importmap: student_importmap`), so Turbo and application.js are never loaded; their Stimulus controllers live in app/javascript/student_controllers and the item templates in app/javascript/items. (2) The CSP is the one of X-02 with `SecureRandom.base64(16)` nonces on script-src; csp_header_test asserts it exactly. (3) public/vendor has mathlive@0.111.0 (the minified module and its fonts, no sounds), katex@0.19.0 (katex.mjs, katex.min.css and only the woff2 fonts, which is the format every browser the app allows picks first) and compute-engine@0.146.0 (the server's three files); vendor_test checks the SHA256SUMS, the versions and that no pin or script names another origin. MathLive reaches for a Compute Engine on esm.run when none is set: expression.js loads ours and sets it, and the CSP would refuse the remote one anyway. The MathLive options that need a mounted field (inlineShortcuts rad, smartSuperscript, no virtual keyboard) are set after the field is in the document (`handle.mounted`). (4) /assets/items/<sha256>.svg is ItemAssetsController (Propshaft's development server answers 404 for anything under /assets/, so a small prepend hands that path on); files are read from storage/item_assets/<sha256>.svg (config.x.item_assets_dir overrides) and a figure reaches the browser only when the instance display's figure carries a valid sha256: M5 stores the figure's digest in the display's figure.sha256 and the file under its digest (or tells us the shape it uses). (5) The font is Atkinson Hyperlegible when installed, then Verdana and the system sans-serif: the font file is not vendored in this milestone; the themes are cream (default), dark (the system's preference) and light (data-theme="light"), with no switch on screen.
- **Why:** An importmap is global to a page, so a separate map is the only way to keep Turbo out; the fetch check needs no CDN reachable.
- **Cost:** 3.7 MB of Compute Engine is a second copy of the server's files (git stores it once); the figure and font seams are decided here, not by M5.
- **Status:** implemented in M10
- **Back-port:** X-02 (own importmap, mounted configuration), A-03 (figure digest).

## D-050 · 2026-10-03 · M10 the warm-up: where it lives, how it is graded, when the editor is given up

- **Design ref:** B-11, E-04
- **Design said:** App code with tasks in config/banco/warmup.yml, graded server-side with an immediate "riprova", recorded in app_events (warmup_answer, warmup_completed), a text field with echo after two failed rounds of an editor task. SYNTH B-11 also says "store warm-up attempts with context warmup".
- **We do:** attempts.item_instance_id is not null and a warm-up task has no instance, so nothing is written to attempts: only app_events (warmup_answer {task, ok}, warmup_completed, warmup_editor_fallback). The closed tasks are graded by the closed graders through a Spec built from the task; the editor tasks are graded by comparing the LaTeX the editor produced with the list the task accepts (without spaces, \left and \right), because the point is typing the right keys, not the checker. A task that is not the editor's repeats until it is right. An editor task still wrong at the third try is skipped ("Passiamo avanti.") and warmup_editor_fallback is written; from then on the student's expression items carry input: "text" (a text box with a KaTeX echo, source text). A round ends with warmup_completed, after which a new round may start (the page offers no repeat once the diagnosis is open). The warm-up is outside the sitting budget and writes no run events. The system test types every editor task with real key events and checks the LaTeX produced.
- **Why:** The ledger's attempt row cannot hold a task with no item; the app_events vocabulary was already in the brief.
- **Cost:** The warm-up answers are not in the attempts table, so a later report reads app_events for them.
- **Status:** implemented in M10
- **Back-port:** B-11 (storage: app_events only; "after two rounds" read as three tries).

## D-051 · 2026-10-03 · M10 end-of-subject screen, solutions, and the flag

- **Design ref:** B-11, B-06, X-01
- **Design said:** Groups Sai già fare / Da riprendere / Da imparare / In correzione / Non te l'abbiamo chiesto (count only); solutions per skill with wrong and "Non lo so" first, each with "Penso che la mia risposta fosse giusta" (a student_flags row); only when the subject is final.
- **We do:** `Diagnosis::Summary` from `Derivation.result`: Sai già fare = demonstrated (with a reason in words), Da imparare = kind learn and to_recover or not_assessed(prerequisite_to_recover), Da riprendere = the other to_recover, with the message_it of the first error code seen (from the items' error catalogues; "Lo riprendiamo insieme." when there is none), In correzione = pending, Non te l'abbiamo chiesto = the count of the rest. Solutions are listed per attempt (the item's prompt, the student's answer in words through the logged id map, the steps and final of solution_json, the wrong and given-up ones first) and exist only when the run is closed; asking for the results of an open run goes back to the sitting. There is no student_flags table: the flag is an app_events row answer_flagged {attempt_id}, one per attempt. No score, percentage or alarm colour appears.
- **Why:** Same content with the tables that exist.
- **Cost:** The teacher's side (M9) reads the flags from app_events.
- **Status:** implemented in M10
- **Back-port:** B-11 (the flag's storage).

## D-052 · 2026-10-03 · M10 the verify commands as Rails 8.1 runs them

- **Design ref:** brief row M10
- **Design said:** `bin/rails test:system TEST=test/system/item_render_test.rb`.
- **We do:** Rails 8.1 refuses the TEST= form ("Could not load test file"); the path goes as an argument: `bin/rails test:system test/system/item_render_test.rb`. The system tests wait up to 10 seconds for elements (Capybara.default_max_wait_time) because the host is often loaded. Each system test file starts the app on the web listener's port, so they run one after the other, as the task runner does.
- **Why:** The command in the brief cannot run as written.
- **Cost:** None.
- **Status:** implemented in M10
- **Back-port:** brief row M10 (the command form).

## D-053 · 2026-10-03 · Integration: a run held open for pending answers in the student's pages

- **Design ref:** D-039 (M5: the engine never closes a run frontier_empty while an answer is pending or ungraded), D-051 (M10: solutions only when the subject is final)
- **Design said:** M10 was written against an engine that closed the run when the frontier was empty; M5 changed the engine to answer `wait(:pending_answers)` instead.
- **We do:** `Diagnosis::Conductor#step!` turns that wait into a `:final` step (the end screen, which lists the pending items as "in correzione"); `Conductor#holding?` says a run is open with nothing left to ask. The sitting page and the results page treat a holding run like a closed one for navigation (no redirect loop); solutions still wait for the real close. In the subject list a holding run is "Fatto · in correzione" and counts as a closed first sitting for dependency gating. The end-to-end system test now expects no solutions and no `run_closed` while the short answer is pending.
- **Why:** The student has nothing more to answer, and the teacher's grading of the short answer is the only thing left; showing solutions earlier would break D-051.
- **Cost:** Solutions of a subject with a short answer appear only after the teacher has graded it; KaTeX in solutions is no longer covered by the end-to-end test (the presenter tests cover it).
- **Status:** implemented in the merge
- **Back-port:** none.

## D-054 · 2026-10-03 · M6 sessions: integer ids, X-Banco-Session, roles and where the rules sit

- **Design ref:** A-04, E-05, E-09
- **Design said:** `agent_sessions(id ULID, role, agent, model, created_at)`; `banco session new` prints the id; the CLI sends X-Banco-Session on every write; `fixture.json` may declare file_sessions in tests.
- **We do:** (1) The id stays the integer primary key the earlier migrations created (`author_session_id` and `file_sessions` already hold integers); a migration adds `agent` and `model`. (2) The CLI reads the id from `BANCO_SESSION` and sends it on every request; `banco session new ... --id` prints the bare id, without `--id` the whole JSON. (3) The server requires a session on `work submit`, `review`, `solve` and the grader commands: `E-SESSION` (none or unknown) and `E-SESSION-ROLE` (wrong role), both 422, new API codes. `work open` needs one for the verifier's view and takes the role from it; an author may still open without one. Graph and blueprint submits do not need a session. (4) `E-VERIFY-AUTHOR` and `E-SESSION-NOT-INDEPENDENT` refuse the submission (422, nothing stored, also in a dry run), so they are raised before validation. A verifier may send `verify.mjs` only. (5) `item_revisions.file_sessions` is the base's map with the submitting session on every file the submission adds or changes; `author_session_id` is the author session of the last change to item.json. (6) The test-only `fixture.json` hook is not built: tests use real sessions. (7) The existing M5 tests now submit with sessions: the author's dry run of a generated item has no verify.mjs, so a full pass is the verifier's dry run on the author's revision.
- **Why:** The smallest change that keeps the ledger shape of M2 and makes the rules mechanical. A role fixed per session means the role needs no header of its own.
- **Cost:** Every M5 caller must now send a session; a dry run of a brand-new item with its verify is no longer possible, which is the point.
- **Status:** implemented in M6
- **Back-port:** A-04 (integer ids, BANCO_SESSION, E-SESSION, E-SESSION-ROLE).

## D-055 · 2026-10-03 · M6 providers.yml: families by pattern, per-role rules

- **Design ref:** A-08, operator Q8 (D-008)
- **Design said:** an allowlist per role; reviewer and solver on another family than the author; the grader on anthropic only; the model is declared.
- **We do:** `config/banco/providers.yml` lists families with name patterns (case-insensitive, `*`) and, per role, `different_from: author` and `known_family: true` (reviewer, solver) or `allow_families: [anthropic]` (grader). A model that matches no pattern is family `unknown`: refused for reviewer and solver (add it to the file), allowed for author and verifier. The family of the author is read from every session that wrote item.json, generator.mjs or an asset of the item. The check runs when a session is created (roles whose rule needs no item) and at every use (`E-PROVIDER-NOT-ALLOWED`). `banco submissions --pending` is a grader command too, because it hands out the student's text.
- **Why:** The student's answers must not reach another provider (Q8); a different family is the point of an independent review.
- **Cost:** The declaration is not proof. A new model name needs one line in the file and a D-entry.
- **Status:** implemented in M6
- **Back-port:** A-08.

## D-056 · 2026-10-03 · M6 expert review and blind solve: what is checked, what is stored

- **Design ref:** A-05, C-01 (banco.review/1, banco.solve/1)
- **Design said:** 11-point checklist; quotes exact substrings; a bare "tutto verificato" rejected; the server grades the blind solve and each disagreement is a blocker; a second round uses a session that did not see the first.
- **We do:** (1) Routes `GET|POST /api/v1/revisions/:revision/review` and `/solve` (the revision id is the item revision). Only the latest revision, and one whose validation passed, can be reviewed or solved (`E-STALE-BASE`, `E-ITEM-NOT-PASSED`). (2) The item text a quote may come from is item.json (raw and every string in it), the instances shown (8 for a generator item, all for a static one) and the programme lines the skill cites; with `instance` the pool is the item without its `instances` member plus that instance. Never generator.mjs, verify.mjs or other findings. (3) `E-REVIEW-EMPTY` when evidence has fewer than 4 words, is a stock phrase, repeats across points, or a point is `fail` and there is no finding. (4) The blind solve is graded by `Grading.grade` on the stored instance with canonical ids (no re-keying). `correct` is agreement; any other verdict (wrong, typical error, near miss, undetermined) is a blocker; `dont_know` is a major finding; an unreadable answer (use_comma, empty) is refused with 422 `E-FILES` and no finding; a short answer is recorded as not graded. One answer for each shown instance. (5) Tables `item_reviews`, `blind_solves`, `review_findings`, all append-only; findings written by the server for a mismatch have Italian `problem_it` and `fix_it`. (6) A session that already reviewed or solved any revision of the item cannot do it again or open it: a second round is a new session. (7) `--dry-run` checks and stores nothing.
- **Why:** Presence of a review is mechanical; judgement stays with the teacher.
- **Cost:** A review of a failed revision is not possible; a solver stumped on a hard but fair item produces a major finding the teacher must dismiss.
- **Status:** implemented in M6
- **Back-port:** A-05 (routes, E-REVIEW-EMPTY rules, dont_know).

## D-057 · 2026-10-03 · M6 the gate approvable? and awaiting_teacher

- **Design ref:** A-05, B-07, firm rule 2
- **Design said:** the approve control needs validation passed, a review and a blind solve on the exact revision, and every blocker or major disposed by the teacher (fix_requested, or dismissed with a reason); no agent verdict, no waiver.
- **We do:** `Review::Gate.check(revision)` gives `approvable`, the reasons and the open findings. A `fix_requested` disposition keeps the gate shut (the revision is to be replaced, and the new one needs its own review). Dispositions are decision rows of kind `dispose_finding` with payload `{finding_id, disposition: fix_requested|dismissed, reason_it}`; the latest decision for a finding counts. Nothing on the API listener writes them: M9b adds the pages. `SubjectStage` says `awaiting_teacher` when every pinned revision (entries and descent) has a review and a blind solve; what they found is the teacher's.
- **Why:** A fix request that left the revision approvable would let the teacher approve what they asked to change.
- **Cost:** The M9b UI must offer a new revision after a fix request.
- **Status:** implemented in M6 (UI in M9b)
- **Back-port:** A-05 (fix_requested keeps the gate shut).

## D-058 · 2026-10-03 · M6 grade proposals: codes, normalization, pending lists

- **Design ref:** B-06, A-08, operator G
- **Design said:** `grade propose` with points[{point_id, score, quote|null, rationale_it}]; quote_not_in_submission and grader_is_author; `banco pending`, `attempt show`, `submission show`, `verdict propose`.
- **We do:** (1) The API answers `E-QUOTE-NOT-FOUND` and `E-GRADER-IS-AUTHOR` (the build task's names, in the E- convention), with `reason` set to the brief's `quote_not_in_submission` and `grader_is_author`; both names stay in the registry. New API code `E-PROPOSAL-EXISTS` (409): an attempt with a proposal the teacher has neither confirmed nor rejected gets no second one. Registry version 2. (2) Entries may use the first draft's `point` and `rationale` for `point_id` and `rationale_it`. (3) Normalization of quote and student text: NFC, curly quotes and apostrophes straightened, whitespace collapsed, trim, no case or accent folding. (4) `banco submissions --pending --json` lists attempts of context diagnosis whose latest grading is `short_answer` and not settled (`short_answers`, with rubric and the student's text) and those whose evidence is `pending` (`verdicts`); the answer carries a notice that the student's text is data. Both commands need a grader session on Claude. (5) A proposal is a row in `grade_proposals` (append-only) and `counts: false`; the teacher's decisions are `confirm_grade` and `reject_grade` with `{grade_proposal_id}` (a rejection lets the attempt be proposed again) and `set_grade` with `{attempt_id}` (a grade written by the teacher); M9a/b write them. (6) `verdict propose` is not built: the brief now says the verdicts list is for the agent's report to the teacher until the teacher's pages say how a verdict is proposed. `banco pending`, `attempt show` and `submission show` are replaced by the one listing.
- **Why:** One listing and one proposal are enough for the evening loop; a command whose decision half does not exist yet would only be a stub.
- **Cost:** The agent cannot propose a verdict for an uncertain answer in M6.
- **Status:** implemented in M6 (confirmation in M9a/b)
- **Back-port:** B-06 (codes, E-PROPOSAL-EXISTS, normalization), E-05 (command list).

## D-059 · 2026-10-03 · M9a DecisionRecorder, its guards and the decision routes

- **Design ref:** D-08, B-08, firm rule 2
- **Design said:** `DecisionRecorder.call(request:)` raises unless the flag, the trusted proxy, the teacher group and user, a valid CSRF and no student cookie hold; it stores request id, Remote-User, remote address.
- **We do:** (1) `DecisionRecorder.call(request:, kind:, params:)` is the only writer; a test greps the application code for any other `Decision` insert. It checks `BANCO_DECISIONS_ENABLED=1`, the web listener, the edge peer, a Remote-User on `BANCO_TEACHER_USERS` with `banco-teacher`, no `banco_device` cookie and a CSRF mark on the request. (2) `Teacher::DecisionsController` verifies the token itself (`any_authenticity_token_valid?`, so it holds even where the environment disables forgery protection), then asks the recorder; a refusal is 403. The routes are `POST /teacher/...` inside the web constraint: on the API and harness listeners they fall to the catch-all 404 (`NotFoundController` now skips forgery protection, or a POST there would be a 422 in production). A missing target is 404, a decision not possible now is 422 with its reasons, a repeated request id is 409. Success is 200 JSON or a 303 to `/teacher`. (3) New columns on `decisions`: `groups`, `user_agent`, `request_path` (migration 20261004100001), next to the existing teacher login, request id and remote address. (4) The student's pages (`ActingStudent`, not the preview) set the signed cookie `banco_device=student`; any value of that cookie refuses decisions. `GET /teacher/items/:id` is the preview of an item and writes `teacher_viewed_item` only when the cookie is absent. (5) The API token has no decision scope: a test walks every `/api/` route and refuses any that maps to a decision or to the teacher's controllers. (6) Kinds: approve_skill_graph, approve_blueprint, dispose_finding, confirm_grade, reject_grade, resolve_attempt, void_diagnosis_run, void_revision_attempts, extend_diagnosis_run, close_diagnosis_run, release_diagnosis, record_consent, kind_override. Resolve, void, extend, close, confirm and reject take student and subject from the attempt or the run, because the engine reads decisions by student and subject. A reason (`reason_it`, at least 3 characters) is required wherever the teacher acts on something. A decision can name only the latest graph or blueprint revision.
- **Why:** The rule needs several independent locks; the token check inside the controller is the one that does not depend on the environment.
- **Cost:** The pages of M9b still have to be built on these routes. The proxy-side checks (Authelia, the cookie-only endpoint) belong to M7a.
- **Status:** implemented in M9a
- **Back-port:** D-08 (groups, user agent and path columns; 404 on the other listeners with forgery protection on).

## D-060 · 2026-10-03 · M9a approval gates and what a run pins

- **Design ref:** B-07, M6 `approvable?`, M10's D-046 note
- **Design said:** the blueprint is approvable when its pinned items are approvable and were opened in the preview, the test was played once as the preview student and its graph is approved; runs pin the approved revision; a newer draft never un-approves.
- **We do:** (1) `Approval::BlueprintGate.check` lists what is missing: the graph revision of the blueprint is the approved one; every pinned item revision (entries and descent) passes `Review::Gate`; an app_event `teacher_viewed_item {item_revision_id}` exists for each; the preview student has a closed run pinned to this very revision (context teacher_preview). `approve_blueprint` is refused with the reasons otherwise. (2) A subject is approved when an approved graph and an approved blueprint exist (the latest decision of each kind); a newer draft changes `pending_revision` only. (3) `Conductor.create_run` pins `approved_blueprint` for the student (nil without it: no run starts) and the latest draft for the preview student; this replaces the "latest" pinning of D-046. The student's list (`Availability`) reads the approved blueprint. (4) `PlanLoader` serves only pinned item revisions whose latest validation passed. (5) `banco status --json` adds `warmup_completed`, `consent_recorded` and `diagnosis.released` at top level; the per-subject fields (`graph_approved`, `blueprint_approved`, `stage`, `pending_revision`) were already there; `stage` stays `approved` while a newer draft waits. (6) Every sitting records `condition: unsupervised` (operator Q4); no decision records it.
- **Why:** Approval must be a checklist the software can show, not a memory of the teacher.
- **Cost:** "Played the whole test" is a closed preview run; nothing checks which answers the teacher gave. A teacher who approves must replay after any new draft.
- **Status:** implemented in M9a
- **Back-port:** B-07 (the gate and the pinning), C-04.

## D-061 · 2026-10-03 · M9a release, consent, kind_override and confirm with edits

- **Design ref:** D-002 (operator Q1), B-11, X-03, C-04
- **Design said:** `release_diagnosis` needs the consent and the warm-up; all subjects start together; the teacher can edit a proposed grade; kind_override changes a skill's kind.
- **We do:** (1) `release_diagnosis` is possible only when `record_consent` exists, the student's warm-up is completed and every subject row has an approved graph and an approved blueprint (all together, no waves); it can be recorded once. `record_consent {acknowledged}` can be recorded once. (2) `confirm_grade {grade_proposal_id}` copies `attempt_id` and `passed` (the proposal's `meets_threshold`) for the engine. With `scores {point_id: n}` the decision is an edit: it carries `edited: true`, the scores, the total and the new `passed`, and a reason; the decision row is the new grade and the proposal stays unchanged. No attempt_gradings row is written, so the engine sees one confirmation. `reject_grade` lets the attempt be proposed again. (3) `kind_override {skill, kind: recover|learn, reason_it}` is a decision on the subject; `PlanLoader` puts the latest one per skill on top of the blueprint's own `kind_overrides`.
- **Why:** One place (the decision row) holds what the teacher decided and why; the engine reads it as it already does.
- **Cost:** Changing a kind after a run has started changes that run's plan. Done before the release this is harmless; later it needs a void.
- **Status:** implemented in M9a
- **Back-port:** X-03 (edits are in the decision), C-04.

## D-062 · 2026-10-03 · M9a bin/reconcile-decisions reads the ledger only

- **Design ref:** D-08
- **Design said:** the nightly reconciliation matches each decision to a Traefik access-log line and writes reconcile.jsonl; `--json` prints `{orphans, unverifiable, items}`.
- **We do:** `bin/reconcile-decisions --since 1d|36h|90m [--json]` (`DecisionReconciliation`) reports as orphans: a decision without provenance (no login, request id, remote address or `banco-teacher` group, an unknown kind, a payload that is not an object); an attempt grading with source `teacher` that no decision names; a student run that started before `release_diagnosis` or is pinned to a revision without an earlier `approve_blueprint`. It exits 1 on any orphan. The proxy-log matching, `reconcile.jsonl` and ntfy are not built: the JSON says `"proxy_log": "not_checked"` and `unverifiable: 0`.
- **Why:** The ledger half needs nothing from the host; the log half needs the infrastructure of M7a.
- **Cost:** Until then a decision written by someone with database access and good-looking provenance is not caught.
- **Status:** implemented in M9a (log matching with M7)
- **Back-port:** D-08.

## D-063 · 2026-10-03 · M9b the teacher's screens, Rimanda and the measured minutes

- **Design ref:** C-04, B-07, A-05, operator Q2 (no daily budget)
- **Design said:** /teacher shows the subjects, the graph for approval, the entry test one screen per skill with "Rimanda" going back to the agent as a comment, the evening corrections, and measures the teacher's minutes per unit.
- **We do:** (1) Read-only pages on the web listener, teacher only: `/teacher` (subjects with stage, counts, what waits, minutes), `/teacher/subjects/:key/graph` (scope labels, edges, cited lines with the imported text, flags from `config/banco/review_flags.yml` for the Q3 lines 91-100 and the Spanish second-year report, a diff against the approved revision), `/teacher/subjects/:key/test` (the gate with its reasons in Italian, the two simulate traces all-correct and all-wrong, "Prova tutto il test come S") and `/teacher/subjects/:key/test/skills/:skill` (every pinned item side by side: four samples with key, typical-error ids and values, steps, error catalogue, sources, the review, the blind solve, the findings with their dispositions, "Prova come S" for one item at `/teacher/items/:id/play`, drawn by the student's own renderer and never saved), `/teacher/corrections`, `/teacher/subjects/:key/report`. Opening a skill screen writes the `teacher_viewed_item` events the gate asks for (not from the student's computer). (2) "Rimanda" is a decision kind, `send_back_item {item_revision_id, reason_code, comment_it}`, taken like every other decision (DecisionRecorder). The agent reads the comments as `teacher_comments` in `banco work open` and `banco work status`; `banco status` counts `items.sent_back`. A sent-back revision fails `Review::Gate` ("a new revision is needed"), so the blueprint pinning it cannot be approved. A fix request on a finding says that a new revision is expected until one exists. (3) Minutes: `/teacher/activity` takes a beat from the page while it is visible and used, and writes one app_event `teacher_active {unit}` at most every 55 seconds; one event is one minute. `banco status` reports `teacher_minutes {total, by_unit, by_subject}`. Units: `<subject>:graph|test|report`, `evening`, `home`. (4) The consent and "Apri la diagnosi" screens are not built here (the routes exist since M9a).
- **Why:** The teacher approves a subject in two decisions with everything in front of them; the agent must hear what was wrong without a decision route of its own; the opening date is worked out from the measured pace.
- **Cost:** The page shows the agent's raw LaTeX in the side-by-side samples; "Prova" is where the markup is drawn. Beats are only as good as the browser: a teacher reading without moving the pointer for a minute loses that minute.
- **Status:** implemented in M9b
- **Back-port:** C-04, B-09, Q2.

## D-064 · 2026-10-03 · M9b the report (B-09): shape, no student text in the API

- **Design ref:** B-09, operator Q4, Q8
- **Design said:** `banco diagnosis report [--subject KEY] --json`, format `banco.diagnosis_report/1`, a golden test in Go; per subject the entry test used, the state, the form of the graph, sittings with counted minutes, per skill state, reason, scope, kind, evidence, programme lines; observed errors; signals `rapid_share`, `dont_know_share`, `sitting_condition`; `next_steps` at the start of 1b.
- **We do:** `Diagnosis::Report` builds it; `GET /api/v1/diagnosis/report?subject=` and the page `/teacher/subjects/:key/report` use the same hash. (1) The API leaves out the student's own words: the agent that reads it may be on another provider than the grader (operator Q8), so errors carry `example_attempts` (ids) and the page adds `examples` (the answers in words). (2) Subject status: `not_started`, `in_progress`, `paused`, `continue_next_day`, `completed` (closed, or held only for pending answers, as the student's list does), `to_redo` (the teacher voided the run). (3) `graph_form` is `fixed_form` when no skill has a prerequisite or a composition, otherwise `adaptive`. (4) `rapid_share` counts answers whose counted time is under 0.2 of the expected seconds (flag over 20 per cent); `dont_know_share` flags over 50 per cent; `sitting_condition` is always `unsupervised`. (5) `groups` splits the own skills into demonstrated, to_recover, to_learn (kind learn, as the end screen does), pending and not_assessed. (6) The Rails examples are the contract (`contract/examples/diagnosis-report.completed.json`); the Go test decodes that very file with unknown fields refused, so a new or renamed member fails the build until the CLI's shape is updated on purpose. `next_steps` is not written (1b).
- **Why:** One hash for the agent and the teacher, with the privacy line of Q8 drawn in the code and not in a promise.
- **Cost:** The agent cannot quote a student's answer from the report; it asks the teacher.
- **Status:** implemented in M9b
- **Back-port:** B-09.

## D-065 · 2026-10-03 · M9b banco health and bin/preflight

- **Design ref:** E-02 (health), the infrastructure section (preflight)
- **Design said:** `banco health --json` with `.db`, `.grader`, `.chrome`, `.chrome_egress`; `bin/preflight` measures only what S feels (p95 of `/up`, `/up/deep`, PSI, MemAvailable, an unhealthy container).
- **We do:** `Health.check` (also `GET /api/v1/health`, `banco health [--no-chrome]`, and `bin/preflight [--no-chrome]`, which exits 1 when `ok` is false): the database is written to inside a rolled-back transaction, Solid Queue has a heartbeat (production only; `not_applicable` elsewhere), the grader worker answers a ping, Chrome answers behind the shared lock (`busy` is not a failure), `chrome_egress` is `blocked` when the sidecar is configured and an address outside the network cannot be loaded (`not_configured` without it), disk free over 1 GiB, the newest file of `BANCO_BACKUP_DIR` younger than 36 hours when the variable is set, and the decisions flag and the release state are reported without gating.
- **Why:** The health the agent and the operator can ask for today, from inside the application.
- **Cost:** The latency percentiles, PSI and memory gates, the container health and the 5-minute timer with ntfy belong to the host (M7) and are not here; `bin/preflight` says nothing about them.
- **Status:** implemented in M9b, host measures with M7
- **Back-port:** E-02.

## D-066 · 2026-10-03 · M9b Atkinson Hyperlegible and the student's theme and size

- **Design ref:** B-11, E-10
- **Design said:** Atkinson Hyperlegible at 20 px (18 at least), line height 1.5 at least, left aligned, no italics, cream, light and dark themes of contrast 7:1, a preference for theme and text size.
- **We do:** The font is vendored (`public/vendor/atkinson-hyperlegible@5.3.0`, woff2 normal 400 and 700, latin and latin-ext, with the SIL Open Font License and checksums) and is the first family of every page, the student's and the teacher's. The student's choice is kept on the server as app_events `student_preference {theme, size}` (the latest counts): theme `cream` (default) or `dark`, size `normal` (20 px), `large` (24) or `larger` (28); the layout puts them on `<html>`, and the item renderer, all in rem, follows. The dark theme is no longer chosen by the system; it is the student's choice.
- **Why:** The choice follows the student to any computer, and a preference is not a ledger of anything else.
- **Cost:** A student who liked the dark system theme has to say so once. The light theme stays in the stylesheet but has no button.
- **Status:** implemented in M9b
- **Back-port:** B-11, E-10.

## D-067 · 2026-10-03 · M9b structure.sql check and the Chrome lock test

- **Design ref:** E-01 (schema in CI), M5 and M10 integrator notes
- **Design said:** `db/structure.sql` is the schema and CI keeps it honest; the integrator saw a discrepancy of 212 lines between the file and the migrations.
- **We do:** `bin/check-structure` drops, creates and migrates a throwaway test database, dumps it and diffs the dump with the committed `db/structure.sql` (it puts the committed file back whatever happens); it is a CI step before the tests. The investigation: on one machine the 212 lines do not reproduce (a fresh dump equals the committed file at HEAD, and after `db:schema:load`). The first CI run of this check failed all the same, and its diff showed why: Rails dumps with the machine's `sqlite3` command line, whose `.schema` spells every table `CREATE TABLE IF NOT EXISTS` on the CI runner's version and plain `CREATE TABLE` on the newer one used to commit the file. That is a difference of spelling in every statement (a few hundred lines) and no difference of schema, and it is the most likely source of the integrator's discrepancy (not proven: that tree is gone). The check therefore compares the two dumps with that spelling removed. The check makes a regression of this kind fail in CI. `test/validation/chrome_runner_test.rb`: the two lock tests use a lock file of their own (`BANCO_CHROME_LOCK`); the shared `tmp/chrome.lock` is also taken by the Chrome tests of the other parallel workers, and a try-lock that must succeed was Busy when one of them held it for minutes under load. The tests that use Chrome keep the shared lock on purpose.
- **Why:** A schema that CI does not rebuild drifts at every merge of parallel migrations; a test that depends on who else holds a lock is a timing accident.
- **Cost:** About 30 seconds in CI.
- **Status:** implemented in M9b
- **Back-port:** E-01.

## D-068 · 2026-10-03 · M9b how the teacher's forms decide and word refusals

- **Design ref:** D-08, B-06
- **Design said:** Decisions are POSTs under /teacher; the reasons of a refusal are plain text for the page to word.
- **We do:** The forms post to the same routes as before and carry `back` (a path under /teacher only). For a browser (not JSON) the controller redirects back with a flash: what was recorded, or why not, in Italian (`Teacher::Wording` knows the gate and refusal sentences and shows an unknown one as it is). The buttons stay disabled, with the reason beside them, while the gates are open, while decisions are off (`BANCO_DECISIONS_ENABLED`) and on the student's computer. The one-click buttons of the evening screen ("Giusta", "Sbagliata", "Come Non lo so") send the reason written in the field, which starts as "Deciso dal docente alla schermata serale."; "Conferma" of an untouched proposal needs none. The command `bin/rails test:system TEST=file` of the brief does not accept a file in this Rails; use `bin/rails test test/system/<file>`.
- **Why:** Efficient approval with every decision still carrying its reason.
- **Cost:** A pre-filled reason can be left unchanged; the ledger then says so honestly.
- **Status:** implemented in M9b
- **Back-port:** C-04.

## D-069 · 2026-10-03 · review fixes: privacy of the list, image and log; engine and grading corrections

- **Design ref:** D-015, D-022, D-029, D-030, D-032, D-040, B-02, B-05, X-03
- **Design said:** D-015: the forbidden-term list lives in bin/hygiene. B-05: counted time. B-02: item 1 of a skill is hard to guess. D-029 point 7: a float-method grading is pending whatever its verdict. D-040: an accent slip earns credit only when the item says accent_policy flag.
- **We do:** (1) The term list is private data and no longer in git, not even split into fragments: bin/hygiene reads it from the CI secret `HYGIENE_TERMS` and from the untracked file `prep/hygiene-terms` (one term per line), and says so when it has neither; this replaces the "list lives in that script" of D-015. The history before this commit still holds the old script; rewriting it is the operator's decision. (2) `.dockerignore` excludes `/prep` and `/.claude` (briefs/ is served at runtime and stays). (3) The request log filters the answer and free-text parameters (`raw`, `reason_it`, `comment_it`, the agent bodies) at any depth. (4) Time: a pause or hidden interval still open when a sitting starts or an item is served ends there (a closed tab never sent "visible"), so it cannot swallow the counted time of later items. (5) An abandoned short answer is served again (it has one instance); a testlet that does not fit no longer keeps the short answer from being served. (6) A pinned descent skill needs at least one hard-to-guess instance (E-POOL-REDO, rule descent_low_guess), as an entry does. (7) Grading: trailing punctuation is stripped in one linear pass (a 20 KB answer took 16 s); a decimal exponent above 400 is invalid (number_too_large) instead of a 30 s BigInt power; a retried answer that turns out invalid settles as an undetermined row with error code invalid_answer for the teacher, instead of staying ungraded for ever; the engine reads float-method rows as pending and the accent-slip rule from Grading::Evidence's definition (policy flag, every code in the allowlist); a fraction with a negative denominator or a negative numerator beside a whole part is invalid (negative_denominator, signed_fraction_part) and a mixed number whose fractional part is not proper is wrong_form (improper).
- **Why:** The findings of the review: a public file that named the student, an image carrying private material, answers in logs, and several places where two readers of the ledger or the clock disagreed.
- **Cost:** CI needs the HYGIENE_TERMS secret to run the term check; a descent skill of only guessable items must get a harder item; 1e500 is refused as a number.
- **Status:** implemented
- **Back-port:** B-02, B-05, X-03.

## D-070 · 2026-10-04 · operator Q8-bis · reviewer and blind solver need another model, not another family

- **Design ref:** A-08, D-008 (operator Q8)
- **Design said:** The reviewer and the blind solver are of a known model family different from the family of every author session of the item (omp, another family).
- **We do:** The operator decided on 2026-10-04 that Sonnet reviews and blind-solves and Opus writes. `config/banco/providers.yml` gives `reviewer` and `solver` the rule `different_model_from: author` in place of `different_from: author` plus `known_family: true`: the model of the session must differ from the model of every author session of the item (compared case-insensitively, a leading `provider/` ignored); the family may be the same and may be unknown. A different session was already required (`E-SESSION-NOT-INDEPENDENT`, ItemSessions). A same-model session is `E-PROVIDER-NOT-ALLOWED` at use. The grader stays `allow_families: [anthropic]`. The briefs `review.md` and `solve.md` and `docs/validation.md` say so. This supersedes D-008 for these two roles.
- **Why:** The operator's choice of cost and quality; the guard keeps against the same model grading its own work, without proving anything (the model is declared).
- **Cost:** A Sonnet and an Opus share a family and may share blind spots; the teacher disposes of every finding in any case.
- **Status:** implemented
- **Back-port:** A-08.

## D-071 · 2026-10-04 · agent sessions are bound to their token; token roles limit session roles

- **Design ref:** A-04, D-05
- **Design said:** A session is an id the CLI sends in `X-Banco-Session`; the token only authenticates.
- **We do:** `agent_sessions.token_id` (migration 20261004200001) holds the public id of the token that created the session. `require_session` refuses a session of another token (422 `E-SESSION`); a session row without a token (made before this column, or by tests) is not bound. Token roles map to the session roles they may open and use (`ApiToken::SESSION_ROLES`): `agent_claude` author, verifier, reviewer, solver, grader; `agent_omp` the same without grader; `ci` none. `POST /api/v1/sessions` and `require_session` answer 422 `E-SESSION-ROLE` otherwise (the code gains `session new` in the contract). The format of `banco.*/1` documents does not change; the table keeps its append-only triggers (a nullable column was added).
- **Why:** A token that leaked or a second agent could otherwise act in another agent's session (a reviewer session reused as a grader, for instance).
- **Cost:** An agent must open its session with the token it uses.
- **Status:** implemented
- **Back-port:** A-04.

## D-072 · 2026-10-04 · production host authorization

- **Design ref:** D-016, E-01
- **Design said:** Three listeners; edge trust by address.
- **We do:** `config.hosts` in production is `Banco::Hosts.allowed` (`lib/banco/hosts.rb`): `banco.scc.im`, `banco`, `banco-harness`, `127.0.0.1`, `localhost` (ports are ignored by Rails) plus the comma-separated `BANCO_EXTRA_HOSTS`. `/up` is excluded so the container health check (`Host: localhost:3000`) works. Any other `Host` is 403.
- **Why:** DNS rebinding protection; Rails left it commented out.
- **Cost:** A new internal name needs `BANCO_EXTRA_HOSTS`.
- **Status:** implemented
- **Back-port:** E-01.

## D-073 · 2026-10-04 · audit lows

- **Design ref:** A-01, A-06, B-02, B-05, X-03
- **Design said:** See each rule.
- **We do:** (1) The latest revision is read inside the transaction in `Validation::Submission#store!` and in the graph and blueprint submits: a concurrent identical submit is a replay, a different one `E-STALE-BASE` (409), never a unique-index 500. (2) The expression grader refuses an Italian thousands separator ("1.000", "1.500.000": a group of three digits after a dot, not after a leading 0) as invalid `thousands_separator`, not 1.0. (3) The number and fraction parsers read every Unicode space as a space and every minus and plus look-alike as the plain sign; ZWSP, ZWNJ, ZWJ, word joiner, BOM and soft hyphen are removed; any other character (fullwidth digits, superscripts) stays and the answer is invalid. The text normaliser removes the same invisible characters (it used to turn ZWSP into a space). (4) A `normalized_text` key, error value or accepted text that normalizes to nothing (only punctuation) is refused: `E-GEN-SCHEMA` for an instance key, `E-SCHEMA` for `accept`. (5) An open item is abandoned after `ABANDON_GAP_SECONDS` of counted time (wall time minus pause and hidden, uncapped), not wall clock. (6) A skill with one C and one W that reaches `MAX_SERVED_PER_SKILL` with nothing pending ends `to_recover(mixed)`, not `not_assessed(item_cap)`.
- **Why:** The low findings of the audit.
- **Cost:** "1.000" and "2.500" are refused as answers; a student must type 1000 or 1,5.
- **Status:** implemented
- **Back-port:** A-01, B-02, B-05.

## D-074 · 2026-10-04 · reference texts: agents list and read, the operator imports

- **Design ref:** A-06, E-QUOTE-REF
- **Design said:** An item quotes an imported reference text through `prompt.quote {ref, text}`; only the Costituzione is seeded.
- **We do:** `banco reference list` and `banco reference show --key KEY` (GET `/api/v1/references[/:key]`, read only) tell an agent which texts exist and give their body, so a quotation is copied as an exact substring. Importing stays with the operator: `bin/rails banco:reference:import KEY= TITLE= SOURCE_URL= FILE=path|-` (source required, sha256 recorded; an existing key with other text is refused). No API route writes a reference text, and the stem limits (60 words, 25-word sentences) are unchanged. The brief `diagnosis-item` says where a passage goes and what to do when none is imported.
- **Why:** An agent that cannot cite a source would put excerpts in the stem or in unlinted option texts. An agent-writable import would let an agent invent a "source" its own quotation then matches.
- **Cost:** A new excerpt needs one operator command.
- **Status:** implemented
- **Back-port:** A-06.

## D-075 · 2026-10-04 · partial exclusions, per-line coverage detail, inherited block markers, W-SCOPE-MARKER

- **Design ref:** C-01, A-06
- **Design said:** `excluded[]` is `{line, reason_it}` (whole lines); coverage counts a line as covered once any skill cites it; E-SCOPE only checks that previous-year refs are present; the star marker is stored on the header line only.
- **We do:** (1) `excluded[]` takes an optional `fragment` (an exact substring of the line, else E-SOURCE `fragment`): the exclusion covers that part only. Existing graphs are valid unchanged (`banco.skill_graph/1` stays). (2) `coverage` adds `partial[]`: for each cited or fragment-excluded line whose text is not wholly inside cited or excluded fragments, `{line, text, cited[], excluded[], unaccounted[]}`. It is informational for a cited line (`uncovered` keeps its meaning); a line that is only fragment-excluded and still has unaccounted text is listed in `uncovered`. The other keys are unchanged. (3) `syllabus lines` adds `block_marker` and `block_marker_line` to a line under a marked header (a marked line ending in ':' or short without closing punctuation; the block runs to the next marked line, header-looking line, blank or transcriber line). It is a heuristic that can end a block early, never extend it past a header. Nothing is stored; the rows are unchanged. (4) New warning `W-SCOPE-MARKER` (registry version 3): a skill's scope is not among those the markers of its cited prima lines imply (star: integration_studied; empty star or both: in_progress; none: studied), using the line's own or inherited marker. A warning, because a skill may span lines of two kinds. The teacher's graph page shows a fragment exclusion with its fragment.
- **Why:** The teacher's coverage view hid parts of a line that no skill measures, and an agent reading one line could not see the star of its block.
- **Cost:** A short bullet under a starred header can look like a header and end the block early (no warning is raised there).
- **Status:** implemented
- **Back-port:** C-01, A-06.

## D-076 · 2026-10-04 · a form that is the item's own skill carries its first violation as the error code

- **Design ref:** B-03, X-03
- **Design said:** a `wrong_form` whose form is the skill itself is a W; descent goes to the implicated prerequisites of the typical errors, plus all direct parents if some W had no catalogue code.
- **We do:** `Diagnosis::EventLoader` gives that W (form `skill`, no typical-error code) the first entry of `form_violations` as its `error_code` (`not_fully_factored`, `not_lowest_terms`, ...). A graph error with that code and `implicates: []` keeps the descent in the node; a code the graph does not declare is still unclassified and descends to the parents. A typical-error code the grader returned is never replaced. Stored rows and the frozen formats are unchanged.
- **Why:** an answer such as `2x(x^2 - 9)`, right in value and incomplete in form, sent the student into prerequisites that were not the cause, and a graph could not declare an in-node form error.
- **Cost:** a graph that never declared the code behaves as before (parents).
- **Status:** implemented
- **Back-port:** B-03.

## D-077 · 2026-10-04 · solution items accept an inequality as the answer

- **Design ref:** A-01
- **Design said:** the `solution` form accepts `x = value` (or the bare value).
- **We do:** the checker parses `<`, `<=`, `>`, `>=` (`\le`, `\leq`, `\lt`, `\gt`, `\ge`, `\geq`, `<=`, the Unicode signs). On an item whose `form` has `solution`, a relation with the unknown alone on one side is canonical (`-3 > x` is `x < -3`); it equals another relation only with the same direction (strict versus non-strict counts) and an equal bound. Answer and error values may be relations, so `x > -3` can be a typical error `direction_not_flipped`. A relation never equals an equation or a bare number. The other `solution` and number-form constraints apply to the bound (`lowest_terms`, no operation left). Chains (`-5 < x < -3`) and a relation on an item without the `solution` form are `invalid` (`unsupported_operator`), as before. Vectors `ineq-*` in `test/fixtures/grading/vectors.json`. `banco.*/1` formats unchanged.
- **Why:** the natural hard-to-guess item for a first-degree inequality is to type the solution set.
- **Cost:** compound solutions (intervals, unions, systems of inequalities) are still out; use a choice item.
- **Status:** implemented
- **Back-port:** A-01.

## D-078 · 2026-10-04 · generator items run `tests`; the leak scan folds exponent braces and product dots

- **Design ref:** A-06
- **Design said:** `tests.must_accept`, `must_reject` and `blank` are exercised by the round trip; the leak scan compares keys with whitespace and `\left`/`\right` removed.
- **We do:** (1) a generator item's `tests` run against the first stored instance, as for a static item (before they were ignored). `must_reject` and `blank` are instance-independent in practice; a `must_accept` value must be right for every instance, so a generator item normally leaves it empty. (2) `Answers.squash` also drops `\cdot`, `\times` and `*`, and rewrites `^{d}` and `^(d)` to `^d` for a one-token exponent, so `4x^{2}y` in a stem or a cell matches the key `4x^2y` (E-SOLUTION-IN-DISPLAY, W-ANSWER-IN-STEM). The dotted abbreviations m.c.m., M.C.D., C.E. were already protected in the sentence split (19643d3). `banco.*/1` formats unchanged.
- **Why:** content agents reported the tests being silently ignored for generators and a leak slipping past a brace-style difference.
- **Cost:** a generator item with an instance-dependent `must_accept` now fails E-ROUNDTRIP; remove it.
- **Status:** implemented
- **Back-port:** A-06.

## D-079 · 2026-10-04 · `isolate` form for literal keys; `exclude_params` on items

- **Design ref:** A-06, brief rule 12
- **Design said:** `solution` strips `x =` but needs a number on the other side; the brief named `exclude_params` without a field for it.
- **We do:** (1) form `isolate` (expression items with an `unknown`): the answer `r = I/(Ct)` and `I/(Ct)` both grade as the key `I/(C t)` (the `unknown =` is stripped from the answer, the key and the error values; any expression may stand on the other side; an equation for another letter is `wrong_form` `not_a_solution_statement`). Without the form nothing changes. (2) `banco.item/1` gets an optional top-level `exclude_params` (1 to 30 strings): values of the exam that no instance may show. Each entry is searched in the display, the answer and the error values (whitespace, `$`, `\left`/`\right` removed; an entry that starts or ends with a digit does not match inside a longer number, so `7` does not hit `17`); a hit is `E-PROVA-A-PARAMS` rule `excluded` on every listed or generated instance. The field is optional, so existing items stay valid; a generator may still exclude values itself.
- **Why:** content agents reported that a letter-key answer could not be graded in the `r = ...` form, and that the brief named a field nothing implemented.
- **Cost:** a substring-style match: an excluded fraction written another way (`\frac{28}{5}` vs `28/5`) is not caught; list each written form.
- **Status:** implemented
- **Back-port:** A-06.

## D-080 · 2026-10-04 · `reduced` form for algebraic fractions; E-ACCEPTS-RANDOM ignores value-equal candidates

- **Design ref:** A-06
- **Design said:** `lowest_terms` checks numeric fractions and integer content; E-ACCEPTS-RANDOM flags any random answer the grader marks correct.
- **We do:** (1) expression form `reduced`: for every fraction whose numerator and denominator are polynomials (degree 9 or less) in one and the same letter, both are interpolated exactly over Q from sampled values and their GCD is computed; a GCD of degree 1 or more is `wrong_form` with `common_factor_not_cancelled` (so `(x^2-16)/(x^2-4x)` against the key `(x+4)/x` is W). Several letters, non-polynomials and numeric fractions are not judged by it. (2) E-ACCEPTS-RANDOM skips a random expression candidate that equals the key in value (graded against the key with no form and no declared errors): `1x+4` and `1(x+4)` for the key `x+4` are the key, not a grader fault. (3) Generator `tests` already run on the first stored instance since D-078 (the report predates that reading of `item_runner`); nothing else changes, `tests` stays required with empty arrays allowed. `banco.*/1` formats unchanged; the new form and code are additive.
- **Why:** content agents reported that retyping the unsimplified fraction was credited, and a sound item failing E-ACCEPTS-RANDOM by chance.
- **Cost:** `reduced` does not look inside several-letter fractions; a fraction with a numeric common factor is still for `lowest_terms`.
- **Status:** implemented
- **Back-port:** A-06.

## D-081 · 2026-10-04 · per-instance `accept`; the item prompt in the leak scan; `W-FORM-SKILL-CLOSURE`; `E-MATCHING-RIGHT-MARKUP`

- **Design ref:** A-06, A-01
- **Design said:** `accept` belongs to the item; the leak scan reads the instance display; `form_skill` only has to exist in the graph; the right column of a matching is free text.
- **We do:** (1) `banco.item/1` instances (listed or generated) may carry an optional `accept` (up to 10 strings, normalized_text only, else `E-GEN-SCHEMA`): other spellings of that instance's key, added to the item's `accept` for that instance alone (Spec, round trip, tests, leak scan). It is stored in a new nullable column `item_instances.accept_json` (migration; rows before it have none) and shown to the verifier and the reviewer. The instance hash and fingerprint are unchanged when there is no `accept`. (2) The leak scan also reads the item `prompt` (stem, table, quote, figure text): a key in a non-stem prompt string, or a choice key in the prompt stem, is `E-SOLUTION-IN-DISPLAY`; the expected answer in the prompt stem of a non-choice item is `W-ANSWER-IN-STEM` (field `/prompt/stem_it`). An item whose prompt names the answer format on purpose gets the warning, which is meant. (3) New warning `W-FORM-SKILL-CLOSURE`: a `form_skill` that is not a prerequisite (or composite part), direct or transitive, of the item's skill. The grader still credits the declared form, but the fold drops the tail suspect, as docs/rules/diagnosis-1.md section 2 says; the fix is a graph edge or no `form_skill`. (4) New error `E-MATCHING-RIGHT-MARKUP`: `$`, a backslash or `**` in a right-column text, because it is drawn as a native option that shows plain text. Use Unicode (`x ≤ -2`). Registry version 4. Tests on generator items and `exclude_params` were already done (D-078, D-079); a generator item's tests refer to its first stored (first clean seed) instance. `banco.*/1` stays backward compatible: every addition is optional.
- **Why:** content agents reported that a generator item could not accept another spelling on one instance only, that the prompt was not scanned, that a `form_skill` outside the closure silently lost its suspect, and that LaTeX in a matching right column shows raw.
- **Cost:** a migration; a few more findings on existing items (reviewed as warnings, except the markup error).
- **Status:** implemented
- **Back-port:** A-06, A-01.

## D-082 · 2026-10-05 · step consistency reads LaTeX decimal commas; the teacher's skill page renders solution markup

- **Design ref:** A-06, B-09
- **Design said:** `E-STEP-INCONSISTENT` compares the numbers in `solution.final` with the key of a number or fraction item.
- **We do:** before scanning, the check drops `$` and turns `{,}` into `,` (and reads `\dfrac` like `\frac`), so a final `$0{,}4$` is the number 0,4, not 0 and 4. The teacher's skill page draws each solution step and the final with `data-markup="inline"`, as the student's results page does, so `$...$` is not shown raw. Authors may write a final either way.
- **Why:** a content agent had to write a plain-text final for decimal answers to pass validation.
- **Cost:** none; no format change.
- **Status:** implemented
- **Back-port:** A-06.

## D-083 · 2026-10-05 · W-ANSWER-IN-STEM ignores a key inside a «quoted» sentence of a normalized_text stem; brief on accent_policy and per-instance accept

- **Design ref:** A-06
- **Design said:** W-ANSWER-IN-STEM fires when the expected answer appears anywhere in the stem; the brief said every item that does not measure accents sets `accent_policy: "flag"`.
- **We do:** (1) on a `normalized_text` item the check removes `«...»` spans from the stem (display and prompt) before looking for the key, so "write the subject of «Marco mangia»" with the key `Marco` is the material, not a leak; a key outside the quotes still warns. Other components unchanged (the quote-free text is only used for the warning; E-SOLUTION-IN-DISPLAY is untouched). (2) The brief now says `accent_policy` belongs to `normalized_text` items only (the validator keeps refusing it elsewhere with E-ACCENT-POLICY), explains the quote convention, and points at the per-instance `accept` of D-081, which already covers "i dolci" / "dolci" on one instance and "la musica" / "musica" on another. `banco.*/1` formats unchanged.
- **Why:** content agents reported warning noise on every analyse-the-sentence item, a brief that contradicted the validator, and (already fixed in D-081, staging had it) the missing per-instance accept.
- **Cost:** a key hidden in a quote is not warned about; the reviewer reads the stem anyway.
- **Status:** implemented
- **Back-port:** A-06.

## D-084 · 2026-10-05 · W-NEGATIVE-STEM ignores «quoted» and $math$ spans; CLI reports a missing contract header as E-NETWORK

- **Design ref:** A-06, CLI contract check
- **Design said:** W-NEGATIVE-STEM fires on any negation word in a stem; the CLI answered E-CONTRACT (rebuild the CLI) whenever X-Banco-Contract differed, including when absent.
- **We do:** (1) the negation patterns run on the stem with `«...»` and `$...$` spans removed, so a logic item that asks about «non (...)» is not warned; a negation in the instruction still is. (2) A response without an X-Banco-Contract header is E-NETWORK (next: retry in 60 s, then `banco health`); E-CONTRACT only when a non-empty digest differs. `banco.*/1` formats unchanged.
- **Why:** content agents reported a false warning on every logic-connective item and a misleading rebuild hint while the server restarted.
- **Cost:** a negation hidden inside quotes is not warned about.
- **Status:** implemented
- **Back-port:** A-06.

## D-085 · 2026-10-05 · per-instance `tests`; W-GRAPH-READABILITY

- **Design ref:** A-06
- **Design said:** item `tests` (must_accept, must_reject, blank) run on the first instance only; the readability lint reads item texts only.
- **We do:** (1) a `banco.item/1` instance may carry an optional `tests` object with `must_accept` and `must_reject` (answers, no `blank`); they are graded on that instance, with its own `accept` (D-081), after the item's tests, and are not stored. Findings point at `/instances/N/tests/...`. Per-instance `accept` itself already existed (D-081). (2) New warning `W-GRAPH-READABILITY`: every `*_it` text of a skill graph (error descriptions, names) goes through the item readability lint; an E-READ there is a warning, so the graph still passes but the author sees that the same text copied into an item error catalogue would be refused. Registry version 5. `banco.*/1` stays backward compatible: both additions are optional.
- **Why:** content agents reported that an alternative on a later instance could not be tested, and a graph sentence of 26 words passing the graph but failing in an item.
- **Cost:** a few more warnings on graphs; no migration.
- **Status:** implemented
- **Back-port:** A-06.

## D-086 · 2026-10-05 · matching: each answer once (hint and greyed-out entries)

- **Design ref:** A-06
- **Design said:** the matching hint read "Abbina ogni voce a una risposta."; nothing stopped the student picking one right-column entry for two rows.
- **We do:** the hint now says each answer is used once and one is left over (the right column is always longer than the left, enforced by validation); the browser greys out entries already chosen in other selects. Grading is unchanged (the key is injective, a duplicate pick is simply wrong). No format change.
- **Why:** a content agent had to repeat the rule in every matching stem.
- **Cost:** to swap two answers the student first clears one select.
- **Status:** implemented
- **Back-port:** A-06.

## D-087 · 2026-10-05 · W-ERROR-NOT-IN-GRAPH; an ordering is never shown as a declared error permutation

- **Design ref:** A-06, X-01
- **Design said:** validation checked only the skill keys an item implicates; the engine reads a skill's errors from the graph alone, so an item code the graph lacked was unclassified (descent into every parent) and item implicates that differed from the graph's were ignored, both silently. Serve-time re-keying redrew an ordering only when it equalled the key, its reverse or its stored listing; the widget starts non-empty, so an untouched answer equal to a declared error permutation was graded as that error.
- **We do:** (1) new warning `W-ERROR-NOT-IN-GRAPH` (registry version 6): an `error_catalogue` code (also of testlet sub items) that is not in `errors[]` of the item's skill in the graph, or whose `implicates` differ from the graph's. A warning, not an error, so items already approved stay valid; the brief says a new code must first be added to the graph. (2) `Rekey` takes the instance's declared errors and redraws an ordering that equals a declared error permutation (testlets per sub item). Matching is unchanged (its selects start empty). `banco.*/1` unchanged.
- **Why:** content agents reported both gaps (italian, B4).
- **Cost:** one more warning on items with free-form codes.
- **Status:** implemented
- **Back-port:** A-06, X-01.

## D-088 · 2026-10-05 · `passage_it` on a short answer is shown to everyone; allowed on a diagnosis item

- **Design ref:** A-06, X-02
- **Design said:** only a testlet's `passage_it` reached the student, the grader, the solver and the teacher; the schema accepted it on a `short_answer` but dropped it silently, and forbade it on a `diagnosis_item`, whose only room for a reading text was the instance stem (60 words).
- **We do:** (1) `passage_it` is read from the revision body for every kind: the student's page (`ItemPresenter`, `items/prompt.js`, with the testlet's "Brano" title), the grader payload, the blind-solver and reviewer instances (`Review::ItemText`), `Teacher::Corrections`, `Teacher::InstanceView` and `Diagnosis::Summary`. Reading from the body means revisions already stored work without re-materialising. (2) `banco.item/1` allows an optional `passage_it` (at most 2400 characters, readability lint as a passage) on a `diagnosis_item`. It is not counted in the 60-word stem cap. Backward compatible: optional.
- **Why:** content agents (italian) found a summary item whose source text nobody saw, and could not write expository-reading items with a text longer than about 50 words.
- **Cost:** none; no migration.
- **Status:** implemented
- **Back-port:** A-06, X-02.

## D-089 · 2026-10-05 · fingerprints independent of stored order; end-of-subject message from the item that erred

- **Design ref:** A-06, X-01, B-11
- **Design said:** `Validation::Canonical.fingerprint` hashed the display with arrays in stored order, while `Rekey` reshuffles choice options, ordering elements and matching columns at serve time; so E-GEN-POOL, E-POOL-REDO and the redo's "never repeat" could be satisfied by reordering one question. `Summary` merged every served item's error catalogue by code, so the last served item's `message_it` won.
- **We do:** (1) the fingerprint takes `options`, `elements`, `left`, `right` (any depth, so testlets too) without their `id` and sorted by canonical text; `validation_rules.yml` version 2 (stored with each validation). Instances already stored keep their old fingerprint (the ledger is append-only); items re-validated get the new one, so a pool is judged on the new rule only after revalidation. (2) `Diagnosis::Summary` takes the message from the first served item (on the skill, if any) one of whose gradings carries the code; the merged catalogue is only a fallback. `banco.*/1` unchanged.
- **Why:** content agents read the code and reported both.
- **Cost:** a pool that relied on reordering now fails E-GEN-POOL / E-POOL-REDO when revalidated; mixed old and new fingerprints can coexist for one item until then.
- **Status:** implemented
- **Back-port:** A-06, B-11.

## D-090 · 2026-10-05 · source kind `legal_text`; brief says which instance `tests` run on

- **Design ref:** A-06, X-02
- **Design said:** `banco.item/1` `source.kind` offered `prima_line`, `seconda_line`, `prova_a_structure`, `textbook`, `inferred`; a law (the Costituzione) could only be cited as `textbook`, which a reviewer may read as the student's own book. The brief did not say that the item's `tests` run on the first instance only (D-085 already added per-instance `tests`).
- **We do:** (1) `source.kind` gains `legal_text` (`ref` the act and article, optional `fragment`); no check changes, so it is only a label for reviewers. Backward compatible (enum widened). (2) Brief rules 10 and 12 state both points. Quoting a reference text still needs an imported text (`E-QUOTE-REF`); there is no import command and none is added.
- **Why:** content agents (law_economics, B3).
- **Cost:** none.
- **Status:** implemented
- **Back-port:** A-06, X-02.

## D-091 · 2026-10-05 · deferred cross-subject edges in the skill graph; `banco --help`

- **Design ref:** A-06, C-04
- **Design said:** a cross-subject prerequisite or implicate is accepted only when the target is in an approved graph (`E-GRAPH-EDGE-UNAPPROVED`). Content agents draft every subject before the teacher approves any graph, so the edges one subject owes another (percentages, fractions, obbligazione) had no place in the graph and lived only in agent reports. The CLI answered `--help` with `E-USAGE`.
- **We do:** (1) `banco.skill_graph/1` gains two optional members: `deferred_prerequisites[]` on a skill and `deferred_implicates[]` on an error, each `{skill, reason_it}` (a skill of another subject, at most 20). They are not checked against any approved graph, are not part of the engine, the closure or the cycle check, and are shown on the teacher's graph screen ("in attesa del grafo dell'altra materia") and in its diff. A target inside the graph's own subject or graph is `E-SCHEMA` (rule `deferred_own_subject`); a target already in an approved graph is the warning `W-GRAPH-DEFERRED-APPROVED` (use a plain edge). Nothing activates a deferred edge by itself: after the other graph is approved, the next revision moves it to `prerequisites` / `implicates` (the edge is checked then). Registry version 7. Backward compatible: both members optional. (2) `banco --help`, `-h` and `help` print the command names, args and flags from the embedded contract (local, no network, not a contract command).
- **Why:** content agents (business, step graph).
- **Cost:** a deferred edge does not steer the engine until it is moved; the move is a content revision.
- **Status:** implemented
- **Back-port:** A-06, C-04.

## D-092 · 2026-10-05 · matching as a classification (`display.reuse_right`)

- **Design ref:** A-06, X-01
- **Design said:** a `matching` pairs each left id with its own right id; the right column has n+1 entries (`E-MATCHING-SIZE`) and the key may not repeat a right id. Sorting 4 or more cases into 3 categories (law, history, geography, biology) could not be written; a content agent invented a fourth "category" to make the shape fit.
- **We do:** `banco.item/1` `display` gains the optional boolean `reuse_right`. When true the matching is a classification: the key may repeat right ids (it must use at least 2 different ones and only ids of the right column), the left column has at least 4 rows (as before), the right column has at least 3 categories and fewer entries than rows (`E-MATCHING-SIZE` otherwise), the right column is still plain text. Grading is unchanged (exact map; `correct_pairs` counts rows); `Rekey` shuffles both columns as before and keeps the flag; the student's page shows another hint and does not grey out an answer already used. Without the flag every rule is as before. Backward compatible (optional member). Generator `tests` already run on the first stored instance since D-078 (the report predates that), so that second report needs no change.
- **Why:** content agent (law_economics, B4).
- **Cost:** with 4 rows and 3 categories a blind guess is right once in 81 times (3^4), against 1 in 120 for a 4-pair matching: still hard to guess; use 5 or more rows when possible.
- **Status:** implemented
- **Back-port:** A-06, X-01.

## D-093 · 2026-10-05 · graph findings per skill; two-category classification; number `accept` and form `scientific`

- **Design ref:** A-06, X-01, E-03
- **Design said:** (1) a finding is keyed by code, field and rule, so two refused targets in one field (`E-GRAPH-EDGE-UNAPPROVED`, `E-SKILL-UNKNOWN`) merged into one finding that named only the first. (2) D-092 classification needs 3 or more categories. (3) a `number` item has one exact key and reads only a plain decimal; `accept` belonged to `normalized_text`.
- **We do:** (1) the finding key includes `detail.skill`: one finding per refused skill (repeats of the same skill and field still count). (2) A classification may have 2 categories when it has 6 or more rows (2^6 = 64 blind guesses, close to D-092's 81); with 3 or more categories the rule is unchanged (4 or more rows). (3) A `number` item may list `accept`: extra exact values (finite decimals, "273,15") graded `correct` like the key; each is checked as a number (`E-SCHEMA` otherwise) and enters the leak scan. A `number` item may declare `form: ["scientific"]`: the answer is read as `a·10^n` (also `a x 10^n`, `a×10^n`, `a*10^n`, `10^{n}`, superscript exponent; exponent beyond 400 is `number_too_large`); the right value is `correct` when 1 <= |a| < 10, else `wrong_form` with violation `scientific_notation` (a plain number is correct only when it is already in that range; use `form_skill` as for other forms). The student's box then shows its own hint and a text keyboard. Without the form, `5,2·10^-4` stays unparseable. Registry gains `scientific_notation`. Backward compatible: only optional members and new accepted values.
- **Why:** content agent (chemistry, step graph).
- **Cost:** a 2-category classification is guessable more often than one with 3 or more; prefer 3 or more categories or 7+ rows. `accept` values are not tried against the error catalogue.
- **Status:** implemented
- **Back-port:** A-06, X-01, E-03.

## D-094 · 2026-10-05 · testlet passage in the leak scan; "da solo" is not an absolute word

- **Design ref:** A-06
- **Design said:** (1) the leak scan of a testlet sub-item read only the sub-item's own display and prompt, never the testlet `passage_it`. (2) `solo` in the absolute-word list matched "da solo" (by oneself). (3) A third report said generator `tests` are never run: already done since D-078 (they run on the first stored instance), nothing to change; the staging build the agent used may have predated it.
- **We do:** (1) for a `choice` sub-item, a key option of 20 or more plain characters found word for word in `passage_it` is `E-SOLUTION-IN-DISPLAY` (field `/sub_items/N/instances/K/passage_it`). Shorter keys (a name in the story) are not checked: they are too common in a passage. (2) `da solo`, `da sola`, `da soli`, `da sole` are removed before `W-ABSOLUTE`; a bare `solo` still warns. The brief says so. `banco.*/1` unchanged.
- **Why:** content agent (law_economics, B5).
- **Cost:** a paraphrase of the key in the passage is still the author's and the reviewer's job; non-choice sub-items are not scanned against the passage.
- **Status:** implemented
- **Back-port:** A-06.

## D-095 · 2026-10-05 · binary profile reports declared errors; arrows and spreadsheet function names pass the readability lint

- **Design ref:** A-01, A-06
- **Design said:** (1) `normalized_text` with profile `binary` returned `wrong` for any answer that differs from the key without leading zeros, never consulting the declared errors. (2) The emoji pattern covered U+2190-U+21FF, so the assignment arrow and every arrow failed `E-READ`. (3) Spreadsheet function names (SOMMA, CONTA.SE) failed `E-READ` as ALL-CAPS words. (4) A report said a second refused cross-subject target on one field is not named: already fixed by D-093 (one finding per target, verified on staging), nothing to change.
- **We do:** (1) in the binary profile a declared error value is matched with leading zeros removed on both sides: `typical_error` with its code, `normalized` is the stripped form (so the roundtrip collision check sees 0101 and 101 as one answer). (2) The emoji pattern now starts at U+21A0: the arrows U+2190-U+219F stay allowed, the rest of the block and the pictographic ranges are still rejected. (3) An all-caps token directly followed by `(`, or by `.` and a letter (CONTA.SE), is a name, not shouting. `validation_rules.yml` version 3. `banco.*/1` unchanged.
- **Why:** content agent (computer_science, step graph).
- **Cost:** a real ALL-CAPS word glued to a bracket ("ECCO(") escapes the check.
- **Status:** implemented
- **Back-port:** A-01, A-06.

## D-096 · 2026-10-05 · testlet low-guess and choice per skill; accent-slip observation skill; graph `notes_it`

- **Design ref:** B-02, B-04, A-06
- **Design said:** (1) a testlet body has no top-level `component`, so the engine loader and the blueprint checks fell back to `number`: every testlet instance was low-guess and not a choice, even with five choice sub items. (2) `ORTHOGRAPHY_SLIP` gives C plus an observation on the orthography skill, but nothing ever named that skill, so the observation was lost. (3) `banco.skill_graph/1` had no place for a note to the teacher (the operator's programme flag, Q3). (4) A report asked for a multi-blank cloze (por/para): not a defect, see below.
- **We do:** (1) `Rules::V1.testlet_flags` reads the sub items' own components: per skill, low-guess when any sub item of that skill is hard to guess (all must be right), choice when all of them are choice. `Plan::Instance` gains the optional `flags` ({skill => {low_guess, choice}}); `low_guess_for(skill)` and `choice_for(skill)` fall back to the instance flags for every other kind; `Fold` and `Candidates` use them. `ItemInfo` gives `low_guess_by_skill` for testlet instances and the blueprint checks (`E-POOL-REDO`, `descent_low_guess`) read it for the skill they check. (2) `Rules::V1::ORTHOGRAPHY_SKILLS` maps `es_accents` to `spanish.accents` and `it_accents`, `it_apostrophe_accent` to `italian.spelling`; `EventLoader` sets `orthography_skill` on the slip, `Grading::Evidence.observations` names it. The credit rule is unchanged. (3) `banco.skill_graph/1` gains the optional `notes_it` (up to 10 strings of 400 characters), shown on the teacher's graph screen above the skills. (4) No change: a cloze with 2 options per blank is a classification (`reuse_right`, D-092/D-093): list the blanks as `left` rows and the options (por, para) as `right`, with 6 or more rows for 2 options (guess 1 in 64), or 4 or more rows with 3 options.
- **Why:** content agent (spanish, step graph).
- **Cost:** a testlet with one hard sub item for a skill is low-guess for that skill even if its other sub items are choice. Observations are noted only; they do not change the state of the orthography skill.
- **Status:** implemented
- **Back-port:** B-02, B-04, A-06.

## D-097 · 2026-10-05 · a dry run waits up to 25 s for Chrome before E-CHROME-BUSY

- **Design ref:** A-06
- **Design said:** a dry run takes the shared Chrome lock with a try-lock and answers 409 `E-CHROME-BUSY` at once when it is taken.
- **We do:** the dry run waits for the lock for `BANCO_DRY_RUN_CHROME_WAIT` seconds (default 25) and only then answers 409 `E-CHROME-BUSY` (same body, `retry in 30 s`). No queue, no new format. The job path is unchanged (it already waits).
- **Why:** content agent (law_economics, verify:B2): while other items validate, dry runs and submits answered 409 and worked on retry after 30 s. Most validations are shorter than the wait.
- **Cost:** a dry run holds an API Puma thread for up to 25 s while waiting (5 threads by default). A long validation still gives 409; the agent retries as before.
- **Status:** implemented
- **Back-port:** A-06.

## D-098 · 2026-10-05 · a testlet is charged as a serve to its first skill only; its sub items must share one skill (E-TESTLET-SKILLS)

- **Design ref:** B-02, D-037, D-047
- **Design said:** each sub item is an attempt on its own skill. D-047 built one attempt per serve, attributed to the testlet's first skill.
- **We do:** (1) `PlanLoader` and `Validation::ItemInfo` give a testlet instance one skill, its first sub item's. A serve is now charged, and left outstanding, for that skill only; before, every sibling skill got a serve with no answer, so a C,W pair ended not_assessed(item_cap) instead of to_recover(mixed) (§13), siblings burnt their cap and a sibling off the descent ended not_needed. (2) New item check `E-TESTLET-SKILLS` (error): every sub item of a testlet is on the same skill. (3) The simulator (`Plan.build_pool`) does the same for a testlet declared on several skills in the dry-run spec. (4) The brief and rules say so. The engine itself still accepts multi-skill instances (tested directly); per-sub-item attempts would lift the check.
- **Why:** content agent (english, step graph); suggested fix (a). Revisions already stored with mixed skills stay valid for reading, but fail E-TESTLET-SKILLS when re-validated: the content agent puts the sub items on one skill and resubmits.
- **Cost:** a passage can measure one skill only (the English plan already does).
- **Status:** implemented
- **Back-port:** B-02, D-047.

## D-099 · 2026-10-05 · one instance of a testlet item per run; a bare-blueprint dry run loads the pinned graph and items

- **Design ref:** B-02, D-047, D-098
- **Design said:** a testlet counts one outcome per skill (`TESTLET_OUTCOMES_PER_SKILL`), which nothing enforced; `simulate --blueprint FILE` simulates the file alone.
- **We do:** (1) `Candidates.for` leaves out every instance of a testlet item once one is served in the run, so one passage is never served twice and the rule is met by construction (a testlet has one skill since D-098). (2) `simulate` with a bare `banco.blueprint/1` loads the graph revision named by `graph_revision_id` (with foreign skills) and the passed stored revisions of the pinned items with their real instances, via `PlanLoader.for_document`. A pinned id with no passed revision gets synthetic instances; a graph revision that is not stored gives the old flat dry run; both add a `warnings` entry (E-SIMULATE-INPUT). A bundle with `graph` or `pool` is unchanged.
- **Why:** content agent (italian, step blueprint). The multi-skill testlet part of that report is D-098: sub items on several skills now fail E-TESTLET-SKILLS. The 'number' default for a testlet's component only applies when per-skill flags are absent; D-096 flags come from the sub items' own components.
- **Cost:** a dry run reads the database when the file names a stored graph.
- **Status:** implemented
- **Back-port:** B-02.

## D-100 · 2026-10-05 · E-VERIFY-REJECTS names every rejected seed with its reason; the dry run reports the verify phase

- **Design ref:** A-06, D-081
- **Design said:** E-VERIFY-REJECTS carries a count and the first seed.
- **We do:** the finding's detail adds `rejected_seeds` (`rejected_indexes` for listed instances), all of them, and `reasons` (reason text to the seeds it applies to). The result `details` (and so the dry-run answer) gains `verify: {checked, rejected}`. `seeds` and `count` are unchanged (additive; `banco.*/1` formats are not touched). The dry run was already the same `ItemRunner` as the job: verify runs over every clean seed of the 200, not only the 24 stored; this is now visible in `details.verify.checked`.
- **Why:** content agent (law_economics, verify B1). A verifier who sees 8 instances needed many submit cycles to find the failing seeds of the pool; the dry run was reported to pass where the real submit failed, which came from a verify.mjs edited between the two runs (not reproducible: a rejecting verify.mjs fails the dry run on staging with the same code).
- **Cost:** a larger finding detail (one seed list and a reason map).
- **Status:** implemented
- **Back-port:** B-02.

## D-101 · 2026-10-05 · the blueprint's own texts and flags are shown: intro note to the student, the rest to the teacher

- **Design ref:** B-02, C-04, rule 5 of the brief
- **Design said:** `intro_note_it` is what the student reads before starting; `not_measured_it` says what the test cannot tell; the teacher sees `redo_reserve: false` and reads `choice_only_reason_it`. Nothing rendered them; the sitting start screen took its calculator line from `Rules::V1.calculator`.
- **We do:** (1) The sitting start screen shows the run's pinned blueprint `intro_note_it` and takes its calculator line from the blueprint's `calculator` (the rule table is the fallback for old documents). The engine and the budget still read the rule table. (2) `/teacher/subjects/:key/test` gains a block with `not_measured_it`, `intro_note_it`, calculator, budget, `depends_on_subjects` and `kind_overrides` with reasons, and marks a skill with `redo_reserve: false` or a `choice_only_reason_it` (list and skill screen). (3) The report's `entry_test` gains `not_measured_it`, `calculator`, `budget`, `depends_on_subjects`, `kind_overrides` (additive, `banco.*/1` untouched), shown on the report page.
- **Also:** the first report (a bare-blueprint dry run ignoring graph and pool) was already fixed by D-099; staging ran that code.
- **Why:** content agent (math, step blueprint).
- **Cost:** none beyond the views.
- **Status:** implemented
- **Back-port:** B-02, C-04.

## D-102 · 2026-10-05 · amounts with the Italian thousands dot: a dedicated invalid code, no false positives in validation

- **Design ref:** E-03, A-06
- **Design said:** the number grader reads one separator; a dot is `use_comma` ("Per i decimali usa la virgola"). The validation scans read a dot as a decimal point.
- **We do:** (1) `Grading::Closed::Numbers` raises invalid `thousands_separator` for `5.300`, `5.300,00`, `5.300,00 €` (unless the item sets `allow_dot`), with the message "Scrivi il numero senza il punto delle migliaia, per esempio 5300,00." The answer is not read as grouped: the student is told how to write it, nothing is stored. (2) `E-STEP-INCONSISTENT` reads `solution.final` both ways (dot as decimal and as thousands grouping), so a final "5.300,00 €" matches the key 5300. (3) `Answers.token_match?` no longer counts a needle that follows `<digit>.` as a whole token ("150,00 €" inside "9.150,00 €" is not a leak). (4) The item `tests` of a generator item already run on the first stored instance (D-078); no change, the brief says so.
- **Why:** content agent (business, B2). New grader code is additive; stored data is unchanged.
- **Cost:** a leak of a key written right after "<digit>." is no longer found.
- **Status:** implemented
- **Back-port:** E-03.

## D-103 · 2026-10-05 · number: spaced thousands, and a unit that changes per instance

- **Design ref:** E-03, D-073, D-102, banco.item/1 (additive)
- **Design said:** digits separated by a space are `ambiguous_mixed_number`; the unit is declared on the item only.
- **We do:** (1) `Numbers.parse` raises `thousands_separator` for groups of exactly three digits separated by a space ("8 800", "1 600 000"; not after a leading 0); "1 2" stays `ambiguous_mixed_number`. The message is now "Scrivi il numero senza punti né spazi tra le cifre, per esempio 5300,00." With `allow_dot` the dot case stays a decimal (the item opted in; do not set it on items whose key is 1000 or more). (2) `display.unit` (optional, string, 20 chars) in an instance overrides the item `unit`: the presenter shows it as the suffix, `Grading::Spec.from_instance` and `Validation::Units.spec_for` strip it (also in testlet sub items). Existing items and instances are unchanged. (3) The `tests` of a generator item already run on the first stored instance (D-078, D-102 (4)); no change.
- **Why:** content agent (chemistry, B1 measures).
- **Cost:** none.
- **Status:** implemented
- **Back-port:** E-03, banco.item/1.

## D-104 · 2026-10-05 · DDT is an allowed acronym; --help works after any command word

- **Design ref:** A-06, D-091
- **Design said:** `readability.caps_allowlist` lists a fixed set of acronyms; `banco --help` lists the commands.
- **We do:** (1) `DDT` joins `caps_allowlist`; `validation_rules.yml` version 4. (2) `--help` or `-h` anywhere in the CLI line (`banco work --help`, `banco work status -h`) prints the same command listing. (3) No change to `work status --wait`: the status document goes to stdout, the error document (`E-...`, exit 3) goes to stderr; read stdout only (do not merge with `2>&1`).
- **Why:** content agent (business, B3).
- **Cost:** none.
- **Status:** implemented
- **Back-port:** A-06.

## D-105 · 2026-10-05 · E-PHRASE matches whole words only

- **Design ref:** A-06
- **Design said:** a text containing a banned phrase is E-PHRASE (substring match).
- **We do:** the phrase must not be preceded or followed by a letter or digit, so "la lezione di nuoto" no longer contains "a lezione". "Lo dice a lezione" is still flagged.
- **Why:** content agent (business, B4). The other two reports of that run (thousands dot, generator tests) were already handled by D-102 and D-078.
- **Cost:** a phrase glued to other letters is no longer found (no such case in the list).
- **Status:** implemented
- **Back-port:** A-06.

## D-106 · 2026-10-05 · `calculation: false` exempts counting items from W-CALCULATOR

- **Design ref:** operator "calculator", A-06, banco.item/1 (additive)
- **Design said:** in a subject that allows the calculator, every number, fraction or expression item must say so (W-CALCULATOR).
- **We do:** an optional boolean `calculation` on an item (and on testlet sub items). `false` means the item has no arithmetic (counting members of a class, reading a value off a table) and W-CALCULATOR is not raised. Absent or `true`: unchanged. Existing items are unchanged. The other two reports of that run were already handled: the `tests` of a generator item run against the first stored instance (D-078, `E-ROUNDTRIP` on `tests/must_accept|must_reject`), and an item error code that is not among its skill's graph errors is `W-ERROR-NOT-IN-GRAPH` (D-087); to use a new code such as `compound_as_mixture`, add it to the graph skill's `errors` (with implicates) first.
- **Why:** content agent (chemistry, B3).
- **Cost:** none.
- **Status:** implemented
- **Back-port:** A-06, banco.item/1.

## D-107 · 2026-10-05 · the number unit suffix is matched after NFKC

- **Design ref:** E-03, `Grading::Closed::Numbers`, D-078, D-103
- **Design said:** the item's unit is removed from a number answer only when the answer ends with exactly that string.
- **We do:** if the exact suffix is absent, the tail of the answer (at most unit length + 2 characters) is compared with the unit after NFKC, so `2,5 g/cm3` is read for the unit `g/cm³` and the reverse; the digits before the tail are never folded. Other spellings (`gr`) stay unparseable. A content agent report also asked for generator `tests` to be run and for a unit per instance: both were already done (D-078 and D-092; D-103 `display.unit`), so no change. For the content agent: a generator's `must_accept` must hold for every instance, normally leave it empty; for mass in some instances and volume in others, put `display.unit` on each instance. `banco.*/1` unchanged.
- **Why:** content agent (chemistry, B2 density): a student who types a plain 3 should not get an invalid.
- **Cost:** none.
- **Status:** implemented
- **Back-port:** A-06.

## D-108 · 2026-10-05 · three english reports answered by documentation

- **Design ref:** D-078, D-081, D-085, `Grading::Closed::Text`
- **Design said:** nothing explicit about which seed the item tests run on, and `it_accents` read as Italian only.
- **We do:** (1) item `tests` run on the first clean seed (seed 1 unless it throws or is rejected): said in the brief and docs/validation.md. (2) An instance may carry its own `accept` (D-081, normalized_text), merged with the item's list by `Grading::Spec.from_instance`: so `didn't go` / `did not go` per seed is already possible; the brief now says so for contractions. (3) `it_accents` stays the code of an accent slip for every subject except Spanish (renaming would break the error-code registry and the rules table); the registry description says so. No code change, `banco.*/1` unchanged. For the content agent: write `must_accept` from seed 1, put per-seed spellings in the instance `accept`, so a typed "write the negative" item is buildable.
- **Why:** content agent (english, B2 past forms).
- **Cost:** none.
- **Status:** implemented
- **Back-port:** A-06.

## D-109 · 2026-10-05 · under accent_policy flag a declared error typed without its accent still hits it

- **Design ref:** E-03, `Grading::Closed::Text`, D-078
- **Design said:** declared error values are matched exactly (after normalization, accents kept); only the key had the accent-slip path.
- **We do:** when `accent_policy` is `flag` and nothing matched yet (not the key, not a declared error exactly, not an accent slip of the key), the answer and each declared error value are compared with grave and acute folded; a hit is the same `typical_error` with that code (`abris` for the declared `abrís` is `es_imp_indicative`). Not applied when the bare form is a paradigm form (a word of its own) or under `strict`. Shared vectors added. The other report (tests of a generator item never run) was already handled: they run on the first clean seed (D-078, D-108), so no change; the content agent should write them from seed 1. `banco.*/1` unchanged.
- **Why:** content agent (spanish, B2 imperative): no need for a second unaccented value per error.
- **Cost:** none.
- **Status:** implemented
- **Back-port:** A-06.

## D-110 · 2026-10-05 · four english reports: two lint false positives, one CLI hint, two answered by documentation

- **Design ref:** A-06 readability lint, `Validation::InstanceChecks` leak scan, `banco work status --wait`, D-081, D-084, D-108
- **Design said:** `es.` is an abbreviation wherever it stands; a normalized_text key anywhere outside «…» in the stem is W-ANSWER-IN-STEM; a failed `--wait` always says "fix the files".
- **We do:** (1) the abbreviation list no longer matches when a hyphen or a letter comes before it: `-es.` ends the sentence, `es.` (esempio) still does not. (2) For normalized_text, a bracketed cue right after the gap (`___ (swim)`) is skipped by the stem leak check, like «…». (3) When `E-VERIFY-MISSING` is the only code, `next` says the files are clean and a verifier runs `banco work open ITEM --role verifier` (same exit 3, same code). (4) Not changed: an instance may already carry its own `accept` (D-081, D-108; an accepted text equal to an error value of that instance comes back correct and fails E-ROUNDTRIP error_value), and W-NEGATIVE-STEM already ignores «…» and `$…$` (D-084): a negative sentence to translate goes inside «…». `banco.*/1` unchanged.
- **Why:** content agent (english, B1 present and future forms).
- **Cost:** none.
- **Status:** implemented
- **Back-port:** A-06.

## D-111 · 2026-10-05 · `banco COMMAND --help` prints that command's contract entry

- **Design ref:** D-091 (`banco --help`), `contract/commands.json`
- **Design said:** `--help` anywhere prints the list of all commands with args and flags.
- **We do:** when the words before `--help` name a command (`banco session new --help`), the output is that command's entry: args, flags, error codes, and the exit codes. Otherwise the full list as before. Not changed: generator items already run `tests` on the stored instances since D-078 (`tests` run against the first stored instance, so on a shuffled choice generator a fixed id may not mean the same option: write tests that hold for every instance, or the seed-1 values and expect to adjust them). A content agent whose CLI says `unknown command: --help` has an old binary: rebuild or take the staging one. `banco.*/1` unchanged.
- **Why:** content agent (spanish, present tense).
- **Cost:** none.
- **Status:** implemented
- **Back-port:** none.

## D-112 · 2026-10-05 · testlet error codes reach the engine; target-language text is not linted as Italian

- **Design ref:** B-02, D-047, D-098, A-06
- **Design said:** (1) a testlet's unit result had a verdict only, so the catalogue codes of its sub items (en_wrong_referent) never reached the engine. (2) every `*_it` string is linted as Italian, including an English passage and model answer that can only sit under `passage_it` and `model_answer_it`.
- **We do:** (1) `Grading::Testlet` returns `typical_error` with the union of the sub items' `error_codes` when the unit is wrong; a mixture stays `undetermined` with no codes, all correct and all dont_know are unchanged. Evidence is W either way; the first code is the engine's error code, so descent follows its implicates when the graph lists that code on the testlet's skill. (2) `validation_rules.yml` v5: `target_language_subjects` (english, spanish) and `target_language_keys` (passage_it, model_answer_it); in those subjects `Readability.lint_document` skips those keys (no Gulpease, sentence length, ALL-CAPS). Other `_it` keys are still linted. (3) Already done, nothing to change: banned phrases on word boundaries (D-105), per-skill low-guess of a testlet (D-096), one skill per testlet and the brief (D-098), and `work status --wait` writes the status to stdout and the error object to stderr only (do not merge the streams).
- **Why:** content agent (english, reading and pronoun descent).
- **Cost:** a code not in the skill's graph errors counts as unclassified, as before. An English passage gets no readability check; the reviewer reads it.
- **Status:** implemented
- **Back-port:** B-02.

## D-113 · 2026-10-05 · binary answers written in groups of bits are read as one string

- **Design ref:** B-02, D-095
- **Design said:** the binary profile refused spaces between bits as `ambiguous_mixed_number`, a message about mixed numbers and fractions.
- **We do:** `Text.binary` drops whitespace between two bits before grading ("1110 1100" is 11101100); the width check and the leading-zero rule apply to the joined string, and `normalized` is the joined string. Other text stays `unparseable`. The reports on declared error values in the binary profile (D-095) and on the Italian thousands dot (`thousands_separator`, D-102/D-103) were already fixed on main; no change.
- **Why:** content agent (computer_science, base conversions).
- **Cost:** none; a space between bits was never a valid answer.
- **Status:** implemented
- **Back-port:** B-02.

## D-114 · 2026-10-05 · binary declared errors at the wrong width; spaced codes in normalized_text; CS acronyms

- **Design ref:** B-02, A-06
- **Design said:** the binary profile consulted declared errors (D-095) only when the value differed from the key; an answer with the right value but the wrong width was always `wrong_form`. `normalized_text` kept internal spaces, so "001 110" or "G H C C" was `wrong` against a key without spaces. The caps allowlist lacked computer science acronyms.
- **We do:** (1) in `Text.binary`, before `wrong_form`, a declared error value equal to the typed string (exact) is a `typical_error` with its code (padding_missing: "111" for the key 00000111). The zeros_padded_right case already worked (D-095). (2) in plain `normalized_text`, an answer that is not accepted but equals an accepted key once its whitespace is removed, when the key is a single token of bits or letters, is `invalid` with the new code `spaces_in_code` ("Scrivi la risposta di seguito, senza spazi."): not an attempt, the student retypes. Items may now use the binary profile (which also joins grouped bits, D-113). (3) ASCII, RGB, USB, SSD, HDD, LAN, WAN, BIOS, CSV join `caps_allowlist`; `validation_rules.yml` version 6. (4) Report that validation never runs a generator item's `tests`: not a defect, done since D-078 (tests run against the first clean seed's instance; keep `must_accept` empty or instance-independent).
- **Why:** content agent (computer_science, coding, bits and the machine).
- **Cost:** a plain-text key of one token typed with spaces is never graded wrong, only asked again. `banco.*/1` unchanged.
- **Status:** implemented
- **Back-port:** B-02, A-06.

## D-115 · 2026-10-05 · `work open` warns inside a git work tree; cloze pages that repeat a form use `reuse_right`

- **Design ref:** D-092, D-111
- **Design said:** nothing about where `work open` writes; a key may repeat a right id only for a classification.
- **We do:** (1) `banco work open` adds a `warning` to its JSON when the folder it wrote is inside a git work tree (`--dir` has existed since M5; the default stays `./ITEM`). (2) Reported "a matching key cannot repeat a form" is answered by D-092: `display.reuse_right: true` allows a key that repeats a right id (4 or more rows and 3 or more forms, or 6 and 2; fewer forms than rows); a cloze page is that shape, no new flag. (3) `banco --help` already works since D-111; staging had it. `banco.*/1` unchanged.
- **Why:** content agent (spanish, B3).
- **Cost:** none.
- **Status:** implemented
- **Back-port:** none.

## D-116 · 2026-10-05 · binary profile: declared error values that are not bit strings

- **Design ref:** B-02, D-095, D-114
- **Design said:** `Text.binary` rejected any answer with a digit other than 0 and 1 as `invalid` (unparseable), so a declared error such as 1121 (digit 2 written) gave the student a free retry.
- **We do:** before the unparseable verdict, an all-digit answer (whitespace removed) is compared with the declared error values; a hit is a `typical_error` with its code. Declared 0/1 values were already classified since D-095 and D-114. Undeclared non-bit answers stay `invalid`.
- **Why:** content agent (computer_science, items:B2).
- **Cost:** none; `banco.*/1` unchanged.
- **Status:** implemented
- **Back-port:** B-02.

## D-117 · 2026-10-05 · W-SCOPE-MARKER reads the stars inside the cited fragment

- **Design ref:** D-075, brief rule 3
- **Design said:** `W-SCOPE-MARKER` compared a skill's scope with the marker of the cited line (its own or inherited from the block header). A line that holds several star fragments without starting with a star has no marker, so a studied skill could cite a `☆` fragment of it without a warning.
- **We do:** the marker of a cited prima ref is the star inside its `fragment` first (`★`, `☆`, both = in progress), then the line's own, then the inherited one. A studied skill citing a `☆` fragment, or an in_progress / integration_studied skill citing only unstarred or other-starred fragments, gets the same warning. No new code, `banco.*/1` unchanged, still a warning.
- **Why:** content agent (geography, step graph). Their second report (a matching with 3 categories) needs no change: `display.reuse_right` (D-092) is exactly a classification with at least 3 right entries and fewer than rows; the schema minItems 5 is not applied to it (`InstanceChecks` decides the sizes).
- **Cost:** none.
- **Status:** implemented

## D-118 · 2026-10-05 · empty table cells

- **Design ref:** A-01 (`banco.item/1`, `$defs/table`)
- **Design said:** header and row cells have `minLength` 1, so a spreadsheet grid needed a single space for each empty cell, a convention nobody had written down.
- **We do:** header and row cells may be `""` (`minLength` 0; `maxLength` 80, the row and header sizes are unchanged). The renderer already draws `""` as an empty `td`/`th`; the leak scan reads each cell as text, so an empty cell never matches and the others are scanned as before. Use `""`, not `" "`. A frozen format relaxed, so every existing item stays valid. The second report (an arrow in `description_it` fails `E-READ`) is not a defect: since D-095 the pattern starts at U+21A0 and the arrows U+2190-U+219F, including the assignment arrow, pass in every `_it` field, error descriptions included (test added). A content agent that saw it was on a staging older than D-095, or wrote a different arrow (for example U+21D2 or U+27F5), which are still refused: use `$\leftarrow$`.
- **Why:** content agent (computer_science, items:B4).
- **Cost:** a table with an entirely empty row or header is now schema-valid; the reviewer sees it.
- **Status:** implemented
- **Back-port:** A-01.

## D-119 · 2026-10-05 · the verifier sees the whole pool

- **Design ref:** A-04, A-06 (`work open --role verifier`)
- **Design said:** the verifier gets item.json, the tests and 8 instances with their expected answers.
- **We do:** the verifier gets every stored instance (the 24 clean seeds validation runs `verify.mjs` on), still with answers and never `generator.mjs`. `instances.json` grows from 8 to 24 rows. `E-VERIFY-REJECTS` already lists every rejected seed, the reasons grouped per wording and the first rejected instance (display, answer), so a seed outside the old 8 is no longer a blind spot.
- **Why:** content agent (business, verify:B4): a categorical verify (matching, choice) must classify texts it had never seen and needed several submit rounds.
- **Cost:** a larger answer (about three times); the verifier sees nothing it could not derive from the 8 plus the validation findings.
- **Status:** implemented
- **Back-port:** A-04.

## D-120 · 2026-10-05 · `banco items list`

- **Design ref:** A-04, A-07 (`banco status`, `review open`)
- **Design said:** `banco status` counts the items of a subject; the revision id to review is learned elsewhere.
- **We do:** `banco items list [--subject KEY] [--current]` (GET `/api/v1/items`, read only) lists every revision of the items with `{item, subject, kind, revision_id, seq, status, current, reviews, blind_solves}`; `current` is true for the latest revision of its item, `status` is its latest validation (`validating` when none). `--current` keeps only the latest revision of each item. A new route and command; no frozen format changes. The same report raised two more points that are not defects: (1) algebraic fractions in lowest terms are asked with `form: ["reduced"]` (D-080; the brief says so), which gives `wrong_form` / `common_factor_not_cancelled` for the unchanged fraction; (2) per-instance `accept` on a `normalized_text` instance exists since D-081 (`"accept": ["x = 0"]` on the instance whose key is `0`).
- **Why:** content agent (math, review:1): finding the 39 current revisions took 170 `review open` probes.
- **Cost:** one more read-only route.
- **Status:** implemented
- **Back-port:** A-04.

## D-121 · 2026-10-05 · closed items beside the short answer; the teacher's traces reach the close

- **Design ref:** B-02, B-07, C-04
- **Design said:** `BlueprintChecks` counts every pinned instance of a skill for the redo pool; the teacher's traces run the named scripts as they are.
- **We do:** (1) New warning `W-SHORT-SKILL-CLOSED` (registry version 8): closed items pinned on the skill of a pinned short answer are never served (`Engine#servable?`), so they are named in the warning and left out of the E-POOL-REDO count (a skill with a short answer needs `redo_reserve: false`). `ItemInfo` gains an optional `kind`. Authors give the short answer its own skill. (2) `Teacher::TestReview#traces` runs with `resolve_pending`, so a discursive subject's traces end at the close, not `waiting_on pending_answers`.
- **Also, already done before this report:** the testlet charged to several skills (D-098), the testlet's per-skill low-guess and choice flags (D-096, `testlet_flags`), the bare-blueprint dry run (D-099), `intro_note_it`, `not_measured_it` and the calculator line (D-101), `work open` inside a git tree (D-115). Staging that ran older code showed them.
- **Why:** content agent (law_economics, step blueprint).
- **Cost:** none.
- **Status:** implemented
- **Back-port:** B-02.

## D-122 · 2026-10-05 · the CLI queues a busy dry run

- **Design ref:** A-06 (dry run), D-097
- **Design said:** a dry run waits up to 25 s for Chrome, then answers 409 `E-CHROME-BUSY` with `retry in 30 s`; the agent retries by hand.
- **We do:** the CLI repeats a `--dry-run` that gets `E-CHROME-BUSY`: `BANCO_BUSY_RETRIES` times (default 6), `BANCO_BUSY_WAIT_MS` apart (default 10000), then reports the error as before. Nothing changes on the server or in the contract; non-dry submits and other errors are never repeated.
- **Why:** content agent (spanish, verify:B3): parallel verifiers got E-CHROME-BUSY and wrote their own retry loops.
- **Cost:** a dry run can take up to about 25 s x 7 plus 60 s under heavy contention (the HTTP timeout is per attempt, 300 s).
- **Status:** implemented
- **Back-port:** A-06.

## D-123 · 2026-10-05 · `work status` says when an error is a retry in progress

- **Design ref:** A-06 (errors are never verdicts), D-122
- **Design said:** an `error` validation row is one failed attempt; the job retries (3 attempts), and `settled` is true only after the last one.
- **We do:** the status answer gains `retrying` (true when the status is `error` and not settled). Nothing else changes: the field is additive, the frozen format stays valid. Content agents read a Chrome timeout (`ChromeRunner::Timeout`) as `error` between attempts and resubmitted; use `banco work status REV --wait` and resubmit only when it settles in `error`.
- **Why:** content agent (english, verify:B1): revision ended in `error` with a Chrome timeout, a resubmission passed. The retry already existed; the answer did not say so.
- **Cost:** none.
- **Status:** implemented
- **Back-port:** A-06.

## D-124 · 2026-10-05 · `E-VERIFY-REJECTS` shows several rejected instances

- **Design ref:** A-06 (verify), D-097
- **Design said:** verify runs on every clean seed of the 200; `E-VERIFY-REJECTS` lists all rejected seeds, the reasons and the first rejected instance.
- **We do:** the detail gains `rejected_samples`: up to 8 rejected instances, each `{id, reason, display, answer, in_stored_pool}` (clipped like `first_rejected`). `in_stored_pool` is false for a seed that `work open --role verifier` did not list. Additive; no frozen format changes. `work open --role verifier` already returns every stored instance (24, tested in `work_api_test`); a verifier that saw 8 was reading a truncated `instances.json`. Verify checks the 200-seed clean pool, so a vocabulary rule written from the 24 can still reject an unseen seed: write rules by pattern, not by word list, and read `rejected_samples` instead of resubmitting one seed at a time.
- **Also, not defects:** `E-CHROME-BUSY` on a dry run is already queued by the CLI (D-122). `W-ANSWER-IN-STEM` on a typed item whose bracketed base word equals the key is a warning, not an error; it does not block, and the author decides.
- **Why:** content agent (spanish, verify:B4): about 10 dry runs, each showing one new word.
- **Cost:** a larger finding detail.
- **Status:** implemented
- **Back-port:** A-06.

## D-125 · 2026-10-05 · the section of a cited line; unpinned items are a reserve

- **Design ref:** C-01, C-04, D-075
- **Design said:** a graph ref is `{source, line, fragment, role}` and the teacher's graph page shows the line text. The teacher's home counts undecided blocker and major findings on the latest revision of every item.
- **We do:** (1) `Syllabus::Sections`: a line's section is the nearest preceding `## ` heading of its programme. `banco syllabus lines` rows gain `section`. The teacher's graph page shows `sezione <heading>` beside each cited line and marks "Riga di un'altra materia." when it is not the section most of the graph's citations of that source sit in. (2) New warning `W-REF-OTHER-SUBJECT` (registry version 9): the same test at submit, with the line and the section in the detail; quiet on a tie or when no line has a section. A needed_by ref to another subject's line stays valid (`banco.skill_graph/1` is unchanged, no `note_it` on refs): say it in `scope_reason_it`, as the content agent already did. (3) Reserve: an item whose item id is not pinned by the subject's latest blueprint is a reserve. It is derived (`Item.reserve`), nothing is stored and no withdraw command exists; `banco status` items gain `reserve` (count) and the teacher's home no longer counts its findings as waiting. Pin it in a later blueprint and it counts again. A withdrawal row was not added: the ledger is append-only and the blueprint already is the statement of what is in the test.
- **Not a defect:** `W-NEGATIVE-STEM` already skips text inside `«...»` and `$...$` (D-084, 2026-10-05 01:00); the stored finding on revision 464 dates from 2026-10-04 18:32, before that fix. A new submission of the item runs the current rule. Curly quotes “...” are now skipped too, with a test of the reported stem.
- **Why:** content agent (italian, step fix).
- **Cost:** one more key in the status answer (additive); a few queries on the graph page.
- **Status:** implemented
- **Back-port:** C-01, C-04.

## D-126 · 2026-10-05 · the short answer is indicative by definition

- **Design ref:** B-06, blueprint brief rule 3
- **Design said:** a discursive subject has exactly one short answer, "marked as indicative".
- **We do:** nothing in the formats. No `indicative` field is added to `banco.item/1` or `banco.blueprint/1`: a short answer is already indicative in every way that matters (its state is `pending(grade_unconfirmed)` until the teacher confirms, it is one piece of evidence, the proposal of the agent never counts by itself, and the teacher's pages show it as "Risposta breve: vale la rubrica"). The brief now says so instead of asking for a mark.
- **Not a defect:** a flag would be redundant (every `short_answer` would carry it) and the engine would have nothing to branch on. The content agent should not cite a source such as "Prova indicativa" for it; if one was added to the skill graph only for this, remove it in the next graph revision.
- **Why:** content agent (geography, step items:B5).
- **Cost:** none; `banco.*/1` unchanged.
- **Status:** implemented
- **Back-port:** B-06 (wording of rule 3).

## D-127 · 2026-10-05 · the whole arrows block is allowed in `*_it` text

- **Design ref:** A-06, item brief rule 6 (E-READ `emoji`); D-095
- **Design said:** D-095 allowed U+2190-U+219F; the rest of the arrows block (U+21A0-U+21FF) was rejected as pictographic.
- **We do:** the emoji pattern now rejects only U+21A9 and U+21AA (the return arrows that have an emoji presentation); every other arrow (food chains, `\u21D2`, `\u21D4`, the chemical equilibrium arrow `\u21CC`, `\u21A6`) is plain text. Graph and item texts use the same `Readability.lint_document`, so a graph description can be copied into an item unchanged. `banco.*/1` unchanged.
- **Also checked, not a defect:** the thousands-separator report (`2.000`, `2 000`) is already `invalid thousands_separator` since D-102/D-103 with the message "Scrivi il numero senza punti né spazi tra le cifre"; staging at 42dc627 returns it.
- **Why:** content agent (biology, step items:bio-b1-ecology-species).
- **Cost:** none.
- **Status:** implemented

## D-128 · 2026-10-05 · W-TESTLET-LEAK: a sub-item key in the passage or in another sub-item

- **Design ref:** A-06, D-094
- **Design said:** each sub-item's instances are checked alone; only a long choice key stated in the passage is an error (D-094).
- **We do:** after the composite instances are built, `ItemRunner#testlet_leaks` flags (warning `W-TESTLET-LEAK`) a sub-item key (choice option text, or `Answers.key_texts` for written answers, 20+ plain characters) that appears in the passage (written keys only: choice keys stay `E-SOLUTION-IN-DISPLAY`) or in any string of another sub-item's display of the same composite instance. The field points at the place that shows the key.
- **Also checked, not a defect:** `banco work submit --help` already prints the command's contract entry (flags, errors) since D-111; the content agent had an older CLI binary. Rebuild or use the staging `bin/banco`.
- **Why:** content agent (biology, step items:bio-b6-testlet-short-answer).
- **Cost:** one pass per composite instance; a warning, no format change (`banco.*/1` unchanged).
- **Status:** implemented
- **Back-port:** A-06.

## D-129 · 2026-10-06 · guest skills from a draft graph; `items list` carries what a blueprint pins

- **Design ref:** B-07, D-120, D-099
- **Design said:** a guest starting skill must be in an approved graph of its subject (E-SKILL-UNKNOWN otherwise), even in a draft or a dry run.
- **We do:** (1) `BlueprintChecks` accepts a guest skill found in the owner's latest graph when that graph is not approved yet, with the warning `W-GUEST-UNAPPROVED` (new `Validation::Context#draft_skill`); a skill in no graph is still `E-SKILL-UNKNOWN`. `Approval::BlueprintGate` refuses the approval ("the guest skill X is not in an approved graph of its subject") until the owner's graph is approved, so the requirement is enforced where it counts. (2) `banco items list` rows of current revisions gain `skill`, `component`, `expected_seconds`, `instances`, `low_guess_instances` (additive; the content agent did not know the command existed and used `work open` per item). (3) Not a defect: `banco diagnosis simulate --blueprint FILE` of a bare blueprint already loads the pinned graph and items since D-099 (staging at c337f42 gives the real trace; a flat run only happens when the graph revision is not stored, and then carries a warning). `banco.*/1` unchanged.
- **Why:** content agent (business, step blueprint).
- **Cost:** a blueprint with a draft guest can be submitted but not approved; the teacher's checklist says why.
- **Status:** implemented

## D-130 · 2026-10-06 · a pending testlet answer holds its skill

- **Design ref:** B-02, D-047, D-096, D-099
- **Design said:** a pending answer makes the engine serve another instance of the skill, up to the serve cap.
- **We do:** while a testlet answer of a skill is pending or ungraded (a mostly right testlet is undetermined, D-047), `Candidates.for` offers no further testlet of that skill and the engine does not stall the skill: it waits (`waiting_on: pending_answers`) for the teacher's resolve_attempt, and other skills go on. D-047's question (does a mostly right testlet count as correct) stays open for the operator.
- **Also (content agent, english, step blueprint):** the bare-blueprint dry run ignoring the graph and the pool and the second testlet from the same passage were already fixed by D-099. A testlet's low-guess and choice flags come from its sub items' components (D-096), not from a default: a testlet with an ordering sub item is low-guess and not choice, so `two_of_two` (not `_choice`) is correct for it; a skill measured only by testlets with a non-choice sub item cannot be choice-only. Content: mark every sub item `choice` if the testlet should count as choice evidence.
- **Why:** 15 minutes of reading passages for one undetermined answer.
- **Cost:** a run waits on the teacher while a testlet answer is pending and nothing else is servable.
- **Status:** implemented
- **Back-port:** B-02.

## D-131 · 2026-10-06 · a testlet that does not fit is deferred, not replaced by a repeat

- **Design ref:** B-02, B-05, D-099
- **Design said:** `Candidates.for(:second)` takes another item, else any unseen instance.
- **We do:** when the only other item of a skill is a testlet whose expected seconds exceed the time left, `Candidates.for(:second, max_seconds:)` returns nothing, so `Engine.choose` reports `:no_fit`, the sitting ends (`time_budget`) and the passage opens the next sitting. A repeat of the item already used is no longer served in its place. A pool with no testlet keeps the old fallback.
- **Also (content agent, spanish, step blueprint):** a testlet's low-guess and choice flags come from its sub items per skill (D-096), and the testlet is attributed to its first skill only (D-098); `Plan.from_bundle` pools built by hand must give `low_guess`/`choice` per testlet themselves. The bare-blueprint dry run loads the graph and the pinned items (D-099); `intro_note_it`, `not_measured_it` and the calculator line are shown (D-101). Staging at 61250b7 already ran all of these.
- **Why:** reading passage never served for a slow student (4 of 20 runs).
- **Cost:** one more sitting for a slow student whose only other item is a long testlet.
- **Status:** implemented

## D-132 · 2026-10-06 · reviewers: list command exists; own scratch directory

- **Design ref:** M6, D-129
- **Design said:** the review brief tells the reviewer how to find revision ids.
- **We do:** no code change. (1) "No command lists the revision ids of a subject" is not a defect: `banco items list --subject KEY --current` (D-129) returns item, `revision_id`, `seq`, `status`, `current`, review and blind-solve counts; the reviewer used an older CLI binary (use the staging `bin/banco`). (2) The scratch directory cleaned under the reviewer was a shared name used by parallel sessions, a content-orchestration matter; `briefs/review.md` now tells reviewers to use a directory named after subject and round. `banco.*/1` unchanged.
- **Why:** content agent (business, step review:1).
- **Cost:** none.
- **Status:** implemented

## D-133 · 2026-10-06 · `review open` lists every stored instance of a generator item

- **Design ref:** A-05, M6 (`docs/validation.md`)
- **Design said:** the reviewer sees 8 instances of a generator item.
- **We do:** the review (`review open`, and the quote check of `review submit`) uses every stored instance (the pool, e.g. 24); numbering is by id, so instances 1..8 are unchanged. The blind solver (`solve open`) still gets 8. No flag, no format change; `banco.*/1` unchanged.
- **Why:** content agent (spanish, step review:1): a reviewer could not read 16 of 24 expected answers and distractors and had to run the generator locally.
- **Cost:** a larger review payload; reviewers may quote any stored instance.
- **Status:** implemented

## D-134 · 2026-10-06 · `items list --subject` accepts keys with an underscore

- **Design ref:** M6, D-129
- **Design said:** `banco items list --subject KEY` lists the revisions of a subject.
- **We do:** the CLI checked the key with the source-name pattern (no underscore), so `computer_science` and `law_economics` were refused with E-USAGE (the "unknown command" the content agent saw was an older binary; the underscore refusal is what remains). It now uses the subject-key pattern of the other commands. `banco.*/1` and the API unchanged.
- **Why:** content agent (computer_science, step review:1).
- **Cost:** none.
- **Status:** implemented

## D-135 · 2026-10-06 · `round_to` on a number error; item implicates into another subject's draft graph; ready marker on deferred edges

- **Design ref:** A-06, D-091, D-129
- **Design said:** a number error matches only the exact declared value; an item implicate must name a skill of the item's graph or of an approved graph; the teacher's graph screen lists deferred edges.
- **We do:** (1) `error_catalogue` instance errors (`errors[]` of an instance, `error_value` in `banco.item/1`) gain the optional `round_to` (integer 0..6, number component only): the error matches any answer that rounds half up, at that many decimals, to the declared value. It never applies to the key (the key is graded first); a `round_to` whose window contains the key is `E-GEN-SCHEMA` (`round_to_key`), on another component `round_to_component`. Backward compatible: optional member. (2) An item implicate into a skill that is only in another subject's latest, unapproved graph is the warning `W-IMPLICATE-PENDING` (registry version 10) instead of `E-SKILL-UNKNOWN`; the engine reads implicates from the graph and ignores the item's list, so the item cannot activate anything. (3) The teacher's graph screen marks a deferred edge whose target graph is approved now ("serve una nuova revisione"). Not changed, not defects: the graph keeps refusing a plain edge into an unapproved graph (`E-GRAPH-EDGE-UNAPPROVED`, rule 12); the way to declare it is `deferred_prerequisites` / `deferred_implicates` (D-091), and `W-ERROR-NOT-IN-GRAPH` already reports item error codes missing from the graph (and implicates that differ).
- **Why:** content agent (chemistry, step fix): calculator-rounded typical errors; cross-subject edges before the other graph is approved.
- **Cost:** a rounded error still needs the student to type at least the declared number of decimals; fewer decimals is a plain wrong.
- **Status:** implemented
- **Back-port:** A-06.

## D-136 · 2026-10-06 · a pinned item revision that a newer passed revision replaced is `W-STALE-PIN`

- **Design ref:** B-07, A-06, C-04
- **Design said:** a blueprint pins item revisions that passed validation.
- **We do:** (1) blueprint submit and dry run warn `W-STALE-PIN` (registry version 11) for a pinned revision that passed but is not the newest passed revision of its item. (2) `banco status` carries `stale_pins` (`[{pinned, latest}]`) in the subject's `blueprint` row; additive member. (3) `Approval::BlueprintGate` lists each stale pin as a reason, so the teacher cannot approve a test that pins a replaced revision. Not a defect: the engine serves exactly the pinned ids (rule 5, immutable revisions); the content agent re-pins and resubmits. A warning, not an error, so a draft can still be simulated.
- **Also:** the report that `review open` shows 8 of 24 instances is answered by D-133 (all stored instances, no flag); the content agent ran a binary or staging from before D-133.
- **Why:** content agent (math, step review:2).
- **Cost:** one extra query per pinned item at submit.
- **Status:** implemented

## D-137 · 2026-10-06 · `skill-graph coverage` lists the error codes of passed items that the graph lacks

- **Design ref:** A-06, C-01
- **Design said:** `W-ERROR-NOT-IN-GRAPH` (D-087) warns at item validation when an item's error code is not an error of its skill in the graph.
- **We do:** `banco skill-graph coverage --subject KEY` gains the additive member `item_errors_not_in_graph`: `[{item, item_revision_id, skill, code}]` for the latest passed revision of each item (testlet sub-items included) against the latest graph. Not a defect in the warning, which already exists: it only fires when a graph exists at the item's validation (or revalidation), so items validated before the graph, or against an older graph revision, passed without it. Warnings never block. The content agent adds the codes to the graph (with their implicates) and resubmits it, or revises the items to graph codes, then re-reads the coverage.
- **Why:** content agent (law_economics, step review:2): 27 codes missing, noticed by hand.
- **Cost:** one pass over the subject's latest revisions per coverage call.
- **Status:** implemented

## D-138 · 2026-10-06 · the blueprint's item order decides which item is served first; a star block survives short bullets

- **Design ref:** B-02, A-06
- **Design said:** the engine picks the next item among the unseen eligible instances in the plan's seeded order; a marked header opens a block that ends at the next header-looking line (short, no closing punctuation).
- **We do:** (1) `Plan::Entry` carries `items` (the blueprint's `entries[].items`); `Candidates.for` returns the eligible instances ordered by the position of their item in that list (unlisted items last, seeded order breaking ties), for every need. Listing the first item first now serves it first. No schema change. (2) `Syllabus::BlockMarker`: inside an open star block only the next marked line, a blank, a transcriber line or a line ending with ":" ends it; a short bullet no longer does, so it inherits the star. A short header-looking line outside a block still opens nothing. Not done: a per-item "coverage unverified" flag. The order answers the concern (a failed later item next to a passed first one is read by the teacher as to verify); a flag would be a new decision input.
- **Why:** content agent (spanish, step fix): 656 served before 403; W-SCOPE-MARKER on lines 177-181.
- **Cost:** a block that really ends at a short header without a colon now runs on until a blank or a marked line; the heuristic can over-report a star. The agent re-imports with the source's blank lines or cites the header line.
- **Status:** implemented

## D-139 · 2026-10-06 · W-SCOPE-MARKER reads a star just before the cited fragment; `banco work open` defaults outside the repo

- **Design ref:** A-06, brief rule 3
- **Design said:** the programme's markers decide the scope; a star inside the cited fragment decides first (D-117); `work open` writes `./ITEM` unless `--dir` (D-091).
- **We do:** (1) A fragment cited without its star takes the star that stands before it in the same sentence of the line (`... ☆ Un mondo inquinato.` cited as `Un mondo inquinato`), then the line marker, then the block marker. (2) `banco work open ITEM` without `--dir` writes `$TMPDIR/banco-work/ITEM` (os.TempDir) instead of the current directory; the in-git-tree warning stays for an explicit `--dir`. (3) Reported "PlanLoader treats a testlet as a low-guess number item" is not reproducible on main: since D-096 the loader gives a testlet per-skill flags from its sub items (choice sub items: not low-guess, choice) and since D-099/D-131 one passage is served once per run; a loader test now pins it. The report came from a staging build or blueprint older than that. `banco.*/1` unchanged.
- **Why:** content agent (geography, step fix).
- **Cost:** a sentence boundary is `. ; ! ?` followed by a space; a star after an abbreviation's dot is read as in the next sentence.
- **Status:** implemented

## D-140 · 2026-10-06 · `banco work open --role verifier` gets its own default folder and refuses the other role's folder

- **Design ref:** A-06, D-091, D-139
- **Design said:** `work open` writes `$TMPDIR/banco-work/ITEM` for both roles.
- **We do:** a verifier open without `--dir` writes `$TMPDIR/banco-work/ITEM.verifier`; opening a folder whose `.banco/work.json` records the other role is refused with `E-USAGE`. Formats unchanged.
- **Why:** content agent (geography, step verify:refix): the verifier folder shared the author's folder, so a stale verify.mjs sat next to generator.mjs and the verifier could see the generator.
- **Cost:** a verifier that relied on the shared default folder must read the `dir` field of the answer.
- **Status:** implemented

## D-141 · 2026-10-06 · a carried-forward verify.mjs that rejects is `E-VERIFY-STALE`; `banco status` counts `awaiting_verifier`

- **Design ref:** A-06, D-091, A-04
- **Design said:** files missing from a submission are carried forward from the base; an author may not change verify.mjs; a rejection is `E-VERIFY-REJECTS` and the revision `failed`.
- **We do:** (1) when the revision's verify.mjs is identical to its base's while another file changed, the rejection of clean seeds is `E-VERIFY-STALE` (registry version 12; same findings and detail as `E-VERIFY-REJECTS`, also in `work submit --dry-run`); a verify.mjs that does not load stays `E-VERIFY-REJECTS`. `work status --wait` says the verifier refreshes it. (2) `banco status` items gain the additive `awaiting_verifier`: the latest validation failed with only `E-VERIFY-MISSING` and/or `E-VERIFY-STALE`; those items are no longer in `failed`. The stored status stays `failed` (never approved), the frozen formats are unchanged.
- **Also, reported and not changed (already answered):** (a) closed items pinned on the short answer's skill are never served; that is `W-SHORT-SKILL-CLOSED` since D-121 (also leaving them out of the redo count: the dry run of the reported file gives `E-POOL-REDO` plus the warning on staging at this commit). The short answer needs a skill of its own; the blueprint brief says so. The engine is not changed. (b) `diagnosis simulate --blueprint` with a bare blueprint loads the stored graph revision and the passed pinned items since D-099; it is flat only when the graph revision is not stored, and then the answer carries `warnings[E-SIMULATE-INPUT]` (read `warnings`, or use `--subject` after the blueprint is stored). The report came from a build before D-099/D-121 or from a blueprint naming an unstored graph revision.
- **Why:** content agent (biology, step fix).
- **Cost:** a verify.mjs that is wrong, not stale, also reads as stale after an author change; the verifier reads the rejections either way.
- **Status:** implemented

## D-142 · 2026-10-06 · a star block ends at a short heading after a finished sentence; W-SCOPE-MARKER counts unmarked lines; descent item order is kept

- **Design ref:** B-02, A-06, D-138
- **Design said:** inside a star block a short line is a bullet (D-138); W-SCOPE-MARKER compares the scope with the markers of the cited lines; the blueprint's item order decides the served order (D-138, entries only).
- **We do:** (1) `Syllabus::BlockMarker`: a short unpunctuated line right after a block line that ends with `. ; ! ?` closes the block (it is a heading: "Economia" after the Constitution text). Bullets after the header or after unpunctuated bullets still inherit. (2) W-SCOPE-MARKER: a cited line without a marker counts as "no marker" (scope studied), so a skill spanning unmarked and star lines expects `studied` or `integration_studied`; only lines the source lacks are skipped; a skill citing only unmarked lines stays quiet as before. (3) `Plan#descent_items` (skill to the blueprint's `descent[].items`) and `Plan#item_order`; `Candidates.for` ranks by the entry's items then the descent items. No schema change; `banco.*/1` unchanged.
- **Why:** content agent (business, step fix): false W-SCOPE-MARKER on lines 136-137 and on a skill spanning lines 147 and 149; 314 served before 313.
- **Cost:** a bullet list whose item follows a sentence-ending bullet and is itself a short unpunctuated line now leaves the block; the agent cites the header line or the source gets a blank line. Existing stored syllabus lines are derived on read, so no re-import is needed.
- **Status:** implemented

## D-143 · 2026-10-06 · W-REF-OTHER-SUBJECT is quiet when the skill's scope_reason_it names the line

- **Design ref:** D-125
- **Design said:** a ref under another programme section than most citations is warned; the author labels it in `scope_reason_it`.
- **We do:** the check reads the skill's `scope_reason_it`; when it contains the ref's line number as a whole number, no warning. The message now says to name the line. Schema unchanged.
- **Why:** content agent (law_economics, step fix): the warning kept firing after the label was written, because the check never read it. Defect.
- **Cost:** a reason that merely mentions the number clears it; the teacher still reads the reason on the graph page. A range written as "687-701" names only its ends.
- **Status:** implemented

## D-144 · 2026-10-06 · W-TESTLET-MULTI-SKILL: a pinned testlet with sub items on several skills is warned and cannot be approved

- **Design ref:** D-098, D-136, A-06
- **Design said:** E-TESTLET-SKILLS (D-098) fails a testlet with sub items on several skills when it is validated; revisions validated before stay `passed` (immutable).
- **We do:** (1) `Validation::ItemInfo` carries `testlet_skills`; the blueprint checks add the warning `W-TESTLET-MULTI-SKILL` (registry version 13) on a pinned testlet whose stored sub items span several skills, in entries and descent, also in `blueprint submit --dry-run`. (2) `Approval::BlueprintGate` refuses the approval with a reason naming the revision and its skills (`multi_skill_testlets`). (3) `banco status` blueprint row gains the additive `multi_skill_testlets` next to `stale_pins`. The stored validation is not rewritten (the ledger is append-only); `banco.*/1` unchanged.
- **Why:** content agent (geography, step fix): old passed testlets (biology 706, history 681, law_economics 634, italian 464/465, spanish 665) could be pinned and approved although every answer counts for the first skill only. Defect (a hole in D-098).
- **Cost:** a warning, not an error, so a draft blueprint and the dry run still work; only the teacher's approval is blocked. The author resubmits the testlet on one skill (a new revision) and pins it.
- **Status:** implemented

## D-145 · 2026-10-06 · W-ERROR-UNREACHABLE: a matching error value that repeats a right-hand id is warned

- **Design ref:** D-081, D-092, A-06
- **Design said:** the matching widget lets each right entry be picked once (a classification with `reuse_right` lets rows share one); the validator did not check that error values are submittable.
- **We do:** `Validation::InstanceChecks` adds the warning `W-ERROR-UNREACHABLE` (registry version 14) for an error value of a matching item whose right ids are not all distinct, unless the instance is a classification (`display.reuse_right`). One finding per such value, at `instances/N/errors/I/value`. Stored validations are not rewritten; `banco.*/1` unchanged.
- **Why:** content agent (italian, step review): revisions 475 and 59 carry non-injective error values and are `passed`; the code can never fire. Missing check (a hole in A-06).
- **Cost:** a warning only; the item still passes. The author rewrites the value as a one-to-one mapping and resubmits a revision.
- **Status:** implemented

## D-146 · 2026-10-06 · diagnosis simulate warns W-STALE-PIN for each stale pin it serves

- **Design ref:** D-136, A-06
- **Design said:** a pinned revision replaced by a newer passed one is W-STALE-PIN in blueprint submit and the approval gate; `banco status` lists `stale_pins`.
- **We do:** `POST /api/v1/diagnosis/simulate` adds a `W-STALE-PIN` entry to `warnings` for each stale pin, for `--subject` and for a bare blueprint with stored items. Same shape as the other simulate warnings; the run itself is unchanged (it still serves the pinned revision). `banco.*/1` unchanged.
- **Why:** content agent (chemistry, step review): simulate served pin 330 with `warnings: []` though 730 replaced it. Missing feature.
- **Cost:** a warning only. The agent pins the newest revision in a new blueprint revision and simulates again.
- **Status:** implemented

## D-147 · 2026-10-06 · `banco status` counts passed items validated under older rules

- **Design ref:** A-06, D-141
- **Design said:** a passed revision stays passed; the validation row stores the rules version it ran under, but nothing compares it with the current one.
- **We do:** `banco status` items gain the additive `older_rules`: items whose latest revision passed under a `rules_version` other than the current one. The stored status is not changed and nothing is re-run. Also reported and not changed: the order of descent items is already kept since D-142 (the english all-wrong simulation on this commit serves 737 before 741 for object-pronouns-possessive); the report came from a build before D-142.
- **Why:** content agent (english, step fix2): revisions 268 and 269 passed under old rules but fail E-SOLUTION-IN-DISPLAY on a dry run. Missing feature.
- **Cost:** a count, not a list; every rules bump makes it non-zero for old items. The author dry-runs (`banco work submit DIR --dry-run`) the pinned items of older rules and resubmits those that fail.
- **Status:** implemented

## D-148 · 2026-10-06 · the programme's star markers are not emoji for the readability rule

- **Design ref:** D-095, D-127, D-085
- **Design said:** E-READ `emoji` flags the pictograph blocks; in a skill's `*_it` text it is the warning W-GRAPH-READABILITY.
- **We do:** U+2605 (star) and U+2606 (empty star) are removed from the emoji class. Every other pictograph is flagged as before. Schema unchanged.
- **Why:** content agent (spanish, step review): the brief tells the agent to cite the programme's markers in `scope_reason_it`, and quoting one raised W-GRAPH-READABILITY (emoji). Defect (the rule contradicted the brief). The other reported issue, W-SCOPE-MARKER ignoring unmarked lines, was already fixed by D-142 and does not reproduce on the current server (the stored spanish graph, revision 38, gives no warning): the agent had run an older build.
- **Cost:** a star in an item text for the student is no longer flagged; the mark is a plain text glyph, not an emoji presentation.
- **Status:** implemented

## D-149 · 2026-10-06 · W-RULES-OUTDATED names the pinned revisions that passed under older rules

- **Design ref:** A-06, D-136, D-147
- **Design said:** D-147 counts, per subject, the items whose latest revision passed under another rules version; it does not say which, and the blueprint checks say nothing.
- **We do:** (1) blueprint submit and dry run warn `W-RULES-OUTDATED` (registry version 15) for each pinned revision whose latest validation passed under a `rules_version` other than the current one, naming that version. (2) `banco status` blueprint row gains the additive `older_rules_pins` (`[{revision, rules_version}]`). A validation without a stored version is not compared. The stored validation is not re-run or rewritten (append-only; re-running every pin per dry run would need Chrome), and approval is not refused (every rules bump would block every test); `banco.*/1` unchanged.
- **Why:** content agent (chemistry, step fix2): che-density-compute 641, -find-mass 642, -find-volume 643 (E-ROUNDTRIP) and che-state-change-names 652 (E-GEN-POOL) are passed under rules 1 but fail rules 6 on an unchanged resubmission. Missing feature (D-147 gave only a count).
- **Cost:** the warning does not say which codes the revision would get now; the author dry-runs the listed revisions and resubmits those that fail. The teacher's checklist still shows the old pass.
- **Status:** implemented

## D-150 · 2026-10-06 · a carried-forward verify.mjs that accepts wrong answers is `E-VERIFY-STALE`, not `E-VERIFY-VACUOUS`

- **Design ref:** A-06, D-141
- **Design said:** D-141 made a carried-forward verify.mjs that rejects clean seeds `E-VERIFY-STALE`; one that accepts a catalogue error value or a +1 or sign-flip mutant stayed `E-VERIFY-VACUOUS`, so the item counted as `failed`.
- **We do:** when the revision's verify.mjs is identical to its base's, the acceptance of wrong answers is also `E-VERIFY-STALE` (same message and detail; registry version 16), so `banco status` counts the item as `awaiting_verifier`. A verify.mjs the author wrote or changed keeps `E-VERIFY-VACUOUS`.
- **Why:** content agent (business, step fix2): the author changed the options, the old verify.mjs accepted the new distractor, and the item showed as failed.
- **Cost:** a carried-forward verify.mjs that was always vacuous also reads as stale; the verifier reads the findings either way.
- **Status:** implemented

## D-151 · 2026-10-06 · skill-graph coverage follows the engine for testlets and lists stored multi-skill testlets

- **Design ref:** D-098, D-137, D-144
- **Design said:** coverage lists `item_errors_not_in_graph` per sub item's skill; a testlet is charged to its first sub item's skill only (D-098).
- **We do:** (1) `banco skill-graph coverage`: a testlet's codes are checked against the first sub item's skill (where the engine reads them), and the skill counts as measured for that skill only. (2) New key `testlets_multi_skill`: passed stored testlets with sub items on several skills (`item`, `item_revision_id`, `skills`, `charged_to`); each would fail E-TESTLET-SKILLS on resubmission, so the agent re-validates them with one skill. Additive; `banco.*/1` unchanged. (3) Descent item order (agent issue 1) was already fixed by D-142 (`Plan#item_order`); no change.
- **Why:** content agent (spanish, step fix2): coverage asked for codes on skills where they have no engine effect and did not say the revision is stale.
- **Cost:** a graph that listed codes only for a non-first sub item skill now shows them under the first skill.
- **Status:** implemented

## D-152 · 2026-10-06 · graph and blueprint submits record the author session and refuse an invalid session header; `--agent` accepts parentheses

- **Design ref:** A-04, D-A04 (graph and blueprint submits need no session)
- **Design said:** graph and blueprint submits take no session, so their authorship was never recorded and any `X-Banco-Session` was ignored. The CLI accepted `--agent` only from `[A-Za-z0-9._/@ :+-]`, and answered "give --agent NAME and --model MODEL" for a bad name.
- **We do:** (1) a session stays optional on `skill-graph submit` and `blueprint submit`; when `X-Banco-Session` is sent it must be an author session of the token (`E-SESSION`, `E-SESSION-ROLE`, 422, nothing stored), and a valid one is stored as `author_session_id`. A real (not dry) submit only. (2) `banco session new --agent` also takes `(` and `)`, and a name outside the set is answered with a message that lists the allowed characters. `banco.*/1` unchanged.
- **Why:** content agent (italian, step promote): `--agent 'claude-code (promoted from staging)'` was refused with a misleading message; and a graph was submitted with `BANCO_SESSION` holding that error text, which was ignored and stored as revision 1 without authorship. Defects.
- **Cost:** production graph revision 1 of italian stays without an author session (append-only; an identical resubmission is a replay). Not corrected; the item revisions carry session 17. A graph or blueprint submit without any header still records no author.
- **Status:** implemented

## D-153 · 2026-10-06 · with a sidecar Chrome the harness URL defaults to `banco-harness`, and `banco health` probes Chrome-to-harness

- **Design ref:** A-06, D-04 (harness listener, internal only)
- **Design said:** Chrome reaches the harness at `BANCO_HARNESS_URL` (`http://banco-harness:3200` in production), else loopback. The production compose never set the variable, so Chrome (a separate container) was told `http://127.0.0.1:3200`, its own loopback: every generator validation failed with `E-CHROME-UNAVAILABLE` while `health` said `chrome: ok` (it only asked Chrome for its version). The 3200 listener is correctly not published on the host.
- **We do:** `Validation::Harness.base_url` is `BANCO_HARNESS_URL` if set, else `http://banco-harness:<HARNESS_PORT>` when `BANCO_CHROME_HOST` is set, else loopback. `Health` gains `harness`: with a sidecar, Chrome loads `<base>/up` and any HTTP status is `ok`, otherwise `unreachable` (turns `ok` false). `banco.*/1` unchanged.
- **Why:** content agent (math, step promote), production: nothing on host port 3200 (by design) and every generator dry run failed. Defect (deployment default).
- **Cost:** one more short Chrome page load in `health`.
- **Status:** implemented

## D-154 · 2026-10-06 · an identical resubmission of a revision that passed under older rules is validated again under the current rules

- **Design ref:** A-06, D-073 (replay), D-149 (W-RULES-OUTDATED)
- **Design said:** D-149 tells the author to dry-run pins that passed under older rules and resubmit those that fail. An identical submit is a replay and enqueues no job, so a revision that still passes could never get a validation under the current rules: the warning and `older_rules_pins` stayed.
- **We do:** a replay whose latest validation passed under another `rules_version` enqueues `ValidateItemRevisionJob`, which appends a new `item_validations` row (append-only). The job treats a passed verdict as final only when it was reached under the current rules (or has no stored version); a failed verdict stays final. The submit answer is unchanged (`replayed: true`); `banco work status REV --wait` shows the new row. `banco.*/1` unchanged, no new command.
- **Why:** content agent (chemistry, step sfix1). Defect (missing way to clear a warning).
- **Cost:** a revision that no longer passes becomes `failed` after the replay (as the dry run said); the author then fixes it by a new revision.
- **Status:** implemented

## D-155 · 2026-10-06 · a dotted abbreviation (a.C., d.C., m.c.m.) counts as one word in the readability rules

- **Design ref:** A-06, item brief rule 6 (sentences of at most 25 words)
- **Design said:** words are runs of letters and digits, so `a.C.` counted as two words (`a`, `C`) and `m.c.m.` as three. A history sentence with several `a.C.` tokens that a person counts as 27 words was reported as 30 (`E-READ sentence_length`). Production rules_version 6 and staging run the same counter; staging passed that item only because its revision was validated before the era-abbreviation split fix.
- **We do:** `Readability.count_words` collapses a dotted abbreviation (`DOTTED`) into one word before counting, for sentence length, instruction length and bold-span length. The splitter is unchanged (D: a.C. followed by a capital still ends a sentence). Only looser, so `rules_version` stays 6 and no pin is flagged `older_rules`.
- **Why:** content agent (history, step promote). Defect in the counter.
- **Cost:** none known; a sentence of 26 real words is still refused.
- **Status:** implemented

## D-156 · 2026-10-06 · the reuse_right widget label says answer, not category

- **Design ref:** D-092 (reuse_right), item brief (dropdown cloze pages)
- **Design said:** a matching part with `reuse_right` shows "Scegli per ogni voce la categoria giusta. Una categoria può servire per più voci." That fits a classification but not a cloze page of verb forms or articles.
- **We do:** the label is "Scegli per ogni voce la risposta giusta. Una risposta può servire per più voci." (`matching_reuse_label`). Text only; `banco.*/1` unchanged.
- **Why:** content agent (spanish, step sfix1). Defect in wording. The same report's first issue (an unchanged resubmission cannot clear W-RULES-OUTDATED) is D-154, already implemented.
- **Cost:** none.
- **Status:** implemented

## D-157 · 2026-10-06 · `items list` and `work status` show `awaiting_verifier`

- **Design ref:** D-141 (`awaiting_verifier` in `banco status`)
- **Design said:** only `banco status` counted a revision whose latest validation failed with only `E-VERIFY-MISSING` and/or `E-VERIFY-STALE` as `awaiting_verifier`; `items list` and `work status` showed the stored `failed`, so a verifier looking for it in `items list` never found it.
- **We do:** the `status` of an `items list` row and of `work status` is `awaiting_verifier` under the same rule (`ItemValidation#display_status`, shared with `banco status`). The stored status stays `failed`; `settled` and `codes` are unchanged; `work status --wait` treats it as the failed exit it was. `E-VERIFY-REJECTS` stays `failed`: it is the author's or verifier's own broken verify.mjs. Additive; `banco.*/1` unchanged.
- **Why:** content agent (chemistry, step sverify1). Defect: two views of one state disagreed.
- **Cost:** a script that compared the status to `failed` for these items must also accept `awaiting_verifier`.
- **Status:** implemented

## D-158 · 2026-10-06 · `review open` reads without a session

- **Design ref:** A-04, A-05 (sessions and independence), D-152 (reads and some submits take no session)
- **Design said:** every review command needed a reviewer session, so `banco review open REV` refused with `E-SESSION` even for someone who only wanted to read the item.
- **We do:** `review open` with no `X-Banco-Session` returns the same page when the token may hold a reviewer session (`E-AUTH` 403 otherwise). A header that is sent is checked as before (role, provider, independence, `E-SESSION` for a stray message). `review submit` and both `solve` commands still need a session: the session is what the independence rule records, and the blind solver must be a declared role. Opening records nothing, so reading does not make a session "have seen" the item. `banco.*/1` unchanged.
- **Why:** content agent (spanish, step sreview1). Defect: a read refused for lack of a record that reading never writes.
- **Cost:** a session-less read does not check the provider rule; that is checked at submit.
- **Status:** implemented

## D-159 · 2026-10-06 · `blueprint open` returns the submittable document

- **Design ref:** B-07, D-038
- **Design said:** `blueprint open` returned a wrapper (subject, name, revision, brief, items, descent targets); the blueprint was inside `revision.blueprint`, and submitting the whole output failed with `E-SCHEMA` on the wrapper keys.
- **We do:** the open page has a new top-level `document`: the latest stored blueprint alone (null when none), accepted as is by `blueprint submit`. The `next` hint and the blueprint brief say so. `banco.*/1` unchanged (a key added to the open page only).
- **Why:** content agent (business, step sreview1). Missing convenience, not a defect of validation.
- **Cost:** the page repeats the document (also under `revision.blueprint`).
- **Status:** implemented

## D-160 · 2026-10-06 · `work status` shows the queue and the rules version; `--wait` waits longer; identical dry runs are cached

- **Design ref:** A-06, D-154
- **Design said:** `work status` gave the verdict only; `--wait` stopped after 300 s; every dry run of a generator ran its 200 seeds again.
- **We do:** (1) `GET /api/v1/work/revisions/:revision` adds `queue_ahead` (older revisions with no final verdict: the Chrome lane runs one validation at a time, so this is how many run first; 0 once settled) and `current_rules_version` (the server's, to compare with the row's `rules_version`). The CLI `--wait` default is 900 s, and its `E-TIMEOUT` says how many are queued ahead and that `--timeout SECONDS` raises the wait. (2) `Validation::DryRun` keeps the result of an identical dry run (subject, files, flag, rules version, graph, references, syllabus, decisions) for 10 minutes, 64 entries per process; an error is never kept. (3) Staging showing items as passed under older rules was a stale staging (rules_version 1 against 6): `refresh.sh` brings it to origin/main; an author compares `rules_version` in the status with `current_rules_version`. `banco.*/1` unchanged (keys added).
- **Why:** content agent (law_economics, step promote1). Missing feature (queue visibility), stale staging, slow repeated dry runs.
- **Cost:** a dry run after a change to something outside the key (a code edit) can be served from memory for up to 10 minutes; a restart clears it.
- **Status:** implemented

## D-161 · 2026-10-06 · an author dry run that only waits for the verifier exits 0

- **Design ref:** A-06, D-141, D-157, D-160
- **Design said:** `work submit --dry-run` of a new generator item always ended 422 `E-VERIFY-MISSING`, since verify.mjs is written by the verifier; the author had no passing dry run.
- **We do:** when every code of a dry run is `E-VERIFY-MISSING` or `E-VERIFY-STALE` the answer is 200 `{dry_run: true, status: "awaiting_verifier", codes: [...], instances: N, next}`; the CLI exits 0. Any other code keeps 422. Nothing is stored. The dry run still runs the 200 seeds in Chrome (verify is the last phase, nothing to skip); an identical repeat is cached (D-160). The second issue (no queue visibility) was already D-160: `work status` has `queue_ahead`; the validation lane is one at a time, so a long wait is the queue, and `--wait` waits 900 s.
- **Why:** content agent (spanish, step promote1). Missing feature. `banco.*/1` unchanged (a new status value on a dry run answer).
- **Cost:** a script that treated any non-"passed" 200 as failure sees a new value.
- **Status:** implemented

## D-162 · 2026-10-06 · `banco health` shows the validation queue depth

- **Design ref:** D-101, D-160
- **Design said:** health reported chrome, chrome_egress and harness as `busy` with no hint why.
- **We do:** `Health.check` adds `validation_queue: {waiting: N}`, the revisions still waiting for a verdict (`ItemRevision.unsettled`, shared with `work status` `queue_ahead`). `busy` stays a non-failure; the key is informational and never gates. A `busy` chrome with `waiting > 0` is the single Chrome lane working through that queue.
- **Why:** content agent (chemistry, step promote1). Missing feature. `banco.*/1` unchanged (one added key). The same report's first issue (dry run of a generator item without verify.mjs gives E-VERIFY-MISSING) is the pre-D-161 behaviour: from D-161 on it is 200 `awaiting_verifier`, exit 0.
- **Cost:** none.
- **Status:** implemented

## D-163 · 2026-10-06 · the solve brief carries a complete `banco.solve/1` example

- **Design ref:** C-03, A-05
- **Design said:** the solve brief described only `answers[]`; the schema also requires `schema_version` and `revision` at the root, so a first submit of `{schema, answers}` failed with E-SCHEMA.
- **We do:** `briefs/solve.md` states the four required root keys and shows a minimal valid file; a test validates that example against the schema.
- **Why:** content agent (business, step solve1:0). Defect in the brief (documentation), not in the software. `banco.*/1` unchanged.
- **Cost:** none.
- **Status:** implemented

## D-164 · 2026-10-06 · brief session examples use the placeholder AGENT

- **Design ref:** C-03
- **Design said:** the solve, review and grade briefs showed `banco session new ... --agent omp` (or `claude-code`), which reads as an instruction for one particular agent.
- **We do:** the three briefs use `--agent AGENT`; the solve brief says AGENT is the name of the agent you are. A test refuses a concrete agent in any brief.
- **Why:** content agent (business, step solve1:3). Defect in the brief (documentation); the schema issue in the same report was already fixed by D-163. Briefs are read from git at runtime; no schema change.
- **Cost:** none.
- **Status:** implemented

## D-165 · 2026-10-06 · E-REVIEW-EMPTY names the rule each weak point failed

- **Design ref:** A-05
- **Design said:** evidence that says nothing is refused with E-REVIEW-EMPTY.
- **We do:** the message lists, per point, the rule it failed (word count with the actual count and the minimum of 4, or a stock phrase); the detail also carries `reasons` (`too_short` or `stock_phrase`) beside `points`.
- **Why:** content agent (business, step review1:2). Missing precision in a message, not a rule change. The checks are unchanged; `points` is unchanged, `reasons` is added (backward compatible).
- **Cost:** none.
- **Status:** implemented

## D-166 · 2026-10-06 · the solve brief states the testlet and short_answer answer shapes

- **Design ref:** C-03, A-05
- **Design said:** the solve brief listed answer shapes for the closed components, `normalized_text` and `expression` only.
- **We do:** `briefs/solve.md` adds the `testlet` answer (object from sub item id to that sub item's own answer, `{"dont_know": true}` to give up one) and the `short_answer` answer (plain string, recorded, not graded). A test checks both sentences.
- **Why:** content agent (spanish, step solve1:0). Defect in the brief (documentation); the envelope fields (`schema`, `schema_version`, `revision`) were already documented by D-163. The guessed shapes were correct. `banco.*/1` unchanged.
- **Cost:** none.
- **Status:** implemented

## D-167 · 2026-10-06 · the review brief tells reviewers to allocate a unique scratch directory

- **Design ref:** C-03
- **Design said:** the review brief suggested a scratch directory named after subject and round (`$TMPDIR/rv-SUBJECT-1`).
- **We do:** the brief says to create it with `mktemp -d "$TMPDIR/rv-SUBJECT-XXXXXX"` and never to `mkdir -p` a fixed name. A test checks the sentence.
- **Why:** content agent (business, step review1:3): a reviewer's `mkdir -p $TMPDIR/rev1` silently reused another session's folder. Missing guidance in the brief, not a defect in the software (the CLI and API never create or read that folder; the fixed name came from the agent or orchestrator). The reviewer kept independence by not reading the files. `banco.*/1` unchanged.
- **Cost:** none.
- **Status:** implemented

## D-168 · 2026-10-06 · the solve brief says a short_answer takes a sample answer, not `dont_know`

- **Design ref:** C-03, A-05
- **Design said:** a `short_answer` is not graded by the server, so a string answer is recorded and never a mismatch; `dont_know` on any instance is a major finding.
- **We do:** unchanged behaviour (a test now covers both paths: a sample string gives no finding, `dont_know` gives one major). `briefs/solve.md` says to write a short sample answer for an open writing task and not to send `dont_know`, which means the task could not be done from its text.
- **Why:** content agent (english, step solve1:3) sent `dont_know` for a free-writing item because the brief offered only "answer or dont_know" and got a major E-BLIND-SOLVE-MISMATCH. Classified as missing guidance, not a defect: the server already exempted free answers. Exempting `dont_know` as well would hide a task nobody could understand. Its second issue (testlet shape) was already fixed by D-166. `banco.*/1` unchanged.
- **Cost:** none.
- **Status:** implemented

## D-169 · 2026-10-06 · the solver and reviewer see the item prompt (an ordering's direction)

- **Design ref:** A-05, C-03
- **Design said:** the blind solver sees the item exactly as the student does.
- **We do:** `Review::ItemText#with_passage` now adds the item's `prompt` (`stem_it`, `table`, `quote`, `figure`) to the display of `banco solve open` and `banco review open`, beside the passage, for every non-testlet item. An instance's own `stem_it` stays; then the prompt stem is shown as `prompt_stem_it`. The stored display and `banco.*/1` are unchanged. `briefs/solve.md` says to keep the `BANCO_SESSION` id in a file when the shell does not persist.
- **Why:** content agent (chemistry, step solve1:2). An ordering's stored display holds only `elements`; the direction ("in senso crescente") lives in the prompt, which the student sees and the solver did not. Defect. Its first issue (root fields of answers.json) was already documented by D-166 in the brief; the agent read an older copy.
- **Cost:** none.
- **Status:** implemented

## D-170 · 2026-10-06 · E-SCHEMA says in plain words what a wrong constant or non-string member must be

- **Design ref:** A-06
- **Design said:** schema errors name the pointer and the library's message.
- **We do:** `Validation::SchemaCheck` words a `const` error as `/schema_version must be exactly 1, not "1"` and a `string` type error as `/revision must be a string (in quotes), not 379`. Errors were already reported in one pass (the missing members in one line); only the wording changes. `briefs/solve.md` already shows the full root (D-166). `banco.*/1` unchanged.
- **Why:** content agent (chemistry, step solve1:3) met three submits with cryptic messages ("is not: 1", "is not a string"). Classified as unclear wording, not a defect in the schema; the brief issue was already fixed.
- **Cost:** none.
- **Status:** implemented

## D-171 · 2026-10-06 · W-MESSAGE-GIVES-KEY: an error message that states an instance's key

- **Design ref:** A-06
- **Design said:** the brief's writing rule 4 forbids a message that gives the key; nothing checked it.
- **We do:** for static instances, `ItemRunner#message_gives_key` warns (`W-MESSAGE-GIVES-KEY`, field `.../error_catalogue/N/message_it`) when a catalogue `message_it` contains the key of any instance of the same unit (choice option text, or `Answers.key_texts`), 6 or more plain characters, whole-token match. Messages are item-level and shown after a wrong answer on any instance, so every instance key counts. Warning only; generated items are not checked (their keys vary by seed). `banco.*/1` unchanged.
- **Why:** content agent (chemistry, review1:0): revisions 116 and 122 passed with messages that wrote other instances' keys. Classified as a missing check (validator gap), not a defect in a past check.
- **Cost:** none; short keys (a number, one word) are deliberately not flagged.
- **Status:** implemented

## D-172 · 2026-10-06 · `blueprint open` shows `awaiting_verifier` in items[]

- **Design ref:** D-141, D-157
- **Design said:** D-157 aligned `items list` and `work status` with `banco status`, but `blueprint open` listed each item's raw stored status, so a revision whose only finding is `E-VERIFY-MISSING` or `E-VERIFY-STALE` showed as `failed`.
- **We do:** the `status` of an `items[]` row of `blueprint open` is `ItemValidation#display_status`, the same rule as the other views (`awaiting_verifier`; otherwise the stored status, `validating` when none). Additive; `banco.*/1` unchanged.
- **Why:** content agent (history, step author). Defect: one more view disagreed.
- **Cost:** a script that compared this status to `failed` must also accept `awaiting_verifier`.
- **Status:** implemented

## D-173 · 2026-10-06 · the solve brief says one submit per session and what `--dry-run` is for; no retraction

- **Design ref:** A-05, D-018 (second round is a new session)
- **Design said:** the blind solve is stored once, append-only; a second round uses a session that did not see the first; the teacher disposes of findings.
- **We do:** behaviour unchanged. `banco solve submit --dry-run` already exists, checks shape and unreadable answers and stores nothing; `briefs/solve.md` now says to run it before the real submit, that a session has one submit, and not to change an answer because of the dry run's mismatch count. No solver-side retraction and no per-instance mismatch in the dry run.
- **Why:** content agent (computer_science, step solve1:2) mistyped one answer and could not resubmit (`E-SESSION-NOT-INDEPENDENT`), leaving a false blocker. Classified as missing guidance. A retraction would let a solver edit the ledger and a per-instance dry-run mismatch would make the solve an oracle for the key, defeating blindness; the ledger is append-only. The orchestrator may run a fresh solver session for a clean round; the teacher dismisses the stale finding otherwise. `banco.*/1` unchanged.
- **Cost:** none.
- **Status:** implemented

## D-174 · 2026-10-06 · answer-format complaints from the blind solver: the stem names the format

- **Design ref:** A-05, D-079, D-169
- **Design said:** the solver sees what the student sees; D-079 gave expression items the `isolate` form (`y = expr` and `expr` both graded); D-169 added the item prompt to `banco solve open`.
- **We do:** no code change. The student's page has no placeholder or format hint, so the solver display cannot have one either; the format must be in the stem, which the solver now sees in full (D-169). `briefs/diagnosis-item.md` rule 13 now says: without `form: ["isolate"]` an answer `y = ...` is not the key of an expression item, so the stem says what to write; a `normalized_text` item always has a question naming what to write. The grader needs no change: `isolate` already accepts `y = expr`. The other two points of the report (root fields of answers.json, `BANCO_SESSION` per call) are D-166 and D-169/the brief, already done. `banco.*/1` unchanged.
- **Why:** content agent (math, step solve1:1). The 10 mismatches on revisions 388 and 428 are content mistakes (stem without a question; an expression item that wants a letter but lacks `isolate`), not defects of the software. The author should add the question to 388's stem and `isolate` to 428, as new revisions.
- **Cost:** none.
- **Status:** implemented

## D-175 · 2026-10-06 · an instance display with no question: the prompt is already shown (D-169); if none, the stem lacks it

- **Design ref:** A-05, D-169, D-174
- **Design said:** the solver sees what the student sees.
- **We do:** no code change. Since D-169 `banco solve open` adds the item `prompt` (`stem_it`, `table`, `quote`, `figure`) to every display, shown as `prompt_stem_it` beside an instance's own `stem_it`; the student's page shows the same two texts and nothing else (no hidden question). So if a display holds only "I numeri sono 12 e 40." the item has no question: a content mistake, as in D-174. The solve brief's root-keys skeleton (`schema`, `schema_version`, `revision`) was added by D-166 and is in `briefs/solve.md` Format; the agent read a copy from before. `banco.*/1` unchanged.
- **Why:** content agent (math, step solve1:2) on revisions 429 (math-lcm-shared-factors) and 424 (math-gcd-partial-common-factor): displays without a question. The agent probably ran before D-169 was deployed; if `solve open` still shows no `prompt_stem_it` after a deploy, the prompt is empty.
- **Cost:** none.
- **Status:** implemented

## D-176 · 2026-10-06 · solve brief root fields of answers.json: already documented (D-166)

- **Design ref:** A-05, D-166
- **Design said:** the solve brief states the four required root keys and shows a minimal valid file (D-166); a test validates that example.
- **We do:** no code change. `briefs/solve.md` Format already lists `schema`, `schema_version` (the number 1), `revision` (a string) and `answers`, with a minimal example; `banco solve submit --dry-run` and the E-SCHEMA wording (D-170) report any missing key in one pass. The agent read a copy from before D-166. `banco.*/1` unchanged.
- **Why:** content agent (math, step solve1:3): first submit with only `answers` failed with E-SCHEMA. Not a defect; the next solver run should re-read `banco brief show solve` and use the skeleton.
- **Cost:** none.
- **Status:** implemented

## D-177 · 2026-10-06 · reviewer scratch directory collision: already in the review brief (D-167)

- **Design ref:** A-05, D-167
- **Design said:** `briefs/review.md` tells reviewers to allocate a private scratch directory with `mktemp -d "$TMPDIR/rv-SUBJECT-XXXXXX"` and never to `mkdir -p` a fixed name such as `rev1`.
- **We do:** no code change. The reviewer used the fixed name `rev1` (and a fixed `sess.txt` inside it), which parallel sessions share; another session overwrote the session id file. Keeping the session id in a variable (`export BANCO_SESSION=$(banco session new ... --id)`) or inside the private directory avoids it. Sessions are server-side, so the stray extra reviewer session is harmless. `banco.*/1` unchanged.
- **Why:** content agent (computer_science, step review1:2). The fix on the workflow side is the same as D-167: a unique directory per reviewer. Not a banco defect.
- **Cost:** none.
- **Status:** implemented

## D-178 · 2026-10-06 · review open: programme lines from the skill and from the item's own sources

- **Design ref:** A-05
- **Design said:** `programme_lines` in `banco review open` were the lines the item's skill cites in the graph.
- **We do:** the list is the union of the skill's graph refs and the lines named by the item's own `sources[].ref` (form `SOURCE-KEY:LINE`, also in sub-items). Each entry gains `cited_by`: `both`, `skill` (graph only) or `item` (item sources only, `role` and `skill` null). Existing keys are unchanged, so `banco.*/1` stays compatible. Quotes from item-only lines are accepted too.
- **Why:** content agent (math, step review1:1): the item cited seconda:884 while the list showed 859; another item cited prima:69, which was missing. Missing feature: the reviewer must see the lines the item claims to rest on. A line found on one side only is now visible as such. Also reported: the shared scratch folder `rev1` was overwritten by a parallel session: already D-167 and D-177, no change.
- **Cost:** none.
- **Status:** implemented

## D-179 · 2026-10-06 · solver display of an ordering item: the prompt (direction) is already shown (D-169)

- **Design ref:** A-05, D-169, D-175
- **Design said:** the solver sees what the student sees; an ordering's direction lives in the item prompt, not in the instance display.
- **We do:** no code change. Since D-169 `banco solve open` adds the item prompt to every non-testlet display, ordering included (`Review::ItemText`, tested in `test/models/review/item_text_test.rb`: the prompt stem appears as `prompt_stem_it`). The student's page shows the same prompt above the elements. A display with only `elements` comes from a run before D-169 was deployed, or from an item whose prompt has no stem: a content mistake (an ordering always names its direction). `banco.*/1` unchanged.
- **Why:** content agent (biology, step solve1:0) on revision 519. Same cause as D-175.
- **Cost:** none.
- **Status:** implemented

## D-180 · 2026-10-06 · solve brief root fields of answers.json, second report: already documented (D-166, D-176)

- **Design ref:** A-05, D-166, D-176
- **Design said:** the solve brief states the four required root keys and shows a minimal valid file; a test validates that example.
- **We do:** no code change. `briefs/solve.md` Format lists `schema`, `schema_version`, `revision`, `answers` and a full minimal example. A dry run reports every missing key in one pass.
- **Why:** content agent (biology, step solve1:1) hit E-SCHEMA on a first submit built from an older copy of the brief. Not a defect.
- **Cost:** none.
- **Status:** implemented

## D-181 · 2026-10-07 · the author reads the findings on their revision

- **Design ref:** A-04, A-05, A-06
- **Design said:** the author sees validation codes and the teacher's send-backs; reviews are the reviewer's and the teacher's.
- **We do:** `banco work status REV` and `banco work open ITEM` (author view, not the verifier's) gain `review_findings`: every finding stored on the revision (reviews and blind solves, oldest first) with `id`, `source`, `severity`, `code`, `instance`, `field`, `quote`, `problem_it`, `fix_it`, `disposition` (when the teacher has decided) and `review_id` or `blind_solve_id`. New key only, `banco.*/1` unchanged. Dispositions stay teacher-only; no new command. `briefs/diagnosis-item.md` says where to read them.
- **Why:** content agent (chemistry, step pfix1): an author could not read the exact quote and fix of a finding and relied on a summary and a stray scratch file. Missing feature.
- **Cost:** a few rows per request.
- **Status:** implemented

## D-182 · 2026-10-07 · solve brief root fields of answers.json: already documented (D-166, D-176, D-180)

- **Design ref:** A-05, D-166
- **Design said:** the solve brief states the four required root keys and shows a minimal valid file.
- **We do:** no code change. `briefs/solve.md` Format lists `schema`, `schema_version` (the number 1), `revision` (a string) and `answers`, with a minimal example including all four; `--dry-run` and the E-SCHEMA wording report every missing key in one pass. `banco.*/1` unchanged.
- **Why:** content agent (biology, step solve1:3), same report as D-176 and D-180: it read an older copy of the brief. Not a defect. The solver should run `banco brief show solve` at the start of the session.
- **Cost:** none.
- **Status:** implemented

## D-183 · 2026-10-07 · short_answer in the solve brief and the author's review findings: already shipped (D-168, D-181)

- **Design ref:** A-05, D-168, D-181
- **Design said:** the solve brief tells the solver a `short_answer` takes a sample answer and never `dont_know`; the author reads the review and blind-solve findings of the revision through `work status` and `work open`.
- **We do:** no code change. `briefs/solve.md` (D-168) says a `short_answer` answer is a plain string, recorded and not graded, and that `dont_know` for it is a major finding; `solve open` already reports `component: short_answer`. `work status REV` and `work open ITEM` (D-181) carry `review_findings` for author sessions. Both reports predate the deployment of those entries or came from an older copy of the brief and the CLI. `banco.*/1` unchanged.
- **Why:** content agent (english, step pfix1). Not defects.
- **Cost:** none.
- **Status:** implemented

## D-184 · 2026-10-07 · the solver sees the prompt of every part, testlet sub items included

- **Design ref:** A-05, D-169, D-172, D-175
- **Design said:** the solver and reviewer see the item prompt as the student does (D-169); `blueprint open` shows `awaiting_verifier` like `banco status` (D-172).
- **We do:** `solve open` and `review open` already add `prompt.stem_it` (as `stem_it`, or `prompt_stem_it` beside an instance stem), `table`, `quote`, `figure` and `passage_it` for a plain item (D-169). The gap that remained is the testlet: its sub items' prompts were not added. `Review::ItemText#with_passage` now adds the passage once and, per sub item, the same parts. `blueprint open` items[] has used `display_status` since D-172. `banco.*/1` unchanged (new keys in a display only).
- **Why:** content agent (spanish, step pfix1) read the code and output of an older deployment: a blind solve (367 / solve 43) made before D-169 saw only `**problema**`. Its E-BLIND-SOLVE-MISMATCH findings are stale: the teacher disposes of them, or a new solve is run on the current deployment. The status report (revision 554) is D-172, already shipped.
- **Cost:** none.
- **Status:** implemented

## D-185 · 2026-10-07 · solve open shows the prompt stem; answers.json root documented: no change (D-169, D-180, D-182)

- **Design ref:** A-05, D-169, D-180, D-182
- **Design said:** the solver sees the item prompt as the student does; the solve brief states the four required root keys.
- **We do:** no code change. A plain item keeps its stem in `prompt.stem_it` (required by `item.json` for every item), and `solve open` adds it to the display as `stem_it` (or `prompt_stem_it` beside an instance stem) since D-169; `test/models/review/item_text_test.rb` covers it. Revisions whose instances carry their own `stem_it` already showed one; a prompt-only item such as revision 31 showed none on a deployment older than D-169. `briefs/solve.md` Format lists `schema`, `schema_version`, `revision`, `answers` with a minimal example. `banco.*/1` unchanged.
- **Why:** content agent (law_economics, step solve1:0). Neither report is a defect on the current deployment. The solver should run `banco brief show solve` and re-open the revision after the deployment. If a revision still shows no stem on the current build, its prompt is the content mistake and the author sends a new revision.
- **Cost:** none.
- **Status:** implemented

## D-186 · 2026-10-07 · first submits reset during a restart; ordering direction and solve brief envelope: no change (D-169, D-180, D-182)

- **Design ref:** A-05, D-169, D-180, D-182
- **Design said:** the solver sees the item prompt, an ordering's direction included (D-169); the solve brief states the four root keys with a full example (D-180).
- **We do:** no code change. Connection resets on the first submits: the production container had been restarted by a deployment minutes before (the API listener is down for a short while on a restart); the documented wait and retry is the right answer, and nothing is lost because a rejected connection records nothing. `briefs/solve.md` Format shows a full file with `schema`, `schema_version`, `revision`, `answers`. `solve open` adds `prompt.stem_it` to the display (an ordering's direction lives in it, D-169); an ordering whose prompt carries no direction is a content mistake and the author sends a new revision. `banco.*/1` unchanged.
- **Why:** content agent (law_economics, step solve1:3). Not defects.
- **Cost:** none.
- **Status:** implemented

## D-187 · 2026-10-07 · testlet answer shape in the solve brief: already shipped (D-166), no change

- **Design ref:** A-05, D-166
- **Design said:** the solve brief states the testlet and short_answer answer shapes (D-166).
- **We do:** no code change. `briefs/solve.md` Format says a testlet answer is an object from each sub item id to that sub item's own answer, in the shape of the sub item's component (`{"s1": "b", "s2": {"n": 3, "d": 4}}`), and `{"dont_know": true}` as a value gives up one sub item. The map the agent used is that shape. `banco.*/1` unchanged.
- **Why:** content agent (law_economics, step solve1:4). The agent read a build or brief copy older than D-166; not a defect.
- **Cost:** none.
- **Status:** implemented

## D-188 · 2026-10-07 · scratch folder, transient refusal, unreachable matching errors: already covered (D-167, D-145, D-147), no change

- **Design ref:** D-145, D-147, D-167
- **Design said:** the review brief tells reviewers to create their scratch directory with `mktemp -d "$TMPDIR/rv-SUBJECT-XXXXXX"` (D-167); `W-ERROR-UNREACHABLE` (D-145, since 2026-10-06) warns on a matching error value that repeats a right-hand id; `banco status` counts passed items validated under older rules (D-147).
- **We do:** no code change. (1) The suggested `mktemp -d` is already in `briefs/review.md`; a fixed name like `rev1` is the agent's choice, not a defect. (2) One `E-NETWORK` connection refused on the API listener while the app restarts for a deploy is the documented wait and retry; not a defect. (3) Revisions 229, 231, 232, 234 and 235 were validated before D-145 and stay `passed` (the ledger is append-only, stored validations are not rewritten); the review dry run checks the review, not the item, so it cannot show the item warning. The warning stays a warning: making it an error would fail items the teacher may still accept and would not fix old revisions. `banco.*/1` unchanged.
- **Why:** content agent (law_economics, step review1:2). Not defects; (3) is a content mistake on old revisions.
- **Cost:** none. The author dry-runs the pinned matching items (`banco work submit DIR --dry-run`), rewrites value maps as one-to-one mappings (or sets `display.reuse_right` for a classification), and resubmits new revisions; the reviewer reports unreachable values as a finding.
- **Status:** implemented

## D-189 · 2026-10-07 · "un giorno solo" is not an absolute word; review findings for the author already shipped (D-181)

- **Design ref:** A-06, D-094, D-181
- **Design said:** `da solo` is removed before `W-ABSOLUTE` (D-094); the author reads the reviews' findings in `work open` and `work status` (D-181).
- **We do:** (1) `solo/sola/soli/sole` right after a determiner and one noun, and closing the phrase (followed by punctuation, the end, `non` or `si`), is the adjective "single" and is removed before `W-ABSOLUTE`: "da un giorno solo non si conosce il clima", "una volta sola". "un atto solo se ..." still warns. (2) No code change: `banco work status REV --json` and `banco work open ITEM --json` (author view) carry `review_findings` with id, source, severity, code, instance, field, quote, problem_it, fix_it, disposition; no new command. `banco.*/1` unchanged.
- **Why:** content agent (geography, step pfix1). (1) defect (false positive, a warning only); (2) already shipped, the agent used a build older than D-181.
- **Cost:** a rare "il tutore solo, firma" style phrase escapes the warning.
- **Status:** implemented

## D-190 · 2026-10-07 · solver prompt.stem_it already shipped (D-169, D-184); API connection reset was a restart; no change

- **Design ref:** A-05, D-169, D-184
- **Design said:** the blind solver sees the item as the student does.
- **We do:** nothing new. `Review::ItemText#solver_instances` goes through `with_passage`, which adds `prompt.stem_it` (as `stem_it`, or `prompt_stem_it` beside an instance stem), `table`, `quote`, `figure` and `passage_it` (D-169; testlet sub items D-184). Tests: `test/models/review/item_text_test.rb`. The reported connection reset (`E-NETWORK`, 2026-10-06T15:41Z) matches the restart of puma at a deploy; health was ok afterwards.
- **Why:** content agent (math, step pfix1) read the output of a deployment older than D-169: solves 176 and 180 pre-date it. Not a defect now. The E-BLIND-SOLVE-MISMATCH findings on 388 and 428 are stale; run a new blind solve on the current deployment.
- **Cost:** none.
- **Status:** implemented

## D-191 · 2026-10-07 · solve brief root fields: already documented with a minimal example; no change

- **Design ref:** A-06, D-166, D-176, D-180
- **Design said:** the solve brief tells the solver the shape of `answers.json`.
- **We do:** nothing new. `briefs/solve.md` (section Format) lists the four required root keys `schema`, `schema_version`, `revision`, `answers` and a minimal JSON example; the schema is `config/banco/schemas/solve.json`. The first-submit E-SCHEMA came from a build older than D-166 (or from a brief read before it).
- **Why:** content agent (italian, step solve1:1). Not a defect now; run `banco brief show solve` on the current deployment.
- **Cost:** none.
- **Status:** implemented

## D-192 · 2026-10-07 · review brief states the E-REVIEW-EMPTY evidence rule; the line 224 ref is a content mistake

- **Design ref:** A-05, D-145
- **Design said:** a bare "all verified" is refused (brief rule 2).
- **We do:** `briefs/review.md` rule 2 now says what the server already enforced (`Review::Checklist`): evidence of at least 4 words (`MIN_WORDS`), not a stock phrase, distinct per point; refusal `E-REVIEW-EMPTY` with `detail.points`. Test: `test/models/brief_test.rb`. The brief hash changes, so reviewers must re-read it.
- **Content mistake, no code change:** `italian.complements` citing `seconda-2025-26:224` (a Spanish line) is a wrong mapping written by the graph author; the server stores whatever lines the graph cites and cannot judge the language of a programme line. The fix is a new graph revision without that ref. The typo on line 420 ("Rifleterre") is a transcription doubt for the teacher, raised as a note, not decided by an agent.
- **Why:** content agent (italian, step review1:0).
- **Cost:** none.
- **Status:** implemented

## D-193 · 2026-10-07 · solve brief root fields (chemistry): repeat of D-191; no change

- **Design ref:** A-06, D-166, D-176, D-191
- **Design said:** the solve brief tells the solver the shape of `answers.json`.
- **We do:** nothing new. `briefs/solve.md` (section Format) already lists `schema`, `schema_version`, `revision`, `answers` with a minimal example (see D-191).
- **Why:** content agent (chemistry, step solve2:0) hit E-SCHEMA once and fixed it from the error text. Not a defect; read `banco brief show solve` on the current deployment before the first submit.
- **Cost:** none.
- **Status:** implemented

## D-194 · 2026-10-07 · W-ERROR-UNREACHABLE reads pair-list error values; where the warning shows

- **Design ref:** D-145, D-092, A-06
- **Design said:** a matching error value that repeats a right id (no `reuse_right`) can never be submitted, so it is warned (D-145).
- **We do:** the check already existed (D-145, a warning, the item still passes) but read only the object form `{"l1":"r2"}`; it now reads the pair-list form `[["l1","r2"]]` too (`Answers.matching_raw`). Still a warning, not an error: `banco.*/1` unchanged. It shows in `banco work submit DIR --dry-run` (`warnings`) and in the stored validation findings, not in `banco review submit --dry-run` (that dry run checks review.json only, `codes:[]` is about the review).
- **Why:** content agent (italian, step review1:1) saw rev 16 pass with values such as `{b:r2,c:r2}`; `codes:[]` came from the review dry run. Partly a defect (pair-list form skipped), partly where the warning appears.
- **Cost:** none. Kept a warning so existing passed items are not invalidated; the author fixes it with a one-to-one value or `reuse_right`.
- **Status:** implemented

## D-195 · 2026-10-07 · solve brief root fields (history): repeat of D-191 and D-193; no change

- **Design ref:** A-06, D-166, D-176, D-191, D-193
- **Design said:** the solve brief tells the solver the shape of `answers.json`.
- **We do:** nothing new. `briefs/solve.md` (section Format) lists `schema`, `schema_version`, `revision`, `answers` with a complete minimal example; `test/models/brief_test.rb` asserts the example carries all four keys.
- **Why:** content agent (history, step solve1:0) needed three attempts, which means it submitted before reading the current brief. Classified as a content mistake (not a defect, not a missing feature).
- **Cost:** none.
- **Status:** implemented

## D-196 · 2026-10-07 · solve brief root fields and testlet shape (history, solve1:1): repeat of D-191; no change

- **Design ref:** A-06, D-166, D-176, D-191, D-193, D-195
- **Design said:** the solve brief tells the solver the shape of `answers.json`.
- **We do:** nothing new. `briefs/solve.md` (section Format) already lists `schema`, `schema_version`, `revision`, `answers` with a minimal example, and says a testlet answer is an object from each sub item id to that sub item's own answer, with an example; `test/models/brief_test.rb` asserts both.
- **Why:** content agent (history, step solve1:1) reported the same E-SCHEMA; it submitted before reading the current brief. Content mistake, not a defect or missing feature.
- **Cost:** none.
- **Status:** implemented

## D-197 · 2026-10-07 · W-ABSOLUTE skips "un solo" and "non ... solo"

- **Design ref:** A-06, D-094, D-189
- **Design said:** an absolute word (`solo`, `soltanto`, ...) is warned (D-094); D-189 already skipped "un giorno solo" (adjective after the noun).
- **We do:** `Validation::Readability` also skips `solo/sola` right after `un/uno/una` ("un solo ambiente") and `solo/soltanto` after `non` in the same clause, up to 3 words between ("non danno solo energia", "non solo"). Still a warning; `banco.*/1` unchanged. "Solo il tutore firma" and "un atto solo se" still warn. Test: `test/validation/readability_test.rb`.
- **Why:** content agent (biology, step pfix1) got false positives and reworded. Defect (false positive). Authors need not reword.
- **Cost:** a rare true "not ... only" absolute claim is no longer warned.
- **Status:** implemented

## D-198 · 2026-10-07 · review brief: evidence on absence points needs the fields read

- **Design ref:** A-05, E-REVIEW-EMPTY
- **Design said:** every checklist point needs evidence of at least 4 words that is not a stock phrase.
- **We do:** no code change. `briefs/review.md` rule 2 now says the same holds for absence points (3, 8, 10) and gives an example ("No test-taking advice." has 3 words and is refused; "Read stem, options and feedback of instances 1 and 2: no test-taking advice." is accepted). `test/models/brief_test.rb` asserts it.
- **Why:** content agent (italian, step review1:3) wrote "No test-taking advice." on point 8 and got E-REVIEW-EMPTY. The check is as documented (the error already reports "3 words, at least 4 needed"); content mistake, brief clarified. The agent resubmitted and was accepted.
- **Cost:** none.
- **Status:** implemented

## D-199 · 2026-10-07 · solve brief root fields (history, solve1:2): repeat of D-191; no change

- **Design ref:** A-06, D-166, D-176, D-191, D-193, D-195, D-196
- **Design said:** the solve brief tells the solver the shape of `answers.json`.
- **We do:** nothing new. `briefs/solve.md` (section Format) already lists `schema`, `schema_version`, `revision`, `answers` with a complete minimal example; `test/models/brief_test.rb` asserts it. Reproduced: the E-SCHEMA text names the missing properties, as designed.
- **Why:** content agent (history, step solve1:2) reported the same E-SCHEMA as solve1:0 and solve1:1; it submitted before reading the current brief. Content mistake, not a defect or missing feature.
- **Cost:** none.
- **Status:** implemented

## D-200 · 2026-10-07 · blind solve on a short_answer, solve brief root fields (history, solve1:3): already shipped; no change

- **Design ref:** A-05, A-06, D-166, D-168, D-183, D-191
- **Design said:** a `short_answer` is solved with a plain string that the server records and does not grade; the brief states the root keys.
- **We do:** nothing new. `Api::V1::SolvesController#finding_for` returns no finding for a `short_answer` answer (verdict `short_answer`); only `dont_know` raises the major E-BLIND-SOLVE-MISMATCH, which is what the agent triggered by sending `dont_know`. `briefs/solve.md` (Format) names the short_answer shape, forbids `dont_know` for it, and lists the four root keys with a full example.
- **Why:** content agent (history, step solve1:3) sent `dont_know` for rev 72 and submitted before reading the current brief. Content mistake, not a defect. Finding 489 is the teacher's to dispose of (a solver error, not an item flaw).
- **Cost:** none.
- **Status:** implemented

## D-201 · 2026-10-07 · solve brief root fields and testlet shape (english, solve2:0): repeat of D-191; no change

- **Design ref:** A-06, D-166, D-176, D-191, D-196, D-199
- **Design said:** the solve brief tells the solver the shape of `answers.json`.
- **We do:** nothing new. `briefs/solve.md` (section Format) already lists the four root keys `schema`, `schema_version`, `revision`, `answers` with a complete minimal example, and gives the testlet answer shape (an object from sub item id to that sub item's answer, `{"s1": "b", "s2": {"n": 3, "d": 4}}`); `test/models/brief_test.rb` asserts it. E-SCHEMA names the missing properties, as designed.
- **Why:** content agent (english, step solve2:0) submitted before reading the current brief. Content mistake, not a defect or missing feature.
- **Cost:** none.
- **Status:** implemented

## D-202 · 2026-10-07 · solve brief root fields (spanish, solve2:0): repeat of D-191; no change

- **Design ref:** A-06, D-166, D-176, D-191, D-201
- **Design said:** the solve brief tells the solver the shape of `answers.json`.
- **We do:** nothing new. `briefs/solve.md` (section Format) lists the root keys `schema`, `schema_version` (1), `revision` (the id passed to `banco solve open`) and `answers`, with a minimal example; `test/models/brief_test.rb` asserts it. E-SCHEMA names the missing properties, as designed.
- **Why:** content agent (spanish, step solve2:0) submitted before reading the current brief. Content mistake, not a defect or missing feature.
- **Cost:** none.
- **Status:** implemented

## D-203 · 2026-10-07 · author could not read review findings through the CLI; line ranges in scope_reason_it (chemistry, pfix2)

- **Design ref:** D-181 (review findings for the author), D-063..D-068 (W-REF-OTHER-SUBJECT, teacher comments)
- **Design said:** `work status` and `work open` carry `review_findings`; a reason naming the line clears W-REF-OTHER-SUBJECT.
- **We do:** (1) `banco work status REV` already printed `review_findings` (the server answer is passed through; the agent ran it before D-181 reached production). `banco work open ITEM` did not: the CLI rebuilt its answer from a fixed list of keys and dropped `review_findings` and `teacher_comments`. It now prints both (new keys only, `banco.*/1` unchanged). (2) `scope_reason_it` naming a range `N-M` (hyphen, en or em dash) now names every line from N to M; the warning text says so. A range that stops short of the line still warns. Not changed: the reviewers' findings stay out of `review open` (a reviewer must not read earlier findings).
- **Why:** The author fixes what the reviewer wrote, and an honest range is a label.

## D-204 · 2026-10-07 · solve brief root fields and testlet shape (geography): repeat of D-191; no change

- **Design ref:** A-06, D-166, D-176, D-191, D-201
- **Design said:** the solve brief tells the solver the shape of `answers.json`.
- **We do:** nothing new. `briefs/solve.md` (section Format) lists `schema`, `schema_version` (1), `revision` and `answers`, with a minimal example, and gives the testlet shape (`{"s1": "b", "s2": {"n": 3, "d": 4}}`, `{"dont_know": true}` per sub item).
- **Why:** content agent (geography, step solve2:0) submitted before reading the current brief; the E-SCHEMA messages it saw are the server naming the missing keys. Content mistake, not a defect.
- **Cost:** none.
- **Status:** implemented

## D-205 · 2026-10-07 · solve brief root fields (math): repeat of D-191; no change

- **Design ref:** A-06, D-166, D-176, D-191
- **Design said:** the solve brief tells the solver the shape of `answers.json`.
- **We do:** nothing new. `briefs/solve.md` (section Format) lists `schema`, `schema_version` (1), `revision` (a string) and `answers`, with a minimal example.
- **Why:** content agent (math, step solve2:0) asked for exactly that example; it is already there. The E-SCHEMA messages it saw name the missing keys and the string type. Content mistake, not a defect.
- **Cost:** none.
- **Status:** implemented

## D-206 · 2026-10-07 · superseded revisions listed as awaiting_verifier (chemistry, pverify2)

- **Design ref:** D-157 (`items list` shows `awaiting_verifier`), D-129 (`current` marker)
- **Design said:** `items list` shows every revision with the display status of its latest validation, so an old revision whose validation failed only with `E-VERIFY-MISSING` or `E-VERIFY-STALE` read `awaiting_verifier`, though `banco status` counts only current revisions.
- **We do:** in `items list`, a revision that is not current and would read `awaiting_verifier` reads `superseded`. Current rows, `work status` and the stored validation are unchanged. Additive value; `banco.*/1` unchanged. A queue scan should still use `--current`.
- **Why:** content agent (chemistry, step pverify2). Defect (misleading status), cosmetic.
- **Cost:** a script that looked for `awaiting_verifier` on a non-current row now sees `superseded`.
- **Status:** implemented

## D-207 · 2026-10-07 · solve open of a superseded revision (biology, solve2:0)

- **Design ref:** A-05 (blind solve), D-206
- **Design said:** `solve submit` refused a revision that is not the latest (E-STALE-BASE) with the hint `banco work open KEY`; `solve open` served any revision, so a solver could work a superseded one for nothing.
- **We do:** `solve open` refuses a non-latest revision with 409 E-STALE-BASE; the hint of `solve open`, `solve submit`, `review submit` is the step's own open command on the latest revision (`banco solve open LATEST`, `banco review open LATEST`). `review open` keeps serving old revisions (read only). `banco.*/1` unchanged.
- **Why:** content agent (biology, solve2:0). Three issues. (1) Root fields of answers.json: already documented with a minimal example (briefs/solve.md, D-166, D-176, D-191); no change. (2) Ordering direction: the student's prompt shows the item's prompt stem (`prompt_stem_it`, D-169) beside the instance stem, and `solve open` shows the same text; if the stem of 524 does not state the direction it is a content mistake for the author or reviewer (the review checklist covers a stated direction), not a software defect. (3) Defect, fixed here.
- **Cost:** a solver that opened an old revision for reading now gets an error.
- **Status:** implemented

## D-208 · 2026-10-07 · W-ACCEPT-ITEM-LEVEL (italian, pfix1)

- **Design ref:** D-081 (per-instance `accept`), A-06
- **Design said:** the item-level `accept` is added to every instance at grading time; nothing warned when an entry was meant for one instance's key.
- **We do:** a static `normalized_text` item with two or more different keys gets the warning `W-ACCEPT-ITEM-LEVEL` for each item-level `accept` entry that is not within one edit (case and punctuation aside) of every instance key; the message points at the per-instance `accept`. Warning only, status unchanged; `banco.*/1` formats unchanged.
- **Why:** content agent (italian, step pfix1): rev 20 had `"un po'"` at item level with keys `po'`, `ha`, ...; it was graded correct on every instance and nothing said so. Missing validation, not a grading defect.
- **Cost:** a deliberate item-level spelling far from some key now warns.
- **Status:** implemented

## D-209 · 2026-10-07 · review open of a superseded revision (biology, review2:0)

- **Design ref:** A-05, D-158, D-206, D-207
- **Design said:** `review open` serves any revision read-only (D-207 kept that); `review submit` refuses a non-latest one with E-STALE-BASE, so a reviewer could do a full review of revision 517 and find it unfileable.
- **We do:** `review open` adds `current` (bool) and `superseded_by` (the latest revision id, else null); when superseded, `next` reads "superseded: a review of this revision cannot be filed; run banco review open LATEST". Additive; `banco.*/1` unchanged. Opening stays allowed. The scratch-directory issue is already covered by the review brief (`mktemp -d "$TMPDIR/rv-SUBJECT-XXXXXX"`); handing out unique names is the orchestrator's, not the software's: content mistake.
- **Why:** content agent (biology, review2:0). The submit refusal is correct; the missing signal at open time was a defect.
- **Cost:** none.
- **Status:** implemented

## D-210 · 2026-10-07 · solve open shows the root of answers.json (english, solve3:0)

- **Design ref:** A-06, D-166, D-176, D-191
- **Design said:** the root fields are in `briefs/solve.md` (Format) with a minimal example; nine agents were told no change (D-191..D-205).
- **We do:** `solve open` adds `file_root` (`schema`, `schema_version` 1, `revision` as a string, `answers` described). Additive; `banco.solve/1` unchanged. Tenth report of the same thing, and the agents evidently work from the `solve open` output, so the hint goes where they look.
- **Why:** content agent (english, solve3:0), suggested exactly this.
- **Cost:** none.
- **Status:** implemented

## D-211 · 2026-10-07 · `review open` reads with the author's own session; the solve Format lists short_answer

- **Design ref:** A-04, A-05, D-158, D-168, D-181, D-183
- **Design said:** `review open` took no session or a reviewer session; an author session was `E-SESSION-ROLE`. The solve brief's Format list named the components without `short_answer` (the sentence about it follows the list).
- **We do:** (1) a session header that is an author session of this token that wrote a file of the item reads the page like a session-less read (nothing is recorded; solver, verifier and strangers are refused as before). (2) `briefs/solve.md` Format now lists "a plain sample string for `short_answer`" in the main sentence. Not changed: `dont_know` on a `short_answer` stays one major finding (D-168: it means the task could not be done from its text; a sample string never gives a finding). The author's review and blind-solve findings are already in `banco work open ITEM` and `banco work status REV` as `review_findings` (D-181, D-183); those answers have them only on the latest revision, and only when the CLI and server are current. `banco.*/1` unchanged.
- **Why:** content agent (history, step pfix1). Issue 1 is guidance (repeat of D-168): classified content mistake of the solver, answer a sample string. Issue 2 is mostly D-181 (already shipped); the refusal of an author session on `review open` was a small real gap.
- **Cost:** none.
- **Status:** implemented

## D-212 · 2026-10-07 · author cannot read review findings through the CLI (math): already shipped; no change

- **Design ref:** D-181, D-183, D-203
- **Design said:** `banco work status REV --json` and `banco work open ITEM` carry the stored findings of the reviewers and blind solvers for the author.
- **We do:** nothing new. The findings are under `review_findings` (id, source, severity, code, instance, field, quote, problem_it, fix_it, disposition, review_id or blind_solve_id), a separate key from `findings` (validation findings) and `teacher_comments`. `work status` passes the server answer through; `work open` prints the key since D-203. The answer lists them for the revision asked, so a superseded revision's findings come from `work status OLD_REV`. A reviewer or solver finding is a row on its source; a blind-solve mismatch is a finding with `blind_solve_id` (`source` says which). The checklist point is the finding's `code`. An older CLI or server (before D-181/D-203) lacks the key: refresh with the deployed `banco`.
- **Why:** content agent (math, step pfix2) read `findings: []` and `teacher_comments: []` and did not see `review_findings`, or ran a build before D-181. Classified: already shipped, not a defect.
- **Cost:** none.
- **Status:** implemented

## D-213 · 2026-10-07 · solve brief root fields (law_economics, solve3:0): repeat of D-195; no change

- **Design ref:** A-06, D-163, D-191, D-195
- **Design said:** the solve brief tells the solver the shape of `answers.json`.
- **We do:** nothing new. `briefs/solve.md` (section Format) says the file needs `schema`, `schema_version` (the number 1), `revision` (a string) and `answers`, with a complete `banco.solve/1` example since D-163; `test/models/brief_test.rb` asserts it. `banco solve submit REV --file F --dry-run` reports E-SCHEMA before anything is stored.
- **Why:** content agent (law_economics, step solve3:0) saw E-SCHEMA for missing root fields and a numeric revision: it wrote the file from the old list or from memory, not from the current brief. Classified as a content mistake, not a defect and not a missing feature (a `solve template` command would repeat the example in the brief).
- **Cost:** none.
- **Status:** implemented

## D-214 · 2026-10-07 · operator decision: the calculator is allowed in mathematics too

- **Design ref:** operator "calculator", `docs/rules/diagnosis-1.md` section 10, D-106
- **Design said:** `Rules::V1::CALCULATOR` was no in mathematics, yes in business and chemistry; the mathematics start screen said "Fai i calcoli sul foglio, senza calcolatrice".
- **We do:** `CALCULATOR["math"]` is `:yes` (supersedes the maths default; business and chemistry stay yes). The start screen of mathematics now shows the calculator_yes line. A blueprint's own `calculator` field still wins at approval. We do NOT add math to `readability.calculator_subjects`: W-CALCULATOR would flag every numeric maths item that lacks the sentence, and the start screen states the rule once. Items in mathematics need not say it. Rules doc section 10, the item brief and the tests that pinned the old default are updated.
- **Why:** operator decision 2026-10-07: "per matematica facciamo usare la calcolatrice".
- **Cost:** none; blueprints already approved that declare `calculator: "no"` keep their declaration.
- **Status:** implemented

## D-215 · 2026-10-07 · operator request: all the questions of a test on one page; approve by confirming they were seen; close the preview

- **Design ref:** B-07, C-04, D-08, M9a/M9b
- **Design said:** B-07 asked the teacher to play the whole test once as S before approving; a run closed in the context `teacher_preview` pinned to the revision was the proof.
- **We do:** (1) `GET /teacher/subjects/:key/test/all` (`Teacher::TestsController#all`, `Teacher::AllQuestions`): every pinned item of the latest revision, entries then descent, grouped by skill, with all stored instances drawn read-only by the student's own templates (inputs disabled, nothing posted); the first instance open, the others under "Altre N varianti". Keys, typical errors, solutions and rubrics are in hidden blocks that "Mostra risposte" opens in the browser. Opening the page records `teacher_viewed_item` for every pinned revision. Linked from the test page and each skill page. (2) New decision `confirm_test_reviewed` ("Ho visto tutte le domande di questa prova"), written only by `DecisionRecorder` with the usual guards, for the latest revision, and only when every pinned item was opened. (3) `Approval::BlueprintGate`: "played" is met EITHER by a closed `teacher_preview` run of this revision OR by `confirm_test_reviewed` for this exact revision; the viewed-items condition still applies. (4) "Chiudi l'anteprima" (`POST /teacher/preview/runs/:run_id/close`, preview only) appends `run_closed` with reason `teacher_close` to the preview run, never to a student's run; the gate does not count a preview closed that way as played.
- **Why:** operator request 2026-10-07: "vedere tutte le domande insieme per la singola prova; ok se non riesco a rispondere?"
- **Cost:** the teacher can approve without answering every item; the ledger says which way (the decision row, or the played run). The page carries all the answers, but it exists only for the teacher (web listener, trusted teacher).
- **Status:** implemented
- **Back-port:** B-07: "played the whole test once as S" becomes "played it, or reviewed all the questions and confirmed".

## D-216 · 2026-10-07 · operator request: more instructions in the test, steps and answer format on items, the formula sheet as a declared support

- **Design ref:** B-05, B-09, X-02, A-03, A-06, C-03
- **Design said:** the start screen had six lines and the item showed its prompt and an input with a one-line label; nothing told the student how each input works while answering; no support changed what an item measures, so the report had nothing to mark.
- **We do:** the principle: a support that removes construct-irrelevant noise (not knowing how to type, losing the thread of a long item) is fine and changes no evidence; a support that changes what is measured (a formula sheet) is declared, off by default, recorded per item and visible in the report. Read-aloud was not chosen.
  (1) Instructions. The start screen has a "Come funziona" block (`sitting.intro.*`, `#how-it-works`): the questions change with the answers, how long, you can pause, "Non lo so" and "Non l'ho ancora studiato" are fine and are not errors, what to do on paper and whether the calculator is allowed (the existing line), it is not a grade, how to send, where the help is, and (only when the sheet is on) the Formulario and that the exam has none. On the sitting page "Come si risponde" is a `<details>` under the item that follows the item's component (`items/help_sections.js`, texts in `sitting.help.*`: number with the decimal comma, fraction boxes, the formula editor with the warm-up's examples, choice, ordering, matching, text, short answer, testlet with one section per sub item component). Opening it posts `help_opened` (component, run, served item) to `POST .../runs/:id/support`, which writes an `app_event` and nothing else: the engine, the grader and the report read none of it.
  (2) `banco.item/1` gains optional `answer_format_it` (string, at most 300) and `steps_it` (2 to 6 strings, at most 200 each), on the item, on a testlet sub item, and per instance inside `display` (also what a generator returns); an instance's own text wins; they are not allowed on a testlet's top level. The student page shows the steps as a numbered list "Cosa fare" above the input and the format under it; the teacher's all-questions page and item play use the same renderer and presenter, so they show them too, and the blind solver's text includes them. Validation: every text is linted as Italian (each step on its own, role `text`); new `E-SUPPORT-LEAK` refuses any of these texts that contains the key or any declared error value of the instance it is shown with (item-level text is checked against every instance, per instance, with the same normalisation as `E-SOLUTION-IN-DISPLAY`; a choice is compared by option text); the two fields are left out of the old display scan so a leak is reported once; new warning `W-STEPS-METHOD` when a step names a method word of the item's subject (`supports.method_words` in `validation_rules.yml`, matched whole, best effort). The rules version is not bumped: the checks fire only on the new fields.
  (3) Formula sheet. `banco.blueprint/1` gains optional `formula_sheet_it` (at most 2000 characters, restricted markup with `$latex$`, linted as Italian text, `E-READ`/`E-SCHEMA`). New decision kind `set_formula_sheet {subject, enabled}` (route `POST /teacher/subjects/:subject/formula-sheet`), written only by `DecisionRecorder` with every guard (flag, trusted teacher, CSRF, web listener, not the student's device); `enabled: true` only when the approved entry test (else the latest draft) has a sheet; the latest decision counts; default off. The teacher's test page shows the sheet, its state and the switch. When a run serves an item, `Diagnosis::Conductor` writes `item_served.formula_sheet_available` (new column, written once with the row: the ledger stays append-only) = decision on and the run's pinned blueprint has a sheet. Only then does the step reply carry `formula_sheet_it` (never in the page or the JSON otherwise) and the sitting page show a "Formulario" button that opens it read-only. Every opening posts `formula_sheet_opened` and appends an `app_event` (run, served item); the endpoint refuses (403) a serve without the sheet. The engine evidence is unchanged: no engine input reads any of this (a test plays the same answers with and without the sheet and compares the outcomes). `Diagnosis::Report` (`banco.diagnosis_report/1`, `banco diagnosis report --json`) adds, per skill, `formula_sheet {attempts, available, opened}` and `marks` ("con formulario disponibile", "con formulario consultato"), and per subject a `formula_sheet` summary with `enabled`; the teacher's report page shows both plainly with the sentence that the exam has no sheet. Counts are of answered attempts; available includes opened.
  (4) Briefs: `briefs/diagnosis-item.md` (section "Supports") and `briefs/blueprint.md` (shape and rule 10) say what the fields are for, the leak rule and that a sheet holds formulas and definitions only, no worked example of a method the test measures. `docs/rules/diagnosis-1.md` section 14 states the report shape. A global `[hidden] { display: none !important }` in the stylesheet: an author `display` on `.button` was showing hidden buttons.
- **Why:** operator request 2026-10-07: "il test deve essere fatto con più istruzioni e per DSA deve aiutare di più". Choices: more instructions; steps for long items; formula sheet as a declared support.
- **Cost:** the fields sit at the item (and sub item) root and in `display`, not under `prompt`, so a revision stored before has none (nothing to migrate). An example in `answer_format_it` of three or more characters that equals a key or a declared error is refused, as the other leak checks do; one or two characters are not checked. A skill result obtained with the sheet is not a different evidence level: it is marked, and the teacher reads it with the exam in mind. The sheet's availability is read at serve time: switching it off does not take it from an item already served.
- **Status:** implemented
- **Back-port:** A-03 (`banco.item/1`, `banco.blueprint/1`: optional fields), B-09 (report: marks for the formula sheet), X-02 (the sitting page: help and sheet), D-08 (decision kinds: `set_formula_sheet`).

## D-217 · 2026-10-07 · operator request: trial students, two teachers who act, one guest who only reads

- **Design ref:** D-02, D-08, firm rules 1 and 2, B-07, B-09, M9b, M10
- **Design said:** one student (key `student`) and one teacher list; identity only from `EdgeTrust` (edge peer plus web listener); every teacher page and write needed a trusted teacher.
- **We do:** three roles and a second kind of student. Env names are fixed:
  `BANCO_TEACHER_USERS` (existing; logins that are teachers when also in the group `banco-teacher`), `BANCO_GUEST_USERS` (new; a guest is in the group `banco-guest`, listed here and not a teacher), `BANCO_STUDENT_USERS` (new; `login=student_key,...`; the key `student` is the official student, `Student::OFFICIAL_KEY`, any other key matching `[a-z0-9-]+` is a trial student; `preview` is reserved for the teacher's preview and ignored), `BANCO_LOGOUT_URL` (new, optional; "Esci" link on teacher, guest and student pages, hidden when unset). Logins may contain `@` and `.`.
  (1) Identity. `EdgeTrust::Identity` keeps `teacher?` and adds `guest?`, `reader?` (teacher or guest), `student?` (in the student group, not a teacher or guest, and mapped), `student_key`, `unconfigured_student?`. A login in the teacher and student groups is a teacher only. With `BANCO_STUDENT_USERS` unset any student login is the official student (staging, old setups); with it set an unmapped student login gets a 403 page "Account non configurato: chiedi all'insegnante" and no row. Student rows are created on first login with kind `student` (no migration: the CHECK allows it); `Student#trial?` is kind `student` with another key.
  (2) Guest. Every GET teacher page is readable by a reader. Every non-GET under `/teacher`, every decision route, the heartbeat and the whole `/teacher/preview` area (start, sittings, answers, close, index) are for the teacher only: 403 for a guest, nothing written. Opening an item or a page that records `teacher_viewed_item` writes nothing for a guest. `DecisionRecorder` keeps its own trusted-teacher guard. Views: `decision_form` and the preview buttons are not drawn for a guest; every teacher page shows "Sei in sola lettura" for a guest and "Accesso: LOGIN · insegnante|ospite" for everyone. The tests walk the routes table, so a route added later is covered.
  (3) Trial students. Same pages, same engine, own runs, attempts, warm-up, seen instances and preferences. No consent and no release are needed (`ActingStudent#diagnosis_open?`). For a subject they get the approved blueprint if there is one, else the newest blueprint revision whose pinned items all passed validation (`Conductor.blueprint_for`, `Conductor.latest_validated_blueprint`), so the flow can be tried before approval. The pages show "Account di prova: i risultati non contano". They never set the device cookie (`DecisionRecorder::DEVICE_COOKIE`): they are adults on their own computers and the cookie would block the teacher's decisions from that browser. Their runs never count in `Approval::BlueprintGate` (only the `preview` student does) and never touch the official student's availability, release, report or seen instances.
  (4) The teacher's views. "The student" still means the official student: `release_diagnosis`, `record_consent`, `void_revision_attempts`, `banco status`, the reconciliation of the log (`DecisionReconciliation` looks at the official student's runs only). Where the teacher looks at a student's data (home, report, corrections) a `?student=KEY` choice lists the trial students ("Prova: LOGIN") and keeps the choice in the links; the key is checked against existing rows (404 otherwise). Decisions on a trial student's runs and attempts (confirm or reject a grade, resolve an attempt, extend, close or void a run) are allowed and record that student's id. `banco diagnosis report` takes `--student KEY` (API `?student=KEY`, 404 `E-NOT-FOUND` when unknown; default official).
- **Why:** operator request 2026-10-07: two teachers who can interact, one read-only guest, and a couple of trial students besides the official one.
- **Cost:** the real login names live only in the private infrastructure configuration, never in git. The grade proposals the agent sees (the pending submissions) include trial answers, which is useful to test the evening loop. A trial student on a blueprint that is not approved sees a test the teacher may still change: its runs are for trying, not for the record. The preview area is closed to the guest even to read.
- **Status:** implemented
