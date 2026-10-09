---
schema: banco.lesson/2
key: ripasso.math.demo-equations
kind: ripasso
subject: math
title_it: "Equazioni di primo grado: risolvere e verificare"
goals_it:
  - "**Risolvere** un'equazione di primo grado intera"
  - "**Verificare** il risultato nell'equazione di partenza"
skills: [math.demo-equation]
uses: [math.demo-signed-numbers]
refs:
  - {source: seconda-2025-26, line: 12, fragment: "equazioni di primo grado numeriche", role: needed_by}
  - {source: prima-2025-26, line: 7, fragment: "equazioni di primo grado", role: taught_in}
scope: studied
minutes: 30
calculator: false
why_it: "Molti argomenti di quest'anno finiscono con un'equazione come $ax = b$. Se la sai risolvere, il resto è più semplice."
---

## Un'equazione è una bilancia {idea icon=scale id=bilancia}

[[subject:I due membri]] sono i due piatti. Una **soluzione** è il numero che, al posto di $\role{unknown}{x}$, tiene i piatti in equilibrio.

::: diagram balance
alt_it: "Bilancia: a sinistra due scatole x e tre pesi da 1, a destra sette pesi da 1. Puoi provare un numero nella scatola."
left: {x: 2, units: 3}
right: {units: 7}
x_value: '2'
try: {from: 0, to: 5}
:::

::: check choice
prompt_it: 'Quale numero tiene in equilibrio la bilancia $2x + 3 = 7$?'
options:
  - {id: a, text_it: '$x = 5$'}
  - {id: b, text_it: '$x = 2$'}
  - {id: c, text_it: '$x = 4$'}
answer: b
errors:
  - {answer: a, code: math_eval_wrong, message_it: 'Con $x = 5$ il primo membro vale 13, non 7.'}
explain_it: 'Con $x = 2$: $2 \cdot 2 + 3 = 7$. I piatti sono uguali.'
:::

## Togli lo stesso peso dai due piatti {idea icon=scale}

::: callout rule "Primo principio"
Puoi aggiungere o togliere lo stesso termine ai due membri.
:::

::: diagram balance
alt_it: "Dalla bilancia 2x + 3 = 7 si tolgono tre pesi da ogni piatto: resta 2x = 4."
x_value: '2'
states:
  - {left: {x: 2, units: 3}, right: {units: 7}, op_it: "Partenza"}
  - {left: {x: 2}, right: {units: 4}, op_it: "Togli 3 pesi da ogni piatto"}
:::

## Segui sempre la stessa procedura {idea icon=list-checks}

::: procedure "La procedura"
steps:
  - {tag: move, text_it: "Porta la x a sinistra e i numeri a destra.", example_tex: '3x - 3 = 6 \to 3x = 6 + 3'}
  - {tag: divide, text_it: "Dividi per il numero davanti alla x.", example_tex: 'x = 9 : 3 = 3'}
:::

::: check number
prompt_it: 'Da $2x = 6$ dividi per 2. Quanto vale $x$?'
input_before: '$x =$'
answer: '3'
errors:
  - {answer: '12', code: math_divide_missing, message_it: 'Hai moltiplicato per 2 invece di dividere.'}
explain_it: 'Dividi tutti e due i membri per 2: $6 : 2 = 3$.'
:::

## Un esempio passo per passo {example icon=pencil-ruler}

::: example
problem_it: 'Risolvi $3x - 1 = 2x + 4$.'
steps:
  - tag: move
    do_it: '$3x - 2x = 4 + 1$'
    why_it: "Sposti i termini cambiando segno."
  - tag: add
    do_it: '$x = 5$'
    why_it: '$3 - 2 = 1$.'
    blank:
      component: number
      prompt_it: 'Quanto vale il coefficiente di $x$ dopo la somma?'
      input_before: '$\role{unknown}{x}$ ha coefficiente'
      answer: '1'
      explain_it: '$3 - 2 = 1$.'
  - tag: verify
    do_it: '$3 \cdot 5 - 1 = 14 = 2 \cdot 5 + 4$'
    why_it: "Tornano 14 e 14."
