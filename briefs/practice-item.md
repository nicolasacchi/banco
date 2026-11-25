---
name: practice-item
version: 3
formats: banco.item/1
---

# Brief: practice items (version 3)

A practice item is an item of kind `practice_item` (`banco.item/1`, `config/banco/schemas/item.json`).
The student meets it while studying a topic: after a lesson, on one skill, with help on request and an
answer at once. It goes through the same pipeline as a diagnosis item: generator or static instances,
blind verifier, leak scans, expert review (with two more points), blind solve, findings and
responses. Everything in `banco brief show diagnosis-item` applies **unless this brief says
otherwise**: the sources, the component rules, the choice rules, the readability rules, the phrases
never used, the over-absolute rules, the calculating subjects, the supports (`answer_format_it`,
`steps_it`) and the generator and verify contract. Read that brief first.

Start with `banco status` and this brief. Work only through `banco`. Never ask for a decision: you
stop at `awaiting_teacher`.

## What differs from a diagnosis item

- `kind: "practice_item"`. Required: `component`, `prompt`, `error_catalogue`, `tests`, `level`, and
  either `instances` or `generator`. Components: `number`, `fraction`, `expression`, `choice`,
  `ordering`, `matching`, `normalized_text`. No `sub_items`, no `rubric`: practice is closed only.
- `level` (1 to 3): 1 one step or direct; 2 the typical case; 3 combined with prerequisites. A topic
  needs at least one level 1 item per skill.
- `hints_it` (2 to 4 strings, each at most 300 characters; **write 3**) on the item, and optionally
  on an instance (an instance's own hints replace the item's for that instance). Every instance has
  effective hints (`E-HINTS`). Hints are shown one at a time, on request, and counted.
- Hint order: 1 says what to look at or which rule applies; 2 is the first concrete step with this
  instance's numbers; 3 (and 4) is the next step, stopping before the final value.
- A hint never states the key (`E-HINT-KEY`: a string the display-key check would flag, unless it also
  occurs in the display of the same instance; numbers taken from the display are allowed). In a
  `choice` item a hint must not name the key option (`W-HINT-OPTION`); the reviewer judges. Ordering and
  matching have no scan: the reviewer judges.
- Hints obey the readability rules of messages (`E-READ`, `E-PHRASE`): sentences of at most 25 words,
  the second person, kind, no exam-gaming.
- A hint restates the rule and never counts or names the mistakes: on a judge item («which of these are wrong?») «Look at the verb after he/she/it» helps, «Two rows are wrong, and one is the -s» is the answer. The same for the message after a wrong answer, which names the mistake and never the right word.
- Keys that are function words («in, on, at», «es, son, hay»): a hint may use them unless it quotes them, names them as the answer or sets them next to the frame of the key. A clock time such as 8:45 counts as one token in the 12-word cap, and a colon before ¿ or ¡ ends a sentence. This holds for any of the 200 most frequent words of the language (`hace`, `must`, `need`) and for a phrase of up to three such words (`have to`, `hay que`, `going to`): «si hace falta» does not leak the key «hace», «think about have to» does not leak «have to»; «Write have to», «have to» in quotes or next to the frame still do.
- Never «X takes Y» for «with X, use Y» in a hint, a message or a solution («the verb takes -s»; say «after he, she or it, add -s»).
- `diagnosis_item`, `short_answer` and `testlet` items must not carry `level` or `hints_it`.
- A practice item is never pinned by a blueprint (`E-BLUEPRINT-PRACTICE-ITEM`), and a topic pins only
  practice items.
- A typed answer (`normalized_text`) whose words have a common acronym accepts both: the full words and
  the acronym, one as the instance's key and the other in that instance's `accept` (accepted «prodotto
  interno lordo» and «PIL»; an item-level `accept` far from the keys is `W-ACCEPT-ITEM-LEVEL`). Case is
  folded unless the item says `case_sensitive: true`, so «pil» and «Pil» pass too; a dotted form
  («P.I.L.») is another string: add it to `accept` when a student may type it. In the texts, put the
  acronym in parentheses after the words when it matters: «prodotto interno lordo (PIL)» (D-324).
  A text in `accept` is never also the `value` of one of the instance's `errors` (`E-ACCEPT-IS-ERROR`: the grader tries
  `accept` first, so that wrong answer would be marked right).
  A key that is a sentence with a comma or a semicolon needs an `accept` entry with the same sentence without it: the grader compares commas (`W-SENTENCE-COMMA-VARIANTS`, a warning).
