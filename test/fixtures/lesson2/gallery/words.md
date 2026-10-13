---
# Gallery of the family `words` (WAVE2 2.6, T3), a lesson/2 file with invented content in the spanish subject. It shows `word_parts` (decode with
# one, two and three words; syllables with the Spanish word engine, a form with attached pieces and its states, a stem change with an arrow, a
# Latin and an Italian word), `mirror` (the pronouns with a role, a false friend, a row where the sameness is the point, two rows with pieces
# that have no pair) and `dialogue` (a transcript with its glosses). `paradigm` (draft, W2-2) is not drawn yet. The English half is
# words-english.md. test/validation/lesson_words_gallery_test.rb renders both with Chrome at the viewports of lesson2.render and keeps no
# finding at all; test/system/lesson_words_gallery_test.rb looks at them (BANCO_SHOT_DIR keeps the shots for the look gate).
schema: banco.lesson/2
key: ripasso.spanish.gallery-words
kind: ripasso
subject: spanish
title_it: "Galleria delle parole e delle lingue"
goals_it:
  - "**Vedere** ogni figura della famiglia"
skills: [spanish.gallery]
refs:
  - {source: gallery-2026, line: 1, fragment: "parole", role: taught_in}
scope: studied
minutes: 30
calculator: false
why_it: "Una galleria serve a guardare le figure. Il contenuto è inventato."
---

## Una parola ha dei pezzi {idea icon=puzzle id=pezzi}

Una parola lunga si capisce a pezzi. Ogni pezzo ha un significato.

::: diagram word_parts
alt_it: "La parola descubrir in due pezzi: des vuol dire togliere e cubrir vuol dire coprire. Insieme: scoprire."
view: decode
words:
  - form_es: 'des|cubrir'
    parts_it: ["togliere", "coprire"]
    meaning_it: "scoprire, togliere la copertura"
:::

## Tre pezzi, due parole {idea icon=puzzle id=pezzi-tre}

::: diagram word_parts
alt_it: "Due parole fatte di pezzi: micro, bio e logia in biologia piccola, e pro e cariote in procariote. Ogni pezzo vuol dire qualcosa."
view: decode
words:
  - form_it: 'micro|bio|logia'
    parts_it: ["piccolo", "vita", "studio"]
    meaning_it: "lo studio dei viventi piccolissimi"
    label_it: "tre pezzi"
  - form_it: 'pro|cariote'
    parts_it: ["prima", "nucleo"]
    meaning_it: "prima del nucleo"
    label_it: "due pezzi"
arrows:
  - {from: 0, to: 1, label_it: "un altro esempio"}
:::

## Dove batte la voce {idea icon=volume-2 id=voce}

La sillaba forte è più alta e ha un punto sopra.

::: diagram word_parts
alt_it: "Le parole queremos e canción divise in sillabe: que, re, mos e can, ción. La voce batte su re in queremos e su ción in canción."
view: syllables
words:
  - form_es: 'queremos'
    label_it: "voi volete"
  - form_es: 'canción'
    label_it: "una canzone"
:::

## Con il pronome attaccato {idea icon=scissors id=attaccato}

::: diagram word_parts
alt_it: "Dar con lo fa darlo, dar con se e lo fa dárselo. La voce resta sulla stessa sillaba e la tilde la segue."
view: syllables
words:
  - form_es: 'dar+lo'
    label_it: "un pronome"
  - form_es: 'dár+se+lo'
    label_it: "due pronomi"
arrows:
  - {from: 0, to: 1, label_it: "con se"}
:::

## Un verbo che cambia {idea icon=replace id=cambia}

::: diagram word_parts
alt_it: "Il verbo poder: puedo e podemos. La radice cambia quando la voce batte sulla radice, e non cambia quando batte sulla desinenza."
view: syllables
words:
  - form_es: 'p[ue]d|o'
    label_it: "yo"
  - form_es: 'pod|emos'
    label_it: "nosotros"
arrows:
  - {from: 0, to: 1, label_it: "cambia persona"}
states:
  - {}
  - {op_it: "Ora guarda la voce"}
:::

## Una parola passo dopo passo {idea icon=footprints id=passi}

::: diagram word_parts
alt_it: "La parola explicar e poi explicárselo. La voce resta su car e la tilde appare quando si attaccano se e lo."
view: syllables
words:
  - form_es: 'explicar'
states:
  - {}
  - {words: [{form_es: 'explicar+se'}], op_it: "Con se"}
  - {words: [{form_es: 'explicár+se+lo'}], op_it: "Con se e lo"}
:::

## Altre lingue, altri pezzi {idea icon=languages id=altre}

::: diagram word_parts
alt_it: "Una parola spagnola e una italiana divise in sillabe: nú, cle, o e mi, cro, sco, pio. La voce batte su nú e su sco."
view: syllables
words:
  - form_es: 'núcleo'
    syllables: 'nú-cle-o'
    stress: 1
    label_it: "spagnolo"
  - form_it: 'micro|scopio'
    syllables: 'mi-cro-sco-pio'
    stress: 3
    label_it: "italiano"
