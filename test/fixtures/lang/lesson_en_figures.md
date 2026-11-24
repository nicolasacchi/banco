---
# A bilingual english lesson with the figures of the pilot's English lessons (D-402): a sentence with states (hero and block) with muted parts, word_parts with
# states and the stress legend, a mirror, a flow with labelled edges (`edges_it`), a table figure, a select check on syllables, a normalized_text check and an
# example blank with their input fragments. test/validation/lesson_render_translation_test.rb draws it in Chrome and expects no translation finding.
schema: banco.lesson/2
bilingual: true
key: lezione.english.figures-fixture
kind: lezione
subject: english
title_en: "Questions with have got"
title_it: "Le domande con have got"
goals_en:
  - "**Ask** and answer with have got"
goals_it:
  - "**Chiedere** e rispondere con have got"
skills: [english.modals-can]
refs:
  - {source: gallery-2026, line: 1, fragment: "modals", role: taught_in}
scope: studied
minutes: 30
calculator: false
book_it: "Cerca «have got» sul libro."
why_en: "You talk about what you have every day."
why_it: "Parli di quello che hai ogni giorno."
glossary:
  - {term_en: "syllable", term_it: "sillaba", def_en: "A part of a word you say in one go.", def_it: "Una parte di parola che si dice in una volta sola."}
hero:
  type: sentence
  layout: line
  alt_en: "A question and its answer with have got. The question puts has first."
  alt_it: "Una domanda e la sua risposta con have got. La domanda mette has per primo."
  text_en: "Has she got a dog?"
  parts:
    - {id: a, text_en: "Has", role: highlight, label_en: "Question: has first", label_it: "Domanda: has per primo"}
    - {id: s, text_en: "she", role: subject, label_en: "who", label_it: "chi"}
    - {id: o, text_en: "got a dog?", role: muted, label_en: "full form: has not got", label_it: "forma intera: has not got"}
  states:
    - {op_en: "Question", op_it: "Domanda", next_label_en: "Negative", next_label_it: "Negativa"}
    - text_en: "She hasn't got a fish"
      op_en: "Negative: has plus not"
      op_it: "Negativa: has più not"
      parts:
        - {id: s, text_en: "She", role: subject, label_en: "who", label_it: "chi"}
        - {id: a, text_en: "hasn't", role: highlight, label_en: "short form", label_it: "forma breve"}
        - {id: o, text_en: "got a fish", role: muted, label_en: "football?", label_it: "il calcio?"}
---

## The voice falls on one syllable {idea short="The voice" short_it="La voce" it="La voce batte su una sillaba" icon=volume-2 id=voice}

In English the voice falls harder on one [[g:syllable]]. Count the parts of the word.

::: it
In inglese la voce batte più forte su una [[g:sillaba]]. Conta i pezzi della parola.
:::

::: diagram word_parts
alt_en: "Two words split into syllables. In happy the voice falls on the first, in about on the second."
alt_it: "Due parole divise in sillabe. In happy la voce batte sulla prima, in about sulla seconda."
caption_en: "The strong syllable has a dot."
caption_it: "La sillaba forte ha un punto."
view: syllables
words:
  - form_en: 'hap|py'
    syllables: 'hap-py'
    stress: 1
    label_en: "first"
    label_it: "prima"
  - form_en: 'a|bout'
    syllables: 'a-bout'
    stress: 2
    label_it: "seconda"
states:
  - {op_en: "Two words", op_it: "Due parole"}
  - op_en: "Now a longer word"
    op_it: "Ora una parola più lunga"
    words:
      - form_en: 'ba|na|na'
        syllables: 'ba-na-na'
        stress: 2
        label_en: "the middle one"
        label_it: "quella di mezzo"
      - form_en: 'ap|ple'
        syllables: 'ap-ple'
        stress: 1
        label_en: "the first"
        label_it: "la prima"
:::