- An item of an `extra` topic (outside the programme, D-324) cites the official programme as a
  programme line: `{"kind": "seconda_line", "ref": "ufficiale-2026-27:N", "fragment": "..."}`, checked
  like any programme line (`E-SOURCE`: the line exists, is citable, holds the exact fragment) and shown
  to the reviewer among the programme lines. Do not fall back to `inferred` for it.

## Messages and solutions: what the student reads

- **Right away after a typical error**: the `message_it` of the catalogue entry, at most two sentences:
  the wrong step and the rule that holds; it never gives the key. Then the student gets "Prova
  questo": a new instance in which the same mistake is possible again. So make every catalogue code
  appear in the `errors[]` of several instances: a code carried by fewer than 3 instances is
  `W-PRACTICE-CODE-SPARSE`. Error values must be what a student making that mistake would really
  type; they differ from each other and from the key.
- **An answer no code explains**: the student reads that it matches no mistake we know, and gets hint
  1 and one more try. The second wrong answer shows the solution.
- **After a correct answer**, and on request: the worked `solution` of the instance (`steps` and
  `final`). Each step says what is done and why, in short sentences, and the last step ends at the
  key. A step is correct on its own: the reviewer checks them one by one.
- The solution is shown after the attempt, never before; it may state the key, the hints may not.
- In a `choice`, `matching` or `ordering` item the options, rows and steps are shuffled for every student: a step, final or hint never says «dall'alto», «nell'ordine delle righe», «la prima frase», «l'opzione b» or names `l1`, `r2`, `e3`; name the option by its text (`W-SOLUTION-STORED-ORDER`, a warning). «La prima frase» and «le frasi in alto» are read as the stored order only when the options or elements are themselves sentences; when the options are the words or forms of one sentence, «nella prima frase» is the stem's own and is quiet.
- A formula never ends in a spacing command (`\;`, `\,`, `\quad`) right before a mark: `$C_3H_6$.`, not `$C_3H_6\;$.` (`W-MATH-SPACE-PUNCT`, a warning).

## English and Spanish: written in the language, with the Italian one tap away (D-402)

In `english` and `spanish` the student reads the exercises in the language he is learning and can open the Italian of every text with the
«Traduzione» button. An item of these subjects opts in with `"bilingual": true` (the item's root; a testlet's sub items inherit it). Then **every
student text is written twice**, and both texts are yours to write: never leave one to a machine.

- **Where the two texts go.** The target text is under `<base>_en` (english) or `<base>_es` (spanish), its Italian under `<base>_it`: `prompt.stem_en` +
  `prompt.stem_it`, `answer_format_en|_it`, `steps_en|_it` (lists of the same length), `hints_en|_it` (item and instance), `error_catalogue[].message_en|_it`,
  `display.stem_en|_it`, `solution.steps[].text_en|_it`, `display.figure.alt_en|_it`, `display.table.caption_en|_it`. A few keys have no suffix and
  already hold the target text: an option's, element's or row's `text`, a table's `header` and `rows`, `quote.text`, the solution's `final`; their
  Italian goes beside them as `text_it`, `header_it`, `rows_it` (the same shape), `quote.text_it`, `final_it`. Every option, element and row has its `text_it`
  (a name or a number too: the check says «copy» only when the text has a word of four letters that is not quoted) **unless the item is form material, see below**.
