---
name: diagnosis-item
version: 1
formats: banco.item/1
---

# Brief: diagnosis items (version 1)

You write items for the entry diagnosis of one student: closed questions that
show, skill by skill, what the student already does well, what to revisit and
what is new. The goal is to teach and to measure honestly, never to "pass a
check". Every item is data in the `banco.item/1` format (`config/banco/schemas/item.json`,
`additionalProperties: false`); the server grades against instances stored at
validation, so the key never travels to the student.

Start with `banco status` and this brief. Work only through `banco`. Never ask for
a decision: you stop at `awaiting_teacher`.

## What you write

A revision is a folder: `item.json`, optionally `generator.mjs`, and `assets/`.
`verify.mjs` is written only by a verifier session, who never sees the generator.

- `verify.mjs` contract: an ES module with a named export `verify(instance)` (sync or
  async) returning `{ok: boolean, reason_it?: string}`; `ok` must be exactly `true` to
  accept. `instance` is `{display, answer, errors, solution, seed}` (plus `accept` when
  the item has one), the same shape the generator returns. The verifier solves the
  `display` independently and compares with `instance.answer`: it must return `ok: true`
  for every clean instance and `ok: false` for the same instance with `answer` replaced
  by a catalogue error value, a +1 mutant or a sign-flip mutant. For `choice` the
  `answer` is an option id, never the option text. A throw counts as a rejection;
  `reason_it` (at most 200 characters) is shown in `E-VERIFY-REJECTS`. Same banned
  globals as generators; no import of the generator.
- `kind`: `diagnosis_item`, `short_answer` or `testlet` (a reading passage of
  150-300 words with exactly 5 closed sub-items, all on the same skill: the testlet has one attempt,
  counted for that skill only, `E-TESTLET-SKILLS` otherwise).
- One difficulty level. No hints field: during the diagnosis there is no help.
- Component per item: `number`, `fraction`, `expression`, `choice`, `ordering`,
  `matching`, `normalized_text`, `short_answer`.
- `error_catalogue[]`: `{code, description_it, message_it, implicates[]}`. Codes
  are snake_case and come from the registry or are new and descriptive. The engine reads the
  errors of a skill from the graph alone: a new code must first be in the `errors` of that skill
  in the graph (with the same `implicates`), else `W-ERROR-NOT-IN-GRAPH` and the code is treated
  as unclassified (descent into every parent).
- A `number` error whose value is a non-terminating decimal (a calculator result such as 9,8067 or
  3,3333) is declared with `round_to`: `{code, value: "9,81", round_to: 2}` matches every answer
  that rounds half up to 9,81 at 2 decimals. It never matches the key (`E-GEN-SCHEMA` if it would).
  Implicates into another subject whose graph is not approved yet: leave them out of the item and
  declare them as `deferred_implicates` in your graph (an item implicate there is only
  `W-IMPLICATE-PENDING`, and the engine ignores it anyway).
- Generators export `generate(seed, rng)` and return
  `{display, answer, errors: [{code, value}], solution: {steps, final}}`. They
  import only `/lib/rng.mjs` and `/lib/fmt.mjs`. No `Math.random`, `Date`,
  `performance`, `crypto`, `Intl`, `toLocaleString`, `eval`, `Function`, `fetch`,
  `XMLHttpRequest`, `WebSocket`, dynamic `import(`, `importScripts`.
- Pools: a generator gives 24 clean seeds of 1..200. A static item has at least 2
  instances. Per skill in a blueprint: at least 6 distinct instances over at
  least 2 items, 3 of them hard to guess, unless the skill declares
  `redo_reserve: false`.
