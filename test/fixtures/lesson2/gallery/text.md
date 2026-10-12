# Gallery: the text layer and "Ascolta" (T2, D-281, D-282)

Status: built. This gallery is not a lesson file: the text layer belongs to no figure family, so it is shown by system tests over two invented served
lessons, `test/fixtures/lesson2/served/text.json` (english: spans, a role span of a language subject, `[[time|it:..]]`, code spans, glossary words, a
heard check, a cloze) and `test/fixtures/lesson2/served/text_chemistry.json` (`\ce{}` and `\pu{}` with mhchem).

## Shown (look gate)

`test/system/lesson_text_system_test.rb` draws both and takes screenshots into `BANCO_SHOT_DIR` at 1366 x 900 cream, 1366 x 900 dark and 390 x 844 cream:
`text-english-1366`, `text-english-dark-1366`, `text-english-390` (the card with its speakers, a code span, glossary words and the list "Parole di questa
scheda"), `text-gloss-open-1366` and `-390` (a definition open under its word), `text-listen-1366`, `-dark-1366` and `-390` (the heard check with its text
shown), `text-cloze-390`, `text-chemistry-1366`. The device is a stand-in with the voices of a Mac; the accepted names are put in by the test.

- language span `[[en:..]]`, `[[es:..]]`, `[[la:..]]` (available, T2): the target ink, `lang`, a speaker once a voice is accepted
- role span of a language subject and `[[role|it:..]]` (available, T2)
- code span `[[code:..]]` (available, T2)
- glossary `[[g:term]]` and the list under the card (available, T2)
- mhchem `\ce{}`, `\pu{}` in chemistry and biology (available, T2)
- the card's "Ascolta" and "Più lento", tap to hear, "Prova le voci" on `/settings#voci` (available, T2)
- option `listen` of `choice`, `matching`, `span_select` (available, T2)

## What is read

`test/system/lesson_speech_golden_test.rb` records what the voice would read for every card of the text lessons and of the graph, chart, maps, docs and
computing galleries in `test/fixtures/lesson2/speech/*.json`; the lead reads them, the operator listens to two on the student's device.
