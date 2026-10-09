---
schema: banco.lesson/2
key: ripasso.math.demo-equations
kind: ripasso
subject: math
title_it: "Equazioni di primo grado: risolvere e verificare"
goals_it:
  - "**Risolvere** un'equazione di primo grado intera"
  - "**Capire** se ha una soluzione, nessuna o infinite"
  - "**Verificare** il risultato nell'equazione di partenza"
skills: [math.demo-equation]
uses: [math.demo-signed-numbers]
refs:
  - {source: seconda-2025-26, line: 12, fragment: "equazioni di primo grado numeriche", role: needed_by}
  - {source: prima-2025-26, line: 7, fragment: "equazioni di primo grado", role: taught_in}
scope: studied
minutes: 30
calculator: false
book_it: "Cerca «equazioni di primo grado» e «principi di equivalenza»."
why_it: "Molti argomenti di quest'anno finiscono con un'equazione come $ax = b$. Se la sai risolvere, il resto è più semplice."
hero:
  type: balance
  alt_it: "Bilancia in equilibrio: a sinistra due scatole x e un peso da 1, a destra sette pesi da 1."
  left: {x: 2, units: 1}
  right: {units: 7}
  x_value: '3'
---

# Per cominciare

## Un'equazione è una bilancia {idea icon=scale id=bilancia}

I due membri sono i due piatti. Una **soluzione** è il numero che, al posto di $\role{unknown}{x}$, tiene i piatti in equilibrio.

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
  - {answer: c, code: math_divide_missing, message_it: 'Hai fatto $7 - 3 = 4$, ma non hai diviso per 2.'}
explain_it: 'Con $x = 2$: $2 \cdot 2 + 3 = 7$. I piatti sono uguali.'
:::

## I pezzi di un'equazione {idea}

::: diagram equation_parts
alt_it: "L'equazione 3x - 7 = 2 divisa in pezzi: il primo membro 3x - 7, il segno uguale e il secondo membro 2."
parts:
  - {tex: '3\role{unknown}{x}', role: left, label_it: "primo membro"}
  - {tex: '-7', role: left}
  - {tex: '=', role: muted}
  - {tex: '2', role: right, label_it: "secondo membro"}
brackets:
  - {from: 0, to: 1, label_it: "tutto a sinistra", role: left}
:::

::: legend
roles:
  - {role: unknown, note_it: "il numero che cerchi"}
  - {role: known, note_it: "i numeri che hai già"}
  - {role: left, note_it: "tutto prima dell'uguale"}
  - {role: right, note_it: "tutto dopo l'uguale"}
:::

:::: more "Che cosa vuol dire intera"
Intera vuol dire che la $x$ non sta mai sotto una frazione. Per esempio $\frac{x}{3} = 2$ non è intera.
::::

# Le regole

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

::: math
lines:
  - {tex: '2x + 3 = 7'}
  - {tex: '2x + 3 \role{highlight}{- 3} = 7 \role{highlight}{- 3}', note_it: "togli 3 da tutti e due"}
  - {tex: '2x = 4'}
:::

## Dividi i due piatti per lo stesso numero {idea icon=weight}

::: callout rule "Secondo principio"
Puoi dividere i due membri per lo stesso numero, se non è zero.
:::

::: diagram balance
alt_it: "Sei scatole pesano come diciotto pesi. Divisi in 6 gruppi uguali, una scatola pesa come tre pesi."
left: {x: 6}
right: {units: 18}
x_value: '3'
states:
  - {op_it: "Partenza"}
  - {groups: 6, op_it: "Dividi in 6 gruppi"}
  - {left: {x: 1}, right: {units: 3}, op_it: "Resta un gruppo"}
:::

::: check number
prompt_it: 'Da $2x = 6$ dividi per 2. Quanto vale $x$?'
input_before: '$x =$'
answer: '3'
errors:
  - {answer: '12', code: math_divide_missing, message_it: 'Hai moltiplicato per 2 invece di dividere.'}
explain_it: 'Dividi tutti e due i membri per 2: $6 : 2 = 3$.'
:::

# Il metodo

## La procedura in quattro passi {idea icon=list-checks}

::: procedure "La procedura"
steps:
  - {tag: develop, text_it: "Togli le parentesi.", example_tex: '3(x - 1) = 3x - 3'}
  - {tag: move, text_it: "Porta la x a sinistra e i numeri a destra.", example_tex: '3x - 3 = 6 \to 3x = 6 + 3'}
  - {tag: add, text_it: "Somma i termini uguali.", example_tex: '3x = 9'}
  - {tag: divide, text_it: "Dividi per il numero davanti alla x.", example_tex: 'x = 9 : 3 = 3'}
:::

Come sulla [bilancia](scheda:bilancia), cambi sempre tutti e due i membri.

::: callout warning "Attenzione"
Un meno davanti a una parentesi cambia il segno di tutti i termini dentro.
:::

## Tre casi: quante soluzioni? {idea icon=scale}

