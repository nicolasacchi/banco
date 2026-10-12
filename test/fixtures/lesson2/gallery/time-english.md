---
# Gallery of the family `time` (WAVE2 2.2, T4a), the tense scale of `timeline`, with invented English content: the order of what happens
# around "adesso", with a point, two points, a range up to now, a habit, a plan made before, and a mark that is not certain. The scale of
# years is in time.md. The Spanish marks (text_es) are checked by the vectors. `calendar` (reserved, W2-3) is not drawn yet.
schema: banco.lesson/2
key: ripasso.english.gallery-time
kind: ripasso
subject: english
title_it: "Galleria della linea dei tempi: prima, adesso, dopo"
goals_it:
  - "**Vedere** l'ordine delle azioni: prima, adesso, dopo"
skills: [english.gallery-time]
refs:
  - {source: seconda-2025-26, line: 31, fragment: "i tempi dei verbi", role: needed_by}
  - {source: prima-2025-26, line: 21, fragment: "l'ordine delle azioni", role: taught_in}
scope: studied
minutes: 20
calculator: false
why_it: "I tempi dei verbi sono forme nel tempo. Una linea le fa vedere. Le frasi sono inventate."
---

## Due azioni nel futuro {idea icon=clock id=ordine}

La linea dice che cosa viene prima. Il punto di mezzo è **adesso**.

::: diagram timeline
alt_it: "Una linea dell'ordine: prima, adesso, dopo. Due azioni nel futuro, prima I arrive e poi I'll call you."
scale: tense
window: ['-3', '3']
marks:
  - {id: a, at: '1', span: point, text_en: "I arrive", label_it: "quando?", role: time}
  - {id: b, at: '2', span: point, text_en: "I'll call you", label_it: "che cosa succede", role: main}
states:
  - {op_it: "Una sola azione", marks: [{id: a, at: '1', span: point, text_en: "I arrive", label_it: "quando?", role: time}]}
  - {op_it: "Due azioni nel futuro"}
:::

Ora tocca tu. Guarda dove stanno i segni rispetto ad adesso.

::: check select
prompt_it: "Tocca il segno dell'azione che succede per prima."
targets: marks
pick: one
answer: [a]
explain_it: "Il segno più a sinistra viene prima degli altri."
diagram:
  type: timeline
  alt_it: "Una linea dell'ordine con tre segni da toccare, uno prima di adesso e due dopo."
  scale: tense
  window: ['-3', '3']
  marks:
    - {id: a, at: '-2', span: point, text_en: "I called", label_it: "quando?"}
    - {id: b, at: '1', span: point, text_en: "I arrive", label_it: "quando?"}
    - {id: c, at: '2', span: point, text_en: "I'll call", label_it: "quando?"}
:::

## Quattro forme del tempo {idea icon=hourglass id=forme}

Un punto è un momento. Una barra dura. Una fila di punti è un'abitudine. Un arco è un piano fatto prima.

::: diagram timeline
alt_it: "Una linea dell'ordine con cinque frasi: un punto nel passato, una barra fino ad adesso, una fila di punti, un piano e un punto non certo."
scale: tense
window: ['-4', '4']
marks:
  - {id: p, at: '-2', span: point, text_en: "I called", label_it: "è finito", role: time}
  - {id: r, at: '-2', to: '0', span: range, text_en: "I have lived here", label_it: "arriva a adesso", role: main}
  - {id: h, at: '-3', to: '3', span: habit, text_en: "I always walk", label_it: "di solito", role: auxiliary}
  - {id: l, at: '3', from: '-1', span: plan, text_en: "I'm going to buy it", label_it: "deciso prima", role: time}
  - {id: u, at: '2', span: point, text_en: "I might go", label_it: "non è sicuro", role: main, uncertain: true}
:::
