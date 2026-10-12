# Gallery: family `checks` (check components and options)

Status: T1 built the first three (D-272). A gallery of this family is not a lesson file: the components are shown by a system test, because a select
needs a figure that offers targets and the only way to show it before one does is a probe figure of eight equal zones.

## Shown (look gate)

`test/system/lesson_checks_system_test.rb` draws `test/fixtures/lesson2/served/checks.json` (an invented English lesson: a sentence, two `tiles` checks, an
`ordering` check) and the select over the probe, and takes screenshots into `BANCO_SHOT_DIR` at 1366 x 900 cream, 1366 x 900 dark and 390 x 844 cream
(`checks-tiles-1366.png`, `checks-tiles-dark-1366.png`, `checks-tiles-390.png`, the same for `ordering`, `select`, and `checks-sentence-english-390.png`).
Each card shows its fixed how-to line on first use (A9), the closed "Come si risponde", the keyboard path (tests) and, for the teacher, the answer by its
words and names (`LessonChecksTeacherBoxTest`).

- `select` (available, schema final, batch w2-1, track T1)
- `tiles` (available, schema final, batch w2-1, track T1)
- `ordering` (available, schema final, batch w2-1, track T1)
- option `verify` (field `verify`; available, T1): no picture, its bad fixture is `bad/verify-disagrees.md`
- option `profile` (field `profile`; available, T1)
- option `thousands` (field `thousands`; available, T1)
- option `reachable_ok` (field `reachable_ok_it`; available, T1)

## Still to show

- `amount_words` (draft, schema draft, batch w2-2, track T8)
- `cell_formula` (reserved, schema none, batch w2-3, track T9)
- `trace` (reserved, schema none, batch w2-3, track T9)
- option `listen` (field `listen`; reserved, batch w2-1, track T2)
- option `chem_formula_profile` (field `profile`; draft, batch w2-2, track T7)
- option `input_bits` (field `input`; reserved, batch w2-1, track T9)
- option `contractions` (field `contractions`; reserved until the vetted table english/contractions is written; the engine is built and tested)