- **Not translated, on purpose.** The key and everything graded (`answer`, `accept`, `errors[].value`, `paradigm_forms`, `tests`), the typed fragments,
  `quote.ref`, and the teacher's own texts: `description_it`, `choice_only_reason_it`, `notes_it`, the rubric's `expected_it`. They stay as they are
  and in Italian. The sentences the practice page writes by itself («Giusto», «Ci sei quasi», «Giuste: N su M») are in the student's interface
  language, not content: do not write them.
- **The target text** (`E-READ`, `W-LANG-LEVEL`, `W-ABSOLUTE`, `E-LESSON-LANG`): sentences of at most **12 words** (a full stop, `?` or `!` ends one, also after a lone letter
  «acaba en n. Lleva» and inside a closing quote `.»` `?»`; a `;` splits), the instruction at most 60; the words of the first 3 000 of the language, plus the grammar words
  (`config/banco/lexicon/{en,es}_grammar.txt`: verb, noun, singular, plural, sílaba, tilde...) and the beginner words (`{en,es}_basic.txt`: thirteen, grandad, pen, lección...);
  any other word the item teaches goes in the item's optional `teaches_en` / `teaches_es` list (**at most 40 words**, each at most 40 characters). Words inside «...» or `[[en:..]]` / `[[es:..]]`, syllable pieces
  (`ja-mon`, `-es`) and form material are not read for the level. A form of a word the item teaches is covered by its stem (`teaches_es: [limpiar]` covers «limpié» and «limpiamos»; the key, the accepted answers and the error values of the item are covered the same way), an irregular form by its verb («slept», «ate», «fui» need nothing: `config/banco/lexicon/{en,es}_irregular.txt`) and the A2 school words (exam, piano, guitar, calculator; piano, guitarra, horario) are in `{en,es}_school.txt`. A quotation in «...», “...” or "..." is not counted in the 12 words either, in the instruction, the hints, the messages, the steps and the solution alike. An absolute word (always, never, nobody; siempre, nunca, nadie) is `W-ABSOLUTE` here too; «only» and «solo» are not one, so «Write only the missing words» is fine.
  No Italian word in a `_en` or `_es` text; to quote one write it inside «...» or `[[it:..]]` (an item's page may print `[[it:..]]` as text, `E-ITEM-RENDER`: prefer «...»).
  English is British by default. Use **common given names** (Tom, Amy, Emma, Jack, Sophie; Lucía, Carlos, Marta, Pablo; the lists are in
  `config/banco/lexicon/{en,es}_names.txt`), never the student's or his household's, and no famous person unless the skill is about him. Invented, plausible contexts.
- **Every target word in Italian text is quoted or a span.** «is, are» bare in an Italian text is refused as not Italian (`E-LANG-TRANSLATION-LANG`): write «is, are» or `[[en:is]]`.
- **The persons rule of a spanish item**, said this way every time: «¿El sujeto es yo y otra persona? Es nosotros. ¿Es tú y otra persona, sin yo? Es vosotros. Yo solo y tú solo no cambian.»
- **The Italian text** is a faithful, plain translation (not a gloss, not a hint), at most 25 words a sentence like every Italian text, and it says what the target says:
  nothing added, nothing dropped, the same level. It must be Italian (`E-LANG-TRANSLATION-LANG`) and written, not copied (`E-LANG-TRANSLATION-COPY`). Two equal target texts are no conflict when their Italian has the same words (a full stop, a capital or markup is not another translation), and a short text made of words that both languages share («La tilde», «Haber cambia con la persona», at most 6 words, no `el`, `los`, `que`, no letter Italian lacks, every word an easy word of the language or in `teaches_en|es`) with the same Italian is no copy.
- **Same shape in both languages** (`E-LANG-PAIR-SHAPE`, `E-LANG-PAIR-MISSING`, `E-LANG-PAIR-ORPHAN`): the same number of `___` blanks, the same formulas
  `$…$` and numbers, the same `**bold**` words, the same paragraphs and list items, and a list as long as its translation.
- **The translation must not give the key away** (`E-SOLUTION-IN-DISPLAY`, `E-SUPPORT-LEAK`, `E-HINT-KEY`, `W-HINT-OPTION`, `W-MESSAGE-GIVES-KEY`, run on the
  target text **and** on the Italian one): the student can always open the Italian. So no «translate this» exercise whose Italian prompt is the exercise, no
  vocabulary matching whose Italian options are the answer, no Italian hint or stem that names the key. A mistake lives in the target text.
- **A reading passage** (`passage_en|_es` + `passage_it`) is a comprehension text: its Italian is shown to the student only **after** he has answered (with the
  solution, or once the exercise is closed), never before, so he cannot answer from the Italian. Write it anyway, complete and faithful. The instruction and the
  question stems keep their Italian as usual.
- **Generators** emit both layers in `display`, `solution` and `hints_*`; `verify.mjs` reads the target text (`instance.display.stem_en`). A static item lists both. **Making an existing generator bilingual changes what `verify.mjs` reads**: `display.stem_it` becomes `display.stem_en` (`stem_es` in spanish), and an author cannot touch `verify.mjs` (`E-VERIFY-AUTHOR`): submit the bilingual generator, then a **verifier session** (`banco work open ITEM --role verifier`) changes `display.stem_it` to `stem_<lang>` in `verify.mjs` and submits it; until then the item is `awaiting_verifier` (`E-VERIFY-STALE`).
- **Stored and served as written.** An item with no `bilingual` flag is validated and served exactly as before, until a new revision opts in. `bilingual` with a
  `_en` text in a revision without the flag, or a `_es` text in english, is `E-LANG-BILINGUAL-FLAG`.

### Contractions (D-398)

The grader reads contractions both ways (D-398): `isn't` and `is not` are the same answer, so a contraction cannot be accepted when its full form is an error value (or the reverse); it is `E-ACCEPT-IS-ERROR`. Declare the contraction in `accept` only when its full form is also right.

### Form material is not translated (`translate_material: false`)

In an exercise that tests a **form** of the language (choose the right form, fill a gap with a form, judge a sentence right or wrong, put forms in order, match a form to its
name) the **material** stays target-only: the instance sentence with its blank (`display.stem_en`), the options, elements or rows that are forms
(`display.options|elements|left|right[].text`) and the `final`. Its Italian would give the key away («Quante/Quanti» → Cuántas/Cuántos; «am/is/are» → «essere»: all the same, or the
answer) or mislead. A form-material instance has no Italian line of its own, so give each instance its task in `display.task_en|es` + `display.task_it` («Make the question.» / «Fai la domanda.»): one short paired instruction, drawn above the sentence, never the key. Say it once, at the item's root: `"translate_material": false` (next to `"bilingual": true`; a testlet's sub items inherit it; without `bilingual` it is
`E-LANG-BILINGUAL-FLAG`). Then:

- no `stem_it` in the instance's `display`, no `text_it` in an option, element or row, no `final_it`; an Italian text beside material is `E-LANG-PAIR-ORPHAN`;
  none is served to the student (the page draws no translation of it) and the solver and the Italian-layer leak scans read none;
- the **instruction** (`prompt.stem_en|_it`, `answer_format_*`, `steps_*`), the **hints**, the **catalogue messages** and the **solution steps** stay paired as always: the
  student can open the Italian of everything he is told about the exercise, never of what he has to work on;
- the material is still linted for the sentence length (12 words) but not for the level or absolute words: a deliberate misspelling (`jámon`, `brujúla`) or a piece of a word is fine there.

When to use it: every item whose options differ only in form (am/is/are, Do/Does, tilde or none, plural endings), every gap or typed answer that is a form, every right/wrong
judge of sentences. Do **not** use it when the text is a plain translation task by nature (vocabulary where the Italian is the point is already forbidden: no «translate this»)
or a reading text (a passage keeps its after-the-answer rule). Without the marker the rule is the old one: every text has its Italian.

- **Matching.** The right-hand labels sit in a drop-down, where their Italian could not be seen; with the marker a form-to-name matching needs no `text_it` on either column.
  The judge rows (`right`/`wrong`, `correct`/`has a mistake`) are the sentences themselves: material, with no Italian that would show the intended meaning.