::: check select
prompt_en: "Say it aloud: banana. Tap the syllable where the voice falls."
prompt_it: "Dillo a voce alta: banana. Tocca la sillaba dove batte la voce."
targets: syllables
pick: one
answer: [w1s2]
errors:
  - {answer: [w1s3], message_en: "It does not fall on the last one.", message_it: "Non batte sull'ultima."}
explain_en: "Ba-na-na: the voice falls on na, the middle one."
explain_it: "Ba-na-na: la voce batte su na, quella di mezzo."
diagram:
  type: word_parts
  alt_en: "The word banana split into syllables."
  alt_it: "La parola banana divisa in sillabe."
  view: syllables
  words:
    - form_en: 'ba|na|na'
      syllables: 'ba-na-na'
      stress: 2
:::

::: legend
roles:
  - {role: subject, note_en: "Who does it", note_it: "Chi lo fa", question_en: "Who?", question_it: "Chi?"}
  - {role: verb, note_en: "The verb", note_it: "Il verbo"}
:::

## Questions with a blank {idea short="Blanks" short_it="Spazi" it="Domande con uno spazio" icon=message-square id=blanks}

Write the verb in the box.

::: it
Scrivi il verbo nella casella.
:::

::: check normalized_text
prompt_en: "Write the verb: Does the baby cry at night?"
prompt_it: "Scrivi il verbo: il bambino piange di notte?"
input_before: "The baby"
input_after: "(cry) at night."
answer: "cry"
errors:
  - {answer: "cries", message_en: "After does the verb has no -s.", message_it: "Dopo does il verbo non ha -s."}
explain_en: "The baby cries: the verb is in the base form."
explain_it: "Il bambino piange: il verbo è alla forma base."
:::

::: check choice
prompt_en: "Which form completes the sentence?"
prompt_it: "Quale forma completa la frase?"
sentence_en: "My dad ___ a car."
translate_material: false
options:
  - {id: a, text_en: "has got"}
  - {id: b, text_en: "have got"}
answer: a
errors:
  - {answer: b, message_en: "My dad is he: has got.", message_it: "Mio padre è lui: has got."}
explain_en: "My dad is he, so has got."
explain_it: "Mio padre è lui, quindi has got."
:::

::: example
problem_en: "Complete the question about Jack."
problem_it: "Completa la domanda su Jack."
steps:
  - tag: split
    do_en: "Find the subject: Jack."
    do_it: "Trova il soggetto: Jack."
    why_en: "The subject comes after does."
    why_it: "Il soggetto viene dopo does."
    blank:
      component: normalized_text
      prompt_en: "Write the verb."
      prompt_it: "Scrivi il verbo."
      input_before: "Jack"
      input_after: "(study) German."
      answer: "studies"
      explain_en: "Jack studies German."
      explain_it: "Jack studia tedesco."
  - tag: split
    do_en: "Write the whole question."
    do_it: "Scrivi tutta la domanda."
    why_en: "The question is about Jack."
    why_it: "Si parla di Jack e del tedesco."
result_en: "Does Jack study German?"
result_it: "Jack studia tedesco?"
:::

## Mirror and sentences {idea short="Mirror" short_it="Specchio" it="Specchio e frasi" icon=languages id=mirror}

A question starts with has.

::: it
Una domanda comincia con has.
:::

::: diagram mirror
alt_en: "Two sentences, Italian above and English below, piece by piece: the verb has got is two words."
alt_it: "Due frasi, italiano sopra e inglese sotto, pezzo per pezzo: il verbo has got è fatto di due parole."
rows:
  - pieces_it: ['Lui', 'ha', 'un cane']
    pieces_en: ['He', 'has got', 'a dog']
    links: [[0, 0, same], [1, 1, shift], [2, 2, same]]
    notes:
      - {side: en, piece: 1, note_en: "has got: two words", note_it: "has got: due parole"}
  - pieces_it: ['Lei', 'ha', 'un pesce']
    pieces_en: ['She', 'has got', 'a fish']
    links: [[0, 0, same], [1, 1, shift], [2, 2, same]]
    notes:
      - {side: en, piece: 1, note_en: "the same, with she", note_it: "lo stesso, con she"}
