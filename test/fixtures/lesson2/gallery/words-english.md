---
# Gallery of the family `words`, the English half (WAVE2 2.6, T3), a lesson/2 file with invented content in the english subject: `word_parts`
# with syllables written by the author (the English engine is not built: the author gives the syllables and the stress), `mirror` with the
# English side, `dialogue` with English lines and a transcript that starts hidden. See words.md for the rest of the family.
schema: banco.lesson/2
key: ripasso.english.gallery-words
kind: ripasso
subject: english
title_it: "Galleria delle parole e delle lingue, in inglese"
goals_it:
  - "**Vedere** ogni figura della famiglia"
skills: [english.gallery]
refs:
  - {source: gallery-2026, line: 1, fragment: "words", role: taught_in}
scope: studied
minutes: 30
calculator: false
why_it: "Una galleria serve a guardare le figure. Il contenuto è inventato."
---

## Dove batte la voce {idea icon=volume-2 id=voce}

::: diagram word_parts
alt_it: "Le parole happy e about divise in sillabe. In happy la voce batte sulla prima sillaba, in about sulla seconda."
view: syllables
words:
  - form_en: 'hap|py'
    syllables: 'hap-py'
    stress: 1
    label_it: "felice"
  - form_en: 'a|bout'
    syllables: 'a-bout'
    stress: 2
    label_it: "circa"
:::

## Italiano e inglese, pezzo per pezzo {idea icon=equal id=specchio}

::: diagram mirror
alt_it: "Chiamerò Marco quando arrivo, e sotto la frase inglese: I will call Marco when I arrive. Dopo when l'inglese usa il presente."
rows:
  - pieces_it: ['Chiamerò', 'Marco', 'quando', 'arrivo']
    pieces_en: ['I will call', 'Marco', 'when', 'I arrive']
    links: [[0, 0, shift], [1, 1, same], [2, 2, same], [3, 3, shift]]
    notes:
      - {side: en, piece: 0, note_it: "will, poi il verbo"}
      - {side: en, piece: 3, note_it: "dopo when il presente, non il futuro"}
:::

## Ascolta due amici {idea icon=message-square id=dialogo}

::: dialogue
title_it: "Ascolta Tom e Amy"
speakers:
  - {id: t, name: "Tom", voice: 1}
  - {id: a, name: "Amy", voice: 2}
transcript: hidden
lines:
  - {speaker: t, text_en: "Are you coming to the lake on Saturday?", gloss_it: "Vieni al lago sabato?"}
  - {speaker: a, text_en: "Yes, if it doesn't rain.", gloss_it: "Sì, se non piove."}
  - {speaker: t, text_en: "I will call you when I arrive.", gloss_it: "Ti chiamo quando arrivo."}
:::
