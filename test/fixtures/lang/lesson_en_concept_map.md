---
# A bilingual english lesson with a concept_map of verb forms (D-402, round 6): `translate_material: false`, the nodes are forms with no Italian. test/validation/lesson_render_translation_test.rb draws it in Chrome and expects no translation finding.
schema: banco.lesson/2
bilingual: true
key: lezione.english.concept-map-fixture
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

## The forms of a verb {idea short="Forms" short_it="Forme" it="Le forme di un verbo" icon=hand-helping id=forms}

A verb has a base and other forms.

::: it
Un verbo ha una base e altre forme.
:::

::: schema concept_map
alt_en: "A map of the verb play with three forms: play, plays and played."
alt_it: "Una mappa del verbo play con tre forme: play, plays e played."
translate_material: false
root: r
nodes:
  - {id: r, text_en: "play"}
  - {id: a, text_en: "plays"}
  - {id: b, text_en: "played"}
edges:
  - {from: r, to: a, label_en: "he, she", label_it: "lui, lei"}
  - {from: r, to: b, label_en: "past", label_it: "passato"}
:::

::: check choice
prompt_en: "Which form shows the past?"
prompt_it: "Quale forma mostra il passato?"
translate_material: false
options:
  - {id: a, text_en: "play"}
  - {id: b, text_en: "played"}
answer: b
errors:
  - {answer: a, message_en: "Play is the base form.", message_it: "Play è la forma base."}
explain_en: "Played is the past form."
explain_it: "Played è la forma del passato."
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
