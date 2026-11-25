---
# A bilingual english lesson with a word_parts figure in the decode view (D-402, round 6): the pieces and the meaning have only their Italian gloss (parts_it, meaning_it), drawn as Italian. test/validation/lesson_render_translation_test.rb draws it in Chrome and expects no translation finding.
schema: banco.lesson/2
bilingual: true
key: lezione.english.decode-fixture
kind: lezione
subject: english
title_en: "Modals: can and should"
title_it: "I modali: can e should"
goals_en:
  - "**Use** can and should with the base verb"
goals_it:
  - "**Usare** can e should con il verbo base"
skills: [english.modals-can]
refs:
  - {source: gallery-2026, line: 1, fragment: "modals", role: taught_in}
scope: studied
minutes: 30
calculator: false
book_it: "Cerca «verbi modali» sul libro."
why_en: "Modal verbs help you ask, offer and say what is possible. You need them every day."
why_it: "I verbi modali servono a chiedere, offrire e dire che cosa è possibile. Ti servono ogni giorno."
glossary:
  - {term_en: "modal verb", term_it: "verbo modale", def_en: "A verb that helps another verb.", def_it: "Un verbo che aiuta un altro verbo."}
---

## Pieces of a word {idea short="Pieces" short_it="Pezzi" it="I pezzi di una parola" icon=hand-helping id=pieces}

A word can have two pieces: the base and an ending.

::: it
Una parola può avere due pezzi: la base e una desinenza.
:::

::: diagram word_parts
alt_en: "The word played split into two pieces: play and ed."
alt_it: "La parola played divisa in due pezzi: play e ed."
view: decode
words:
  - form_en: 'play|ed'
    parts_it: ["giocare", "passato"]
    meaning_it: "giocò, ha giocato"
:::

::: check choice
prompt_en: "Which piece shows the past?"
prompt_it: "Quale pezzo mostra il passato?"
translate_material: false
options:
  - {id: a, text_en: "play"}
  - {id: b, text_en: "ed"}
answer: b
errors:
  - {answer: a, message_en: "Play is the base. The past is in the ending.", message_it: "Play è la base. Il passato è nella desinenza."}
explain_en: "The ending ed shows the past."
explain_it: "La desinenza ed mostra il passato."
:::

## Try it {try short="Try it" short_it="Prova tu" it="Prova tu" icon=pencil id=try}

::: try
intro_en: "Choose the right form."
intro_it: "Scegli la forma giusta."
exercises:
  - translate_material: false
    text_en: "Yesterday I ___ football."
    check:
      component: choice
      prompt_en: "Which word fits?"
      prompt_it: "Quale parola va bene?"
      options:
        - {id: a, text_en: "play"}
        - {id: b, text_en: "played"}
      answer: b
    solution_en: "Yesterday is past: played."
    solution_it: "Yesterday è passato: played."
    final_en: "played"
:::
