# Frequency lists for W-LANG-LEVEL (D-282)

`en.txt` and `es.txt` hold the 5000 most frequent words of English and Spanish, one per line, most frequent first (the rule
`lesson2.target_vocabulary_top`, 3000, says how many of them count as easy; the rest of the list lets the reviewer move that line without a new
source). They are only looked up by `Lessons::Lexicon` when the lint of a language lesson asks whether a target-language word is "easy" (inside the first
3000 words) or must be taught (`W-LANG-LEVEL`, a warning the reviewer judges). They are never shown to the student.

- **Source:** wordfreq 3.1.1 (Robyn Speer; `large_en` and `large_es`), the words in order of its merged frequency estimate, filtered to
  alphabetic tokens (English keeps one internal apostrophe: `don't`). Words only, no counts.
- **Licence:** wordfreq's code is Apache-2.0; its data files "may be redistributed under a Creative Commons Attribution-ShareAlike 4.0
  licence" (<https://creativecommons.org/licenses/by-sa/4.0/>), and are built from Google Books Ngrams, Wikipedia, Leeds, ParaCrawl, SUBTLEX,
  OpenSubtitles and other sources listed in wordfreq's README. These two files are lists of words derived from that data: treat them as CC BY-SA 4.0,
  attributed to wordfreq (<https://github.com/rspeer/wordfreq>) and its sources. No other file of the repository is derived from them.
- **Changed** only through a D entry, like the vetted data tables.
- **One word is left out** of `en.txt` (position 4704, beyond the 3000 that count): it contains a string that the public-repository hygiene check forbids. A lesson that uses it lists it in `teaches_en`.

# Given names for W-LANG-LEVEL (D-402)

`en_names.txt` and `es_names.txt` hold common given names of English and Spanish, one per line (Spanish with its accents), written for this repository: they are not derived
from the frequency lists and carry no licence of their own beyond the repository's. `Validation::Bilingual.names` reads them (lower case): a name in a sentence of an
exercise or a lesson («Tom plays football», «Lucía come pan») is a name, never a word to teach, so it does not need to sit in `teaches_en` or `teaches_es` and is not a
`W-LANG-LEVEL` warning even at the start of a sentence, where the lint cannot tell it from a word.

- **Only common given names**: the ones a learner meets in a textbook. No surname, no famous person, no name of the student or of his household (the briefs say so; the public-repository hygiene check enforces it).
- **Changed** like the frequency lists, through a D entry.
- **A name that is also an Italian word is not listed** (the Italian text of a lesson is linted with these names, so «Mia», «Rosa», «Sol» and the like stay out).

# Grammar and basic words (D-402)

`en_grammar.txt`, `es_grammar.txt`, `en_basic.txt` and `es_basic.txt` are read, like the lists above, only by `Lessons::Lexicon`; they are never shown to the student. One word per line, UTF-8, lower case (Spanish with its accents), `#` comment lines and blank lines ignored.

- **`{en,es}_grammar.txt`**: the metalanguage a language lesson or item uses to talk about the language in that language (*verb, plural, vowel, tilde, esdrújula, oración*…), with the inflections a lesson uses (number, gender). These words are not a `W-LANG-LEVEL` warning even when they fall outside the first 3000 words.
- **`{en,es}_basic.txt`**: beginner words every A1 learner has by the first lessons (numbers, family, school things, days, months, colours, animals, clothes, classroom verbs) that the first 3000 words of the frequency list lack. Words already inside the first 3000 are not repeated; phrases are listed word by word.
- **Source and licence:** written for this repository, not derived from the frequency lists; no licence of their own beyond the repository's.
- **Changed** only through a D entry, like the other files here.

# School words and irregular forms (D-402, round 7)

`en_school.txt` and `es_school.txt` hold the school words of an A2 learner that the first 3000 words lack (*exam, piano, guitar, calculator; piano, guitarra, horario, recreo*). Like `{en,es}_basic.txt`: one word per line, lower case, `#` comments, read only by `Lessons::Lexicon` (an allowlist, so the word and its inflections are no `W-LANG-LEVEL` warning), written for this repository. The list is short and plain on purpose: a school word that is not obvious goes into `teaches_en` / `teaches_es` of the lesson or the item.

`en_irregular.txt` and `es_irregular.txt` map an irregular form to its verb, one line a verb: `sleep: slept`, `ir: voy vas va ... fui fuiste fue ...` (the preterite, the participle, the irregular present, the forms that the regular endings and the Snowball stem do not reach). A form that belongs to two verbs (*fui*: ir and ser) stands under both. `Lessons::Lexicon.verbs` reads them: an irregular form is known when its verb is one of the easy words (the first 3000, `grammar`, `basic`, `school`) or its stem, and the same holds against `teaches_<lang>`: «slept» is covered by `teaches_en: [sleep]`. The two tables of `config/banco/data/{english,spanish}/verbs` are schemas only for now (no written table, `Lessons::Verbs` is a stub), so these lists are the only irregular forms the level check reads; they are not vetted data, they only say which forms belong to a verb already known.
- **Source and licence:** written for this repository, not derived from the frequency lists; no licence of their own beyond the repository's.
- **Changed** only through a D entry, like the other files here.