- Run `banco work submit DIR --dry-run` until it exits 0, then submit.
- The cycle: `banco work open ITEM` (or a new folder named after the item key; `work open` writes `$TMPDIR/banco-work/ITEM` (outside the repo; a verifier gets `ITEM.verifier`, never the author's folder, and `work open` refuses a folder of the other role) unless you pass `--dir`, and reopening a folder deletes files the opened revision does not have; the CLI warns when a `--dir` is inside a git work tree),
  edit, `banco work submit DIR --dry-run`, `banco work submit DIR`, `banco work
  status REV --wait`. The first submit fails with `E-VERIFY-MISSING` but stores the
  instances: a verifier then runs `banco work open ITEM --role verifier` (item,
  tests and every stored instance with its answer, never the generator) and submits
  `verify.mjs`. Always start from `work open`: it records the base revision in `.banco/work.json`; a hand-made folder for an existing item has no base and fails with `E-STALE-BASE` (the fix is to open it, or pass `--item KEY --base REV`). The graph first: `banco skill-graph open|submit --subject KEY`.
- The teacher can send an item back ("Rimanda"). `banco work open ITEM` and `banco
  work status REV` then carry `teacher_comments`: for each one the revision, a
  `reason_code` (`wrong_key`, `ambiguous_text`, `wrong_error_code`, `off_programme`,
  `too_hard`, `too_easy`, `unclear_wording`, `other`) and a `comment_it`. Read them
  before you edit; a sent-back revision is never approved, so answer with a new
  revision that fixes what the comment says. `banco status` counts them in
  `items.sent_back`.
- A `normalized_text` item that does not measure accents says `accent_policy: "flag"`
  (a slip in an accent is then credited with a note); one that does says `strict`.
  Choice, ordering, matching and the other components carry no `accent_policy`
  (they are graded by id; the validator refuses it with E-ACCENT-POLICY).
- When the answer is a word of a sentence the student must analyse, put the sentence
  in the stem between `«` and `»`: a key found only inside the quotes is the material
  and gets no W-ANSWER-IN-STEM. A key outside the quotes still does.
- `accept` may also sit on one instance (D-081): other spellings of that instance's
  key only, so another instance's key is never accepted.

## The writing rules (version 1)

1. **Sources.** Every skill cites a line of the prior-year programme, or is
   declared `middle_school` or `not_in_prima`; and it has a line of the current
   year's programme that needs it, directly or through a skill that depends on it.
   A citation is `(source, line, fragment)` with the fragment an exact substring
   of the line. Never cite a transcriber line (headings, page markers). Never
   invent a page number, a line number or a quotation: if you do not have it, say
   so in the item's `sources` as `inferred` with the reason.
2. **First item: hard to guess.** The first item of a skill is written
   (`number`, `fraction`, `expression`, `normalized_text`), an `ordering` of 4 or
   more, or a `matching` of 4 or more pairs. A `choice` as first item needs a
   written `choice_only_reason_it` that the teacher will read.
3. **Choice.** 3 to 5 options, 4 preferred, never 2. Every distractor is a typical
   error with its own code. **Exactly one option is defensible**: before you submit,
   try to defend each distractor; if you can, rewrite it. Distractors are the
   mistakes a real learner makes, not nonsense and not "all of the above".
4. **Messages.** Every typical error has `message_it` of at most two sentences:
   the wrong step and the right one. It never scolds and never gives the key of
   another instance.
5. **No help, no solution in the text.** The solution lives in `solution`. The
   text of the correct option appears nowhere outside the options (stem, table,
   figure alt, SVG text; in a testlet, also the passage: a key option of 20 or
   more characters found word for word in `passage_it` is `E-SOLUTION-IN-DISPLAY`).
6. **Readability** (plain language for readers who need it). Italian sentences of
   at most 25 words; the instruction (stem) at most 60 words; bold only on key
   words, at most 3 spans of at most 4 words; no ALL-CAPS words, no italics, no
   emoji; mathematics between `$...$`; decimal comma. One idea per sentence, no
   double negations.
   A short text of your own to read before the question (an informative text, the
   text to summarise) goes in the item's `passage_it` (kinds `diagnosis_item` and
   `short_answer`; up to 2400 characters, linted as a passage, shown to the student,
   the grader, the solver and the teacher above the question; in english and spanish the passage
   and a rubric's `model_answer_it` are in that language and are not linted as Italian). It is not part of the
   stem, so the 60-word cap does not count it. A quoted excerpt of an imported text goes in `prompt.quote`
   `{ref, text}`, not in the stem: `banco reference list` shows the imported
   reference texts and `banco reference show --key KEY` their body; `text` must be
   an exact substring of it (E-QUOTE-REF). If no suitable text is imported, do not
   paste an excerpt into the stem or the options: write the item without it and
   report the missing text; the operator imports public-domain excerpts with their
   source (D-074).
7. **Phrases never used.** No exam-gaming ("la risposta che cercano", "cosa
   scrivere", "se il prof", "a lezione") and no self-certification
   ("è verificato"). No personalisation and no data about the student.
8. **No over-absolute rules.** Every "sempre", "mai", "solo" in a rule or a
   message is tested against a counterexample before it is written (some in
   offers, enough after the adjective, the existence condition of a fraction
   holds for every denominator). When a rule has exceptions, name it as a
   tendency or leave it out.
9. **Test use, not metalanguage.** In foreign languages the item measures use
   (choose the form, complete the sentence), not the grammar terms. In Italian,
   clause and logical analysis is content. Keep terms neutral until the
   textbook's own terms are known.
10. **Facts with sources.** History, law, biology and geography facts carry a
    source. No borderline or disputed cases (for example mining among the
    economic sectors, or "Australia as a continent"). A law or a reference text
    (the Costituzione, a statute) is cited with source kind `legal_text`: `ref` is
    the act and article (`Costituzione art. 3`), `fragment` an optional exact
    phrase. `textbook` is only the student's own textbook.
11. **Transcription doubts go to the teacher.** If a programme line is unclear,
    cut off or looks like a transcription error, do not guess and do not build on
    it: write it in your report to the teacher and leave the skill out until the
    answer.
12. **The previous year's exam (Prova A) is one instance, not the target.** Use only
    its structure, with new numbers (the item's optional `exclude_params`: the exam's values, each written
    as it would appear; an instance that shows one fails `E-PROVA-A-PARAMS`); the declared error
    answers differ from each other and from the key; lcm items use numbers that
    are not coprime. Never copy its numbers, its wording or its answers.
    Per-instance spellings (normalized_text): an instance may carry `accept`, other
    spellings of its own key (`"accept": ["x = 0"]` on the instance whose key is `0`; for English, a key `did not go` with `"accept": ["didn't go"]`); the
    item's `accept` applies to every instance. The item's `tests` (`must_accept`, `must_reject`) run on the first
    stored instance only (the first clean seed: seed 1 unless seed 1 throws or is rejected, in which case the next one), so write them for that instance's
    key; an instance's own `tests` run on that instance (use them for any other seed). A `matching` key is by default a one-to-one pairing: each of the n left entries gets a different one of the n+1 right entries (one is left over); a key that repeats a right id is rejected (reported as `E-GEN-SCHEMA` on the answer, also for a static item). A `matching` that classifies cases (4 or more rows and 3 or more categories, or 6 or more rows and 2 categories; always fewer categories than rows) sets `display.reuse_right: true` on every instance: the key may repeat a category; the right column is then the categories alone (no spare). A dropdown cloze page (one form per sentence, a form may be needed twice) is the same shape: set `reuse_right: true`, list each form once in the right column, with fewer forms than sentences. The right column of a `matching` is plain text (no `$`, no backslash:
    `E-MATCHING-RIGHT-MARKUP`). A `form_skill` should be a prerequisite of the item's skill
    (`W-FORM-SKILL-CLOSURE` otherwise: credit, but no tail suspect).
13. **Calculating subjects.** Numeric items are generators. A numeric answer
    without letters uses `number` or `fraction`; `expression` is only for answers
    with letters or irrational values, with one-digit exponents. To isolate a letter
    (`r = ...`) give the answer `{latex, unknown}` with `form: ["isolate"]`: the student may
    type `r = I/(Ct)` or just `I/(Ct)`. To ask for an algebraic fraction in lowest terms (the student
    cancels a common polynomial factor) give `form: ["reduced"]`: a fraction whose numerator and
    denominator, polynomials in one letter, still share a factor is `wrong_form`
    (`common_factor_not_cancelled`); `lowest_terms` only checks integer content. Business amounts
    use `number` with unit euro and 2 decimals; computer science states the
    KB convention in the stem. Where the calculator is allowed (business,
    chemistry) every numeric stem says so; a `number` item may list other right values in `accept` (`["273,15"]`, for a convention the teacher leaves open) and may declare `form: ["scientific"]` to ask for `a·10^n` with 1 <= a < 10 (the same value in another shape is `wrong_form`, violation `scientific_notation`); elsewhere numbers are chosen for hand
    calculation.
14. **Scope.** No content of the in-progress (star-empty) lines and no content of
    the following year inside items of skills the student has already studied.

## Public repository

The code and these briefs are public. Items for the course live in the database,
but anything you write into a report or a file the repository can see is public.
No name of the student or of the household, no school, no city, no exam-session
details, no programme text. Say "the student" and "the teacher".
