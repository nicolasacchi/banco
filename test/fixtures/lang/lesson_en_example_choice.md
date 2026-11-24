---
# A bilingual english lesson whose example has a choice step with two quoted options with a word of Italian each (D-402): at 390 px the step is narrow, and the options wrap inside it instead of overflowing. a typed gap there ends in a lone full stop, which stays glued to the box, and the suffixes in the text (-ing, -ed) are never split after their hyphen. test/validation/lesson_render_translation_test.rb draws it in Chrome and expects no finding.
schema: banco.lesson/2
bilingual: true
key: lezione.english.example-choice-fixture
kind: lezione
subject: english
title_en: "Modals: can and should (example choice)"
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

## Choose the word {idea short="Words" short_it="Parole" it="Scegli la parola" icon=hand-helping id=words}

A place where you borrow books is a library, not a bookshop. Add the suffixes -ing and -ed to a verb to get -ing forms.

::: it
Un posto dove si prendono libri in prestito è una library, non una bookshop. Aggiungi i suffissi -ing e -ed a un verbo per avere le forme in -ing.
:::

::: example
problem_en: "Choose the word for a place where you borrow books."
problem_it: "Scegli la parola per un posto dove si prendono libri in prestito."
steps:
  - tag: split
    do_en: "Find the word for the place."
    do_it: "Trova la parola per il posto."
    why_en: "You borrow books there."
    why_it: "Lì si prendono libri in prestito."
    blank:
      component: choice
      prompt_en: "Which word is right?"
      prompt_it: "Quale parola è giusta?"
      translate_material: false
      options:
        - {id: a, text_en: "«[[it:biblioteca]]»"}
        - {id: b, text_en: "«[[it:biblioteche]]»"}
      answer: a
      explain_en: "A library lends books."
      explain_it: "Una biblioteca presta libri."
  - tag: split
    do_en: "Write the answer."
    do_it: "Scrivi la risposta."
    why_en: "The answer is the word you chose."
    why_it: "La risposta è la parola che hai scelto."
result_en: "A library."
result_it: "Una biblioteca."
:::

::: check normalized_text
prompt_en: "Write the word."
prompt_it: "Scrivi la parola."
input_before: "You borrow books from a"
input_after: "."
answer: "library"
explain_en: "A library lends books."
explain_it: "Una biblioteca presta libri."
:::

## Try it {try short="Try it" short_it="Prova tu" it="Prova tu" icon=pencil id=try}

::: try
intro_en: "Choose the right form."
intro_it: "Scegli la forma giusta."
exercises:
  - translate_material: false
    text_en: "You should ___ more water."
    check:
      component: choice
      prompt_en: "Which word fits?"
      prompt_it: "Quale parola va bene?"
      options:
        - {id: a, text_en: "drinks"}
        - {id: b, text_en: "drink"}
      answer: b
    solution_en: "After should the verb has no -s: should drink."
    solution_it: "Dopo should il verbo non prende -s: should drink."
    final_en: "drink"
:::
