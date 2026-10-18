---
# The renderer problems the Spanish author reported in wave 3 (D-310), one card each, invented content: markup in the header cells of a
# `table` (also when the rows stack at 390 px) and a long caption, markup in the titles of `cases`, a `mirror` whose pieces carry an icon
# role, markup in the options of a `choice` check, an `ordering` check with long sentences, a `tiles` check that orders facts, and mistakes
# whose group title holds a word of Spanish.
# test/validation/lesson_polish_gallery_test.rb draws it in Chrome at the viewports of lesson2.render and keeps no finding at all.
schema: banco.lesson/2
key: ripasso.spanish.gallery-polish
kind: ripasso
subject: spanish
title_it: "Galleria delle correzioni del disegno"
goals_it:
  - "**Vedere** i pezzi corretti"
skills: [spanish.gallery]
refs:
  - {source: gallery-2026, line: 1, fragment: "parole", role: taught_in}
scope: studied
minutes: 30
calculator: false
why_it: "Una galleria serve a guardare le figure. Il contenuto è inventato."
---

## Tre verbi, tre desinenze {idea icon=layout-grid id=tabella}

Le tre coniugazioni hanno desinenze diverse.

::: table
caption_it: "Il presente dei verbi regolari: la persona io e la persona noi delle tre coniugazioni"
header: ["Persona", "[[es:hablar]]", "[[es:comer]]", "[[es:vivir]]"]
rows:
  - ["io", "[[es:hablo]]", "[[es:como]]", "[[es:vivo]]"]
  - ["noi", "[[es:hablamos]]", "[[es:comemos]]", "[[es:vivimos]]"]
:::

## Tre coniugazioni {idea icon=puzzle id=casi}

::: cases "Le desinenze di [[es:hablar]], [[es:comer]] e [[es:vivir]]"
cases:
  - title_it: "Con [[es:hablar]] la persona noi ha sempre la stessa desinenza"
    text_it: "Con noi la desinenza è [[es:-amos]]."
    example_it: "[[es:hablamos]]"
  - title_it: "-er: [[es:comer]]"
    text_it: "Con noi la desinenza è [[es:-emos]]."
    example_it: "[[es:comemos]]"
  - title_it: "-ir: [[es:vivir]]"
    text_it: "Con noi la desinenza è [[es:-imos]]."
    example_it: "[[es:vivimos]]"
:::

## Il verbo riflessivo {idea icon=arrow-left-right id=specchio}

Il pronome riflessivo va prima del verbo, come in italiano.

::: diagram mirror
alt_it: "La frase italiana ci laviamo le mani sopra la spagnola nos lavamos las manos: i verbi si corrispondono, l'articolo cambia."
rows:
  - pieces_it: ['Ci', 'laviamo', 'le mani']
    pieces_es: ['Nos', 'lavamos', 'las manos']
    links: [[0, 0, same], [1, 1, same], [2, 2, shift]]
    notes:
      - {side: es, piece: 2, note_it: "l'articolo è las"}
    roles:
      - {side: it, piece: 1, role: verb}
      - {side: es, piece: 1, role: verb}
:::

::: check choice
prompt_it: "Come si dice «noi viviamo»?"
options:
  - {id: a, text_it: "[[es:vivemos]]"}
  - {id: b, text_it: "[[es:vivimos]]"}
  - {id: c, text_it: "**[[es:viven]]**"}
answer: b
errors:
  - {answer: a, code: es_vowel, message_it: "Con noi i verbi in -ir hanno la i."}
explain_it: "[[es:vivir]] fa [[es:vivimos]]."
:::

## Una giornata in ordine {idea icon=list-ordered id=ordine}

Le azioni di una giornata hanno un ordine.

::: check ordering
prompt_it: "Metti in ordine la mattina di Lucía."
items:
  - {id: a, text_it: "[[es:Lucía se despierta a las siete y media de la mañana.]]"}
  - {id: b, text_it: "[[es:Después se ducha y se viste para ir al instituto.]]"}
  - {id: c, text_it: "[[es:Desayuna un café con leche y unas tostadas.]]"}
  - {id: d, text_it: "[[es:Finalmente sale de casa con su hermano pequeño.]]"}
answer: [a, b, c, d]
errors:
  - {answer: [a, c, b, d], message_it: "Prima si lava e si veste, poi fa colazione."}
explain_it: "Si sveglia, si lava, fa colazione, esce."
:::

## I fatti in fila {idea icon=list-ordered id=fatti}

Una storia racconta i fatti in ordine di tempo.

::: check tiles
prompt_it: "Metti i fatti in ordine di tempo. Un fatto non serve."
tiles:
  - {id: a, text_it: "Lucía impara lo spagnolo a scuola."}
  - {id: b, text_it: "Va in Spagna per un mese."}
  - {id: c, text_it: "Scrive una lettera alla famiglia che la ospita."}
  - {id: d, text_it: "Lucía nasce a Madrid."}
answer: [a, c, b]
errors:
  - {answer: [a, b, c], message_it: "La lettera parte prima del viaggio."}
explain_it: "Prima impara, poi scrive alla famiglia, poi parte."
:::

::: check tiles
prompt_it: "Costruisci la frase «io mi lavo»."
builds: sentence
tiles:
  - {id: a, text_es: "Yo"}
  - {id: b, text_es: "me"}
  - {id: c, text_es: "lavo"}
  - {id: d, text_es: "te"}
answer: [a, b, c]
explain_it: "[[es:Yo me lavo.]]"
:::

## Errori da evitare {mistakes}

::: mistake
group_it: "La persona noi di [[es:vivir]]"
wrong_it: "[[es:Nosotros vivemos en Madrid.]]"
right_it: "[[es:Nosotros vivimos en Madrid.]]"
why_it: "I verbi in -ir hanno la i: [[es:vivimos]]."
code: es_ir_vowel
:::

::: mistake
group_it: "La persona noi di [[es:vivir]]"
wrong_it: "[[es:Nosotros vivamos aquí.]]"
right_it: "[[es:Nosotros vivimos aquí.]]"
why_it: "Con noi il presente di [[es:vivir]] è [[es:vivimos]]."
code: es_ir_ending
:::
