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
Never ask for a decision.

## Format

`answers[]`: one entry per instance, `{instance, answer}` or `{instance, dont_know:
true}`. The answer has the shape the component asks for: a string with the decimal
comma for `number`, `{n, d}` for `fraction`, the option id for `choice`, the
element ids in order for `ordering`, a map left id to right id for `matching`, a
string for `normalized_text`, a LaTeX string for `expression`.

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