::: cases "Dopo la somma arrivi a $ax = b$"
cases:
  - title_it: "Una soluzione"
    condition_it: '$a \neq 0$'
    text_it: 'Dividi per $a$.'
    example_it: '$2x = 6$, quindi $x = 3$'
    diagram:
      type: balance
      alt_it: "Bilancia: due scatole a sinistra, sei pesi a destra. Una scatola pesa tre."
      left: {x: 2}
      right: {units: 6}
      x_value: '3'
  - title_it: "Nessuna soluzione"
    condition_it: '$a = 0$ e $b \neq 0$'
    text_it: 'Nessun numero per zero dà $b$.'
    example_it: '$0 \cdot x = 7$'
    diagram:
      type: balance
      alt_it: "Bilancia inclinata: a sinistra una scatola, a destra una scatola e sette pesi. Con ogni numero resta storta."
      left: {x: 1}
      right: {x: 1, units: 7}
  - title_it: "Infinite soluzioni"
    condition_it: '$a = 0$ e $b = 0$'
    text_it: 'Ogni numero va bene.'
    example_it: '$0 \cdot x = 0$'
    diagram:
      type: balance
      alt_it: "Bilancia in equilibrio con le stesse scatole e gli stessi pesi da tutte e due le parti, per ogni numero."
      left: {x: 1, units: 2}
      right: {x: 1, units: 2}
:::

::: check matching
prompt_it: "Collega ogni equazione al suo caso."
left:
  - {id: l1, text_it: '$5x = 0$'}
  - {id: l2, text_it: '$0 \cdot x = 0$'}
  - {id: l3, text_it: '$0 \cdot x = 7$'}
right:
  - {id: r1, text_it: "Una soluzione"}
  - {id: r2, text_it: "Nessuna soluzione"}
  - {id: r3, text_it: "Infinite soluzioni"}
answer: {l1: r1, l2: r3, l3: r2}
errors:
  - {answer: {l1: r3, l2: r3, l3: r2}, code: math_zero_case, message_it: 'Con $5x = 0$ solo $x = 0$ va bene.'}
explain_it: 'Con $a \neq 0$ trovi una soluzione. Con $a = 0$ conta $b$.'
:::

## Un esempio passo per passo {example icon=pencil-ruler}

::: example
problem_it: 'Risolvi $3(x - 1) - x = 2x + 4$.'
steps:
  - tag: develop
    do_it: '$3x - 3 - x = 2x + 4$'
    why_it: "Il 3 moltiplica ogni termine della parentesi."
  - tag: move
    do_it: '$3x - x - 2x = 4 + 3$'
    why_it: "Sposti i termini cambiando segno."
  - tag: add
    do_it: '$0 \cdot x = 7$'
    why_it: '$3 - 1 - 2 = 0$.'
    blank:
      component: number
      prompt_it: 'Quanto vale il coefficiente di $x$?'
      input_before: '$\role{unknown}{x}$ ha coefficiente'
      answer: '0'
      explain_it: '$3 - 1 - 2 = 0$.'
result_it: "Impossibile: nessun numero per 0 dà 7."
:::

# Alla fine

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
      - {tag: verify, do_it: '$3 \cdot 3 - 7 = 2$', why_it: 'Torna 2, come il secondo membro.'}
  - text_it: 'Risolvi: $4x - 1 = 15$.'
    check:
      component: number
      prompt_it: 'Quanto vale $x$?'
      input_before: '$x =$'
      answer: '4'
      errors:
        - {answer: '3,5', code: math_sign_move, message_it: 'Hai sottratto 1 invece di sommarlo.'}
    solution_steps:
      - {tag: move, do_it: '$4x = 15 + 1 = 16$', why_it: 'Sposta $-1$ cambiando segno.'}
      - {tag: divide, do_it: '$x = 16 : 4 = 4$', why_it: 'Dividi per 4.'}
  - text_it: 'Risolvi: $2x + 3 = x + 9$.'
    check:
      component: number
      prompt_it: 'Quanto vale $x$?'
      input_before: '$x =$'
      answer: '6'
    solution_steps:
      - {tag: move, do_it: '$2x - x = 9 - 3$', why_it: 'Le x a sinistra, i numeri a destra.'}
      - {tag: add, do_it: '$x = 6$', why_it: 'Somma i termini uguali.'}
  - text_it: 'Risolvi: $3x = 7$.'
    check:
      component: fraction
      prompt_it: 'Scrivi $x$ come frazione.'
      input_before: '$x =$'
      answer: '7/3'
      errors:
        - {answer: '4', code: math_divide_missing, message_it: 'Hai fatto $7 - 3$ invece di dividere per 3.'}
    final_it: '$x = \frac{7}{3}$'
    solution_it: 'Dividi per 3 i due membri: $x = \frac{7}{3}$.'
:::

## In sintesi {summary}

::: summary
- Sviluppa, sposta cambiando segno, somma, dividi per il coefficiente.
- $0 \cdot x = b$ con $b \neq 0$: impossibile. $0 \cdot x = 0$: indeterminata.
- Verifica sempre nell'equazione di partenza.
:::

::: schema flow
alt_it: "Da ax = b: se a è diverso da 0 è determinata; se a = 0 e b è diverso da 0 è impossibile; se a = 0 e b = 0 è indeterminata."
nodes:
  - {id: s, kind: step, text_it: 'Arrivi a $ax = b$'}
  - {id: q1, kind: decision, text_it: '$a \neq 0$?'}
  - {id: det, kind: end, text_it: 'Determinata: $x = \frac{b}{a}$'}
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

## Che cosa vuol dire graficamente {idea extra icon=telescope}

Ogni equazione di primo grado è una retta. La soluzione è dove la retta incontra l'asse delle $x$.

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

## Sulla retta, i segni sono salti {idea extra icon=telescope}

Sommare un numero positivo sposta a destra. Sommare un numero negativo sposta a sinistra.

::: diagram number_line
alt_it: "Retta dei numeri da -5 a 5. Il numero -4 è segnato, e un salto di 4 verso destra arriva a 0."
min: '-5'
max: '5'
step: '1'
labels: all
marks:
  - {at: '-4', kind: dot, label_it: "-4"}
jumps:
  - {from: '-4', by: '4', label_it: "+4"}
:::
