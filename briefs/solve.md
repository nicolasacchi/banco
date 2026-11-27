---
name: solve
version: 5
formats: banco.solve/1
---

# Brief: blind solve (version 5)

You solve the instances of one item revision exactly as the student sees them,
and write `banco.solve/1` (`config/banco/schemas/solve.json`). The server grades
your answers; every disagreement with the key becomes a blocker finding for the
teacher. You never see the key, the generator, the verify or the review.

Start with `banco status` and this brief. Open your session first:
`export BANCO_SESSION=$(banco session new --role solver --agent AGENT --model MODEL --id)` (AGENT is the name of the agent you are, MODEL the model you run);
the model must be a different model than every author of the item (the family may be the same) (`E-PROVIDER-NOT-ALLOWED`) and the
session new to the item (`E-SESSION-NOT-INDEPENDENT`). `banco solve open REV` gives you the instances in display form (stems, tables,
options, elements) and writes every figure the item shows as a PNG file (see Figures below).
`banco solve submit REV --file answers.json` sends the answers.
If your shell does not keep variables between calls, write the session id to a file in your work folder and export it again before each `banco` call (`E-SESSION` otherwise).
Never ask for a decision.

A session has only one submit for an item: a stored answer cannot be retracted or corrected,
and a second submit is refused (`E-SESSION-NOT-INDEPENDENT`). Before the real submit, check the
file with `banco solve submit REV --file answers.json --dry-run`: it stores nothing and refuses
a wrong shape, a missing or doubled instance and an answer the grader cannot read (a number with
a dot, an empty string), so fix those first. It also prints a mismatch count; do not change an
answer because of that count, since the solve is blind and a disagreement is for the teacher to
judge. Read each answer once more against the display before you submit.

## Pictures of the instances (look at them first)

`banco solve open REV` asks the server to draw every instance as the student sees it on a 390 px phone and prints `item_shots.fetch`, the
command that brings the pictures: `banco item shots REV --dir DIR --wait` writes `DIR/REV/instance-NN_390x844.webp`, one whole-page picture per
instance (NN is the instance number of your `instances`). **Look at the picture of an instance before you answer it** (open the WebP as an image):
it shows what the student sees, the shape of the answer box and the way a table, a formula or an option is laid out, which the text of
`solve open` does not. A choice, a matching and an ordering are drawn shuffled with a fixed seed, as the student's page shuffles them: the number
on an option, a row or a step is its position in `shown_order` (printed with each file: `shown_order.options[n-1]` is the stored id of option n),
and the stored ids are what your `answers.json` uses. If the pictures are not ready, `--wait` waits for them: a minute or two on a quiet server, and as long as the server says the render is queued or running when the queue is long (it prints your place on stderr; 3600 s is the cap, `--timeout` shortens the stretch without progress); if they
cannot be had, answer from the text and say so in your report. Something broken in a picture (text cut at the edge, a formula that did not draw,
an option you cannot tell from another) is for the lead: report it, do not guess.

**Test the form of an answer before you file it.** Whether a contraction («'s scared» for «is scared»), brackets, punctuation, case or accents are accepted cannot be read off anything you see: `banco item grade REV --instance N --answer "…"` grades it through the student's own path and prints the verdict, what matched and the message the student would read (`--answer` may be repeated; `--answers-file FILE` takes one JSON array of `{instance, answer}`). It stores nothing.

## Figures

An item may show a drawing (a graph, a curve, a diagram). `banco solve open REV` writes each one as a PNG file in
`banco-figures/REV/` (`--dir DIR` chooses another parent folder: the files go to `DIR/REV/`, so several revisions can share it) and prints `figures`: for each file its `path`, its `alt_it`
(the text a student reads when the picture does not load) and the `instances` that show it; an instance's `display.figure` names
its file (`file`). **Look at every figure file before you answer** (open the PNG as an image; the alt text is not the
drawing), and read values from the drawing as a student would. The pictures are the drawings and nothing
more: no key, no data table behind them.

Never answer `dont_know` because a figure is missing or unreadable: stop, do not submit, and report it to the lead
(the figure is `missing: true`: `banco solve open` still prints the item, with a `warnings` line, but exits with `E-FIGURE-MISSING`; or a file did not come, or the picture is cut or unreadable). `dont_know` is for a
question you cannot answer with the whole item in front of you.

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

## Items in English or Spanish with the Italian (D-402)

An item of `english` or `spanish` may show each text twice: the language it teaches (`stem_en`, `stem_es`, an option's `text`, `hints_*`…) and its Italian
beside it (`stem_it`, `text_it`…). `banco solve open` gives you **both layers**, as the student has them when he opens the translation. **Answer from the
target-language text**, as a student who is learning the language would; the Italian is only there to help him read. If you can answer correctly from the Italian
alone, without reading the target text (a «translate this» task whose Italian is the exercise, an Italian option that is the answer, an Italian stem that
names it), say so in your report as a `translation_leak`: the teacher reads it. A mistake or a mismatch between the two texts is a `translation_fidelity` note, not
a reason to change your answer.

An item that says `translate_material: false` (form material) has no Italian for its sentence, options and rows: you read them in the target language only, as the student does; the instruction and hints keep their Italian.

A reading passage has no Italian in your copy (`passage_it` is missing): the student reads that translation only after he has answered, so you answer
from the English or Spanish passage alone, as he does.

## Rules (version 2)

1. Solve as a competent student of the stated level would: no tricks, no use of the
   position or length of options, no guessing from the style of the item.
2. If an instance has two defensible answers, or none, answer what you think best
   and say it to the teacher in your report: that is exactly what the blind solve
   exists to find.
3. If you really do not know, send `dont_know`; do not guess to look good.
4. Use the Italian decimal comma. Do not add explanations to the file; the format
   forbids extra fields.
5. You are a different model family from the author and a different session from
   the author, the verifier and the reviewer. Work only from the display text and its figure files.
6. Never invent a source or a citation for an answer.
7. Every answer that differs from the key becomes a blocker finding. The teacher sees the key and your raw answer side by side, and the author answers the finding (`banco findings respond`). Write your answer exactly as a student would type it.

## Public repository

Anything written to a file the repository can see is public: say "the student"
and "the teacher", with no names, school, city or exam details.