- **Typed gaps** (`normalized_text`): the sentence with the `___` and the answer are material; put a cue in brackets after the gap, `___ a bike? (you / have got)`; the instruction
  and the hints carry the Italian. One blank per instance line (`W-LANG-FRAME-BLANK`), and a gap that stands for an auxiliary is a gap like any other.
- **The `work` folder.** `banco work open ITEM` writes the latest revision into `item.json` and **overwrites** the file in the folder: a rewrite script that edits `item.json` must
  run after `work open`, never before, and keep its own copy of anything it has not submitted.

## Pools

- A generated item keeps `generator.pool` of 24 clean seeds; a static practice item has at least 10
  instances (`E-PRACTICE-POOL`). Instances must differ in display and fingerprint.
- Instances of one item must look different to the student: different cases or rows, not the same rows reshuffled (`W-INSTANCES-ALIKE`).
- A `matching` with 2 categories (a right/wrong judge) has at least 2 rows of each category in every instance (`W-MATCHING-JUDGE-ROWS`).
- A classification (`reuse_right: true`) has fewer chips than rows, **or as many when one chip is never a right answer** (a distractor, «why» among «because, so, but»): four rows and four chips with one unused chip need no fifth row (`E-MATCHING-SIZE`).
- A `matching` has at most 4 rows (a right/wrong judge, two labels, at most 5: 3 + 2 lets the split vary): more rows are `W-MATCHING-ROWS` (a warning), 7 or more `E-MATCHING-ROWS` (an error in a new submission); from 4 rows it is already hard to guess and more rows only use up his tries, so split a longer list into two items. A right/wrong judge has 4 or 5 rows here (at least 4: `E-MATCHING-SIZE`; at least 2 of each option: `W-MATCHING-JUDGE-ROWS`; 5 rows are not warned).
- Per skill a topic needs at least 20 distinct instances over its 2 to 4 pinned items, 12 of them hard
  to guess (written answers, an ordering or matching of 4 or more): plan the items so that the pool
  reaches that. Write the first, level 1, item first. An `extra` topic (outside the programme, D-324:
  optional exercises) needs 10 distinct instances per skill, 6 of them hard to guess.
- Do not copy the lesson's exercises or worked examples (`W-TOPIC-INSTANCE-IN-LESSON`) and do not reuse
  the instances of the diagnosis items of the skill (`W-PRACTICE-DIAGNOSIS-OVERLAP`).

## Reviewers and solvers

A reviewer checks 13 points: the 11 of the review brief, plus 12 (hints: 2 to 4 per instance, from the
rule to the next step; none states the key; the last stops before the final value) and 13 (messages
and solution: each typical-error message names the mistake and the rule without the key; each
solution step is correct, says why, and ends at the key). A review of a practice item with another
number of points is `E-REVIEW-CHECKLIST`. The blind solver sees what the student sees before asking
for help: prompt and display, never hints, messages or solutions. Findings are answered with
`banco findings respond`, exactly as for diagnosis items.

## The cycle

`banco work open ITEM`, edit, `banco work submit DIR --dry-run`, `banco work submit DIR`,
`banco work status REV --wait`: the same as for diagnosis items (new generators wait for a verifier). A validation that failed with `E-GEN-TIMEOUT` and `timeout_only` is the server's time limit, not your generator: the server queues it again by itself; ask at once with `banco work retry REV` (also for a revision that stays `validating` after a restart).
`banco items list --subject KEY --kind practice --current` lists the practice items only. The teacher
can send an item back ("Rimanda"); read `teacher_comments` before you edit. When the items of a skill
have passed, been reviewed and been solved blind, the topic file pins them (`banco brief show topic`).

## Public repository

The code and these briefs are public. Items live in the database, but anything you write into a file
or a report the repository can see is public. No name of the student or of the household, no school,
no city, no exam-session details, no programme text. Say "the student" and "the teacher".

The direction of an accent (è/é, à/á…) is never tested and never makes an answer wrong (D-296); a missing accent and an apostrophe for an accent still count.