:::

::: diagram sentence
alt_en: "Two questions, one about a dog and one about football."
alt_it: "Due domande, una su un cane e una sul calcio."
layout: line
text_en: "Has she got a dog?"
parts:
  - {id: a, text_en: "Has", role: highlight, label_en: "has first", label_it: "has per primo"}
  - {id: s, text_en: "she", role: subject, label_en: "who", label_it: "chi"}
  - {id: o, text_en: "got a dog?", role: muted, label_en: "what", label_it: "che cosa"}
states:
  - {op_en: "Has first", op_it: "Has per primo"}
  - text_en: "Does he play football?"
    op_en: "Question: does first"
    op_it: "Domanda: does per primo"
    parts:
      - {id: a, text_en: "Does", role: highlight, label_en: "does first", label_it: "does per primo"}
      - {id: s, text_en: "he", role: subject, label_en: "who", label_it: "chi"}
      - {id: o, text_en: "play football?", role: muted, label_en: "the verb", label_it: "il verbo"}
:::

## The rule in a diagram {idea short="Diagram" short_it="Schema" it="La regola in uno schema" icon=key-round id=diagram}

::: schema flow
alt_en: "How to ask. Find the verb. If it is have got, put has first. If it is another verb, put does first."
alt_it: "Come si chiede. Cerca il verbo. Se è il verbo avere, il primo posto è di «has». Se è un altro verbo, il primo posto è di «does»."
nodes:
  - {id: s, kind: step, text_en: "Find the verb", text_it: "Trova il verbo"}
  - {id: q, kind: decision, text_en: "Which verb?", text_it: "Quale verbo?"}
  - {id: a, kind: end, text_en: "Has first", text_it: "Has per primo"}
  - {id: b, kind: end, text_en: "Does first", text_it: "Does per primo"}
edges:
  - [s, q]
  - [q, a, "have got"]
  - [q, b, "other verb"]
edges_it:
  - ~
  - "il verbo avere"
  - "altro verbo"
:::

::: schema table
alt_en: "Table of questions: the subject and the form of have got."
alt_it: "Tabella di domande: il soggetto e la forma di have got."
header: ["Subject", "Question"]
header_it: ["Soggetto", "Domanda"]
rows:
  - ["he, she", "Has she got a dog?"]
  - ["you, they", "Have they got a car?"]
rows_it:
  - ["lui, lei", "Ha un cane?"]
  - ["voi, loro", "Hanno una macchina?"]
:::

## Try it {try short="Try" short_it="Prova" it="Prova tu" icon=hand-helping id=try}

::: try
intro_en: "Choose the right form."
intro_it: "Scegli la forma giusta."
exercises:
  - text_en: "My dad ___ a car."
    text_it: "Mio padre ___ una macchina."
    check:
      component: choice
      prompt_en: "Which word fits?"
      prompt_it: "Quale parola va bene?"
      options:
        - {id: a, text_en: "has got", text_it: "ha"}
        - {id: b, text_en: "have got", text_it: "hanno"}
      answer: a
    solution_en: "My dad is he: has got."
    solution_it: "Mio padre è lui: has got."
    final_en: "has got"
    final_it: "ha"
  - text_en: "Write the verb."
    text_it: "Scrivi il verbo."
    check:
      component: normalized_text
      prompt_en: "Write the verb."
      prompt_it: "Scrivi il verbo."
      input_before: "My dad"
      input_after: "a car."
      answer: "has got"
    solution_en: "He has got a car."
    solution_it: "Lui ha una macchina."
    final_en: "has got"
    final_it: "ha"
  - check:
      component: normalized_text
      prompt_en: "Write the missing words."
      prompt_it: "Scrivi le parole che mancano."
      input_before: "My sister"
      input_after: "two dogs."
      answer: "has got"
    solution_en: "She has got two dogs."
    solution_it: "Lei ha due cani."
    final_en: "has got"
    final_it: "ha"
:::
