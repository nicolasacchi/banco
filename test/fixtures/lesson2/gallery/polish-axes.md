---
# The axis labels of a `cartesian` figure (D-335), invented content: the number under each gridline is centred on it whatever its real width,
# and the label of a tick at the frame's edge ends at the frame instead of straddling it. test/system/lesson_polish_system_test.rb measures
# it in Chrome at 390 and 1280 px: the window ends at 4 on card 1 (the last label sits against the frame) and runs over negative numbers on card 2.
schema: banco.lesson/2
key: ripasso.math.gallery-axes
kind: ripasso
subject: math
title_it: "Galleria delle etichette degli assi"
goals_it:
  - "**Vedere** i numeri sotto le linee"
skills: [math.gallery]
refs:
  - {source: gallery-2026, line: 1, fragment: "assi", role: taught_in}
scope: studied
minutes: 30
calculator: false
why_it: "Una galleria serve a guardare le figure. Il contenuto è inventato."
---

## La finestra finisce a 4 {idea icon=plus id=quattro}

La retta $y = x$ nella finestra da 0 a 4.

::: diagram cartesian
alt_it: "Piano cartesiano da 0 a 4 con la retta y = x che passa per l'origine e per il punto (4, 4)."
x: ['0', '4']
y: ['0', '4']
grid: true
lines:
  - {id: r, eq: 'y = x', label_it: '$y = x$'}
:::

## Numeri negativi {idea icon=multiply id=negativi}

La retta $y = 2x - 4$ nella finestra da $-1$ a $5$.

::: diagram cartesian
alt_it: "Piano cartesiano con la retta y = 2x - 4. Incontra l'asse delle x nel punto (2, 0)."
x: ['-1', '5']
y: ['-5', '5']
grid: true
lines:
  - {id: r, eq: 'y = 2x - 4', label_it: '$y = 2x - 4$'}
points:
  - {x: '2', y: '0', label_it: "x = 2", on_lines: [r]}
:::
