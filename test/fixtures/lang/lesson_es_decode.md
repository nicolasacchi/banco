---
# A bilingual spanish lesson whose decode word_parts words carry the pieces' Italian gloss (parts_it) with no Spanish twin, the second one with no meaning_it at all (the brief allows it, D-402, round 7): the dry run and the render check agree. test/validation/lesson_render_translation_test.rb draws it in Chrome and expects no translation finding.
schema: banco.lesson/2
bilingual: true
key: lezione.spanish.figures-fixture
kind: lezione
subject: spanish
title_es: "La tilde y las preguntas"
title_it: "La tilde e le domande"
goals_es:
  - "**Encontrar** la sílaba donde suena la voz"
goals_it:
  - "**Trovare** la sillaba dove batte la voce"
skills: [spanish.ser-estar]
refs:
  - {source: gallery-2026, line: 1, fragment: "ser y estar", role: taught_in}
scope: studied
minutes: 30
calculator: false
book_it: "Cerca «acentuación» sul libro."
why_es: "Cada tilde cuenta. Con las preguntas hablas de ti y de otros."
why_it: "Ogni tilde conta. Con le domande parli di te e degli altri."
glossary:
  - {term_es: "sílaba", term_it: "sillaba", def_es: "Un trozo de palabra que se dice de una vez.", def_it: "Un pezzo di parola che si dice in una volta sola."}
---

## Las partes de una palabra {idea short="Partes" short_it="Parti" it="Le parti di una parola" icon=volume-2 id=partes}

Una palabra puede tener dos partes: el prefijo y la base.

::: it
Una parola può avere due parti: il prefisso e la base.
:::

::: diagram word_parts
alt_es: "La palabra deshacer dividida en dos partes: des y hacer."
alt_it: "La parola deshacer divisa in due parti: des e hacer."
view: decode
words:
  - form_es: 'des|hacer'
    parts_it: ["il contrario", "fare"]
    meaning_it: "disfare"
  - form_es: 'des|cubrir'
    parts_it: ["il contrario", "coprire"]
:::

::: check choice
prompt_es: "¿Qué parte lleva el sentido contrario?"
prompt_it: "Quale parte porta il senso contrario?"
translate_material: false
options:
  - {id: a, text_es: "des"}
  - {id: b, text_es: "hacer"}
answer: a
errors:
  - {answer: b, message_es: "Hacer es la base. El sentido contrario viene antes.", message_it: "Hacer è la base. Il senso contrario viene prima."}
explain_es: "El prefijo des cambia el sentido."
explain_it: "Il prefisso des cambia il senso."
:::

## Prueba tú {try short="Prueba" short_it="Prova tu" it="Prova tu" icon=pen-line id=try}

::: try
intro_es: "Elige la forma."
intro_it: "Scegli la forma."
exercises:
  - translate_material: false
    text_es: "Ana ___ la cama."
    check:
      component: choice
      prompt_es: "¿Qué palabra va?"
      prompt_it: "Quale parola va bene?"
      options:
        - {id: a, text_es: "deshace"}
        - {id: b, text_es: "hace"}
      answer: a
    solution_es: "Es el contrario: deshace."
    solution_it: "È il contrario: deshace."
    final_es: "deshace"
:::
