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
