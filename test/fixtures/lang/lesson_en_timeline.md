---
# A bilingual english lesson with a tense timeline in the cover, in a diagram block and in a case (D-402, tooling round 4): a mark's `text_en` is the figure's own
# target text (no `text_it`), its `label_en` / `label_it` are a pair like any label.
schema: banco.lesson/2
bilingual: true
key: lezione.english.timeline-fixture
kind: lezione
subject: english
title_en: "When things happen"
title_it: "Quando succedono le cose"
goals_en:
  - "**Put** two actions in order"
goals_it:
  - "**Mettere** due azioni in ordine"
skills: [english.modals-can]
refs:
  - {source: gallery-2026, line: 1, fragment: "modals", role: taught_in}
scope: studied
minutes: 30
calculator: false
teaches_en: [arrive, tap]
book_it: "Cerca «i tempi» sul libro."
why_en: "You tell what happened first every day."
why_it: "Dici che cosa è successo prima ogni giorno."
hero:
  type: timeline
  alt_en: "A line of order with before, now and after. Two actions come after now."
  alt_it: "Una linea dell'ordine con prima, adesso e dopo. Due azioni vengono dopo adesso."
  scale: tense
  window: ['-3', '3']
  marks:
    - {id: a, at: '1', span: point, text_en: "I arrive", label_en: "when?", label_it: "quando?", role: time}
    - {id: b, at: '2', span: point, text_en: "I will call you", label_en: "what happens", label_it: "che cosa succede", role: main}
---

## Two actions {idea short="Two actions" short_it="Due azioni" it="Due azioni" icon=clock id=two}

The action in the first place comes first.

::: it
L'azione al primo posto viene prima.
:::

::: diagram timeline
alt_en: "A line of order with one past action and two actions after now."
alt_it: "Una linea dell'ordine con un'azione passata e due azioni dopo adesso."
scale: tense
window: ['-3', '3']
marks:
  - {id: a, at: '-2', span: point, text_en: "I called", label_en: "when?", label_it: "quando?"}
  - {id: b, at: '1', to: '3', span: range, text_en: "I will be here", label_en: "how long?", label_it: "per quanto tempo?"}
states:
  - {op_en: "One action", op_it: "Una azione", marks: [{id: a, at: '-2', span: point, text_en: "I called", label_en: "when?", label_it: "quando?"}]}
  - {op_en: "Two actions", op_it: "Due azioni"}
:::

::: cases "Three kinds" it="Tre tipi"
cases:
  - title_en: "A point"
    title_it: "Un punto"
    text_en: "One moment."
    text_it: "Un momento."
    diagram:
      type: timeline
      alt_en: "A line of order with one point before now."
      alt_it: "Una linea dell'ordine con un punto prima di adesso."
      scale: tense
      window: ['-3', '3']
      marks:
        - {id: a, at: '-2', span: point, text_en: "I called", label_en: "when?", label_it: "quando?"}
  - title_en: "A habit"
    title_it: "Un'abitudine"
    text_en: "Many moments."
    text_it: "Tanti momenti."
:::

::: check select
prompt_en: "Tap the action that happens first."
prompt_it: "Tocca l'azione che succede per prima."
targets: marks
pick: one
answer: [a]
explain_en: "The left mark comes first."
explain_it: "Il segno a sinistra viene prima."
diagram:
  type: timeline
  alt_en: "A line of order with two marks to tap."
  alt_it: "Una linea dell'ordine con due segni da toccare."
  scale: tense
  window: ['-3', '3']
  marks:
    - {id: a, at: '-2', span: point, text_en: "I called", label_en: "when?", label_it: "quando?"}
    - {id: b, at: '1', span: point, text_en: "I arrive", label_en: "when?", label_it: "quando?"}
    - {id: c, at: '2', span: point, text_en: "I will call", label_en: "when?", label_it: "quando?"}
:::