:::

## Italiano e spagnolo, pezzo per pezzo {idea icon=arrow-left-right id=specchio}

::: diagram mirror
alt_it: "La frase italiana glielo do sopra la spagnola se lo doy, pezzo per pezzo: in spagnolo sono tre parole separate, in italiano due."
rows:
  - pieces_it: ['Glie+lo', 'do']
    pieces_es: ['Se', 'lo', 'doy']
    links: [[0, 0, shift], [0, 1, same], [1, 2, same]]
    notes:
      - {side: es, piece: 0, note_it: "due parole, non una"}
    roles:
      - {side: es, piece: 0, role: oi}
      - {side: es, piece: 1, role: od}
      - {side: es, piece: 2, role: verb}
:::

## Un falso amico {idea icon=languages id=falso-amico}

::: diagram mirror
alt_it: "Sono costipato e estoy constipado si somigliano, ma constipado vuol dire raffreddato. Il secondo pezzo è un falso amico."
rows:
  - pieces_it: ['Sono', 'costipato']
    pieces_es: ['Estoy', 'constipado']
    links: [[0, 0, shift], [1, 1, false_friend]]
    notes:
      - {side: es, piece: 0, note_it: "per come stai si usa estar"}
      - {side: es, piece: 1, note_it: "vuol dire raffreddato"}
:::

## Quando l'uguale è il punto {idea icon=arrow-left-right id=uguale}

::: diagram mirror
alt_it: "Io parlo e yo hablo: i pezzi corrispondono uno a uno, nello stesso ordine. Qui l'ordine è uguale."
same_ok: true
rows:
  - pieces_it: ['Io', 'parlo']
    pieces_es: ['Yo', 'hablo']
    links: [[0, 0, same], [1, 1, same]]
:::

## Due coppie con pezzi senza compagno {idea icon=arrow-left-right id=coppie}

::: diagram mirror
alt_it: "Due coppie di frasi. Glielo do diventa se lo doy. Mi piace diventa me gusta, e in spagnolo si può aggiungere el libro."
rows:
  - pieces_it: ['Glie+lo', 'do']
    pieces_es: ['Se', 'lo', 'doy']
    links: [[0, 0, shift], [0, 1, same], [1, 2, same]]
    notes:
      - {side: es, piece: 0, note_it: "due parole, non una"}
  - pieces_it: ['Mi', 'piace']
    pieces_es: ['Me', 'gusta', 'el', 'libro']
    links: [[0, 0, same], [1, 1, shift]]
    notes:
      - {side: es, piece: 1, note_it: "la cosa che piace è il soggetto"}
      - {side: es, piece: 2, note_it: "qui c'è l'articolo"}
      - {side: es, piece: 3, note_it: "il libro, il soggetto"}
:::

## Ascolta due amici {idea icon=message-circle id=dialogo}

::: dialogue
title_it: "Ascolta Ana e Luis"
speakers:
  - {id: a, name: "Ana", voice: 1}
  - {id: l, name: "Luis", voice: 2}
transcript: shown
lines:
  - {speaker: a, text_es: "¿Me das el libro, por favor?", gloss_it: "Mi dai il libro, per favore?"}
  - {speaker: l, text_es: "Sí, te lo doy ahora.", gloss_it: "Sì, te lo do adesso."}
  - {speaker: a, text_es: "Gracias. ¿Y el cuaderno?", gloss_it: "Grazie. E il quaderno?"}
  - {speaker: l, text_es: "El cuaderno se lo di a Marta.", gloss_it: "Il quaderno l'ho dato a Marta."}
:::

## Tocca la sillaba forte {idea icon=volume-2 id=tocca-sillaba}

::: check select
prompt_it: "Tocca la sillaba dove batte la voce."
targets: syllables
pick: one
answer: [w1s2]
errors:
  - {answer: [w1s1], code: es_stress_first, message_it: "In queremos la voce non batte sulla prima sillaba."}
explain_it: "In queremos la voce batte su re."
diagram:
  type: word_parts
  alt_it: "La parola queremos divisa in sillabe, una accanto all'altra."
  view: syllables
  words:
    - {form_es: 'queremos'}
:::

## Tocca il pezzo che cambia {idea icon=arrow-left-right id=tocca-pezzo}

::: check select
prompt_it: "Tocca il pezzo spagnolo che sta al posto di glie."
targets: pieces
pick: one
answer: [r1t1]
explain_it: "Glie diventa se, e in spagnolo è una parola da sola."
diagram:
  type: mirror
  alt_it: "Una frase italiana sopra la stessa frase in spagnolo, divise in pezzi."
  rows:
    - pieces_it: ['Glie+lo', 'do']
      pieces_es: ['Se', 'lo', 'doy']
      links: [[0, 0, shift], [0, 1, same], [1, 2, same]]
      notes:
        - {side: es, piece: 0, note_it: "due parole, non una"}
:::
