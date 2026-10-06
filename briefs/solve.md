---
name: solve
version: 1
formats: banco.solve/1
---

# Brief: blind solve (version 1)

You solve the instances of one item revision exactly as the student sees them,
and write `banco.solve/1` (`config/banco/schemas/solve.json`). The server grades
your answers; every disagreement with the key becomes a blocker finding for the
teacher. You never see the key, the generator, the verify or the review.

Start with `banco status` and this brief. Open your session first:
`export BANCO_SESSION=$(banco session new --role solver --agent AGENT --model MODEL --id)` (AGENT is the name of the agent you are, MODEL the model you run);
the model must be a different model than every author of the item (the family may be the same) (`E-PROVIDER-NOT-ALLOWED`) and the
session new to the item (`E-SESSION-NOT-INDEPENDENT`). `banco solve open REV` gives you the instances in display form (stems, tables,
options, elements). `banco solve submit REV --file answers.json` sends the answers.
If your shell does not keep variables between calls, write the session id to a file in your work folder and export it again before each `banco` call (`E-SESSION` otherwise).
Never ask for a decision.

A session has only one submit for an item: a stored answer cannot be retracted or corrected,
and a second submit is refused (`E-SESSION-NOT-INDEPENDENT`). Before the real submit, check the
file with `banco solve submit REV --file answers.json --dry-run`: it stores nothing and refuses
a wrong shape, a missing or doubled instance and an answer the grader cannot read (a number with
a dot, an empty string), so fix those first. It also prints a mismatch count; do not change an
answer because of that count, since the solve is blind and a disagreement is for the teacher to
judge. Read each answer once more against the display before you submit.

## Format

`answers[]`: one entry per instance, `{instance, answer}` or `{instance, dont_know:
true}`. The answer has the shape the component asks for: a string with the decimal
comma for `number`, `{n, d}` for `fraction`, the option id for `choice`, the
element ids in order for `ordering`, a map left id to right id for `matching`, a
string for `normalized_text`, a LaTeX string for `expression`. For a `testlet` the
answer is an object from each sub item id to that sub item's own answer, in the shape
of the sub item's component (`{"s1": "b", "s2": {"n": 3, "d": 4}}`); to give up one
sub item write `{"dont_know": true}` as its value. For a `short_answer` the answer is
a plain string: the server records it for the teacher and does not grade it, so
an open writing task never produces a mismatch. Write a short sample answer; do not send
`dont_know` for it (that is a major finding: the task could not be done from its text).

The file needs four keys at the root, all required: `schema`, `schema_version`
(the number 1), `revision` (the revision id you passed to `banco solve open`, as a
string) and `answers`. Nothing else is allowed. A minimal file:

```json
{
  "schema": "banco.solve/1",
  "schema_version": 1,
  "revision": "179",
  "answers": [
    {"instance": 1, "answer": "42,5"},
    {"instance": 2, "dont_know": true}
  ]
}
```

## Rules (version 1)

1. Solve as a competent student of the stated level would: no tricks, no use of the
   position or length of options, no guessing from the style of the item.
2. If an instance has two defensible answers, or none, answer what you think best
   and say it to the teacher in your report: that is exactly what the blind solve
   exists to find.
3. If you really do not know, send `dont_know`; do not guess to look good.
4. Use the Italian decimal comma. Do not add explanations to the file; the format
   forbids extra fields.
5. You are a different model family from the author and a different session from
   the author, the verifier and the reviewer. Work only from the display text.
6. Never invent a source or a citation for an answer.

## Public repository

Anything written to a file the repository can see is public: say "the student"
and "the teacher", with no names, school, city or exam details.