result_it: "La soluzione è $x = 5$."
:::

## Errori da evitare {mistakes}

::: mistake
group_it: "Segni"
wrong_it: '$2x - 3 = 7 \to 2x = 7 - 3$'
right_it: '$2x = 7 + 3$'
why_it: 'Spostando, $-3$ diventa $+3$.'
code: math_sign_move
:::

::: mistake
group_it: "Segni"
wrong_it: '$-(x - 2) = -x - 2$'
right_it: '$-(x - 2) = -x + 2$'
why_it: 'Il meno cambia il segno di tutti i termini.'
code: math_sign_bracket
:::

::: mistake
group_it: "Dividere"
wrong_it: '$3x = 9 \to x = 9 - 3$'
right_it: '$x = 9 : 3 = 3$'
why_it: 'Il 3 moltiplica la $x$: si toglie dividendo.'
code: math_divide_missing
:::

## Prova tu {try}

::: try
intro_it: "Fai i conti sul quaderno, poi scrivi qui il risultato."
exercises:
  - text_it: 'Risolvi e verifica: $3x - 7 = 2$.'
    check:
      component: number
      prompt_it: 'Quanto vale $x$?'
      input_before: '$x =$'
      answer: '3'
      errors:
        - {answer: '-5/3', code: math_sign_move, message_it: 'Guarda il segno di $-7$ quando cambia membro.'}
    solution_steps:
      - {tag: move, do_it: '$3x = 2 + 7 = 9$', why_it: 'Sposta $-7$ cambiando segno.'}
      - {tag: divide, do_it: '$x = 9 : 3 = 3$', why_it: 'Dividi per 3.'}
  - text_it: 'Risolvi: $4x - 1 = 15$.'
    check:
      component: number
      prompt_it: 'Quanto vale $x$?'
      input_before: '$x =$'
      answer: '4'
    solution_it: 'Sposti $-1$: $4x = 16$, quindi $x = 4$.'
  - text_it: 'Risolvi: $2x + 3 = x + 9$.'
    check:
      component: number
      prompt_it: 'Quanto vale $x$?'
      input_before: '$x =$'
      answer: '6'
    solution_it: 'Le x a sinistra: $x = 6$.'
  - text_it: 'Risolvi: $3x = 7$.'
    check:
      component: fraction
      prompt_it: 'Scrivi $x$ come frazione.'
      input_before: '$x =$'
      answer: '7/3'
    final_it: '$x = \frac{7}{3}$'
    solution_it: 'Dividi per 3 i due membri: $x = \frac{7}{3}$.'
:::

## In sintesi {summary}

::: summary
- Sposta cambiando segno, somma, dividi per il coefficiente.
- $0 \cdot x = b$ con $b \neq 0$: impossibile. $0 \cdot x = 0$: indeterminata.
- Verifica sempre nell'equazione di partenza.
:::

::: schema flow
alt_it: "Da ax = b: se a è diverso da 0 è determinata; se a = 0 e b è diverso da 0 è impossibile; se a = 0 e b = 0 è indeterminata."
nodes:
  - {id: s, kind: step, text_it: 'Arrivi a $ax = b$'}
  - {id: q1, kind: decision, text_it: '$a \neq 0$?'}
  - {id: det, kind: end, text_it: 'Determinata'}
  - {id: q2, kind: decision, text_it: '$b \neq 0$?'}
  - {id: imp, kind: end, text_it: "Impossibile"}
  - {id: ind, kind: end, text_it: "Indeterminata"}
edges:
  - [s, q1]
  - [q1, det, "sì"]
  - [q1, q2, "no"]
  - [q2, imp, "sì"]
  - [q2, ind, "no"]
:::
