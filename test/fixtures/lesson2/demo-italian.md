---
schema: banco.lesson/2
key: ripasso.italian.demo-sentence
kind: ripasso
subject: italian
title_it: "La frase: soggetto, predicato e complementi"
goals_it:
  - "**Trovare** il predicato, il centro della frase"
  - "**Riconoscere** il soggetto e il complemento oggetto"
skills: [italian.demo-sentence-parts]
uses: []
refs:
  - {source: seconda-2025-26, line: 31, fragment: "analisi logica della frase semplice", role: needed_by}
  - {source: prima-2025-26, line: 21, fragment: "soggetto e predicato", role: taught_in}
scope: studied
minutes: 25
calculator: false
why_it: "Per capire un testo devi sapere chi fa che cosa. Il soggetto e il predicato ti dicono proprio questo."
hero:
  type: sentence
  layout: centre
  alt_it: "La frase Marco legge un libro: il verbo legge è al centro, Marco e un libro gli stanno intorno."
  text_it: "Marco legge un libro"
  parts:
    - {id: s, text_it: "Marco", role: subject, label_it: "soggetto"}
    - {id: p, text_it: "legge", role: predicate, label_it: "predicato"}
    - {id: o, text_it: "un libro", role: object, label_it: "oggetto"}
---

# Il centro della frase

## Ogni frase ha un centro {idea icon=zap id=centro}

Il **predicato** dice che cosa succede. Tutte le altre parti stanno intorno a lui.

::: diagram sentence
alt_it: "La frase Il gatto beve il latte con il verbo beve al centro e le altre parti intorno."
text_it: "Il gatto beve il latte"
layout: centre
parts:
  - {id: s, text_it: "Il gatto", role: subject, label_it: "soggetto", question_it: "Chi beve?"}
  - {id: p, text_it: "beve", role: predicate, label_it: "predicato", question_it: "Che cosa fa?"}
  - {id: o, text_it: "il latte", role: object, label_it: "oggetto", question_it: "Che cosa beve?"}
:::

::: check span_select
prompt_it: "Tocca il predicato."
text_it: "La bambina canta una canzone"
spans:
  - {id: s1, text_it: "La bambina"}
  - {id: s2, text_it: "canta"}
  - {id: s3, text_it: "una canzone"}
answer: [s2]
errors:
  - {answer: [s1], code: it_subject_for_predicate, message_it: "La bambina è chi fa l'azione. Cerca la parola che dice l'azione."}
explain_it: "Canta dice che cosa fa la bambina: è il predicato."
:::

## Il soggetto: chi fa l'azione {idea icon=user}

Per trovare il [[subject:soggetto]] chiedi al [[predicate:predicato]]: chi?

::: diagram sentence
alt_it: "La frase Il treno parte con il soggetto Il treno e il predicato parte colorati e con la loro icona."
text_it: "Il treno parte"
layout: line
parts:
  - {id: s, text_it: "Il treno", role: subject, label_it: "soggetto", question_it: "Chi parte?"}
  - {id: p, text_it: "parte", role: predicate, label_it: "predicato", question_it: "Che cosa fa?"}
:::

::: check choice
prompt_it: "Qual è il soggetto di: Luca mangia la mela?"
options:
  - {id: a, text_it: "Luca"}
  - {id: b, text_it: "mangia"}
  - {id: c, text_it: "la mela"}
answer: a
errors:
  - {answer: c, code: it_object_for_subject, message_it: "La mela è ciò che viene mangiato. Chiedi: chi mangia?"}
explain_it: "Chi mangia? Luca. Luca è il soggetto."
:::

# Le altre parti

## Il complemento oggetto risponde a: che cosa? {idea icon=box}

::: legend
roles:
  - {role: subject, question_it: "Chi? Che cosa?"}
  - {role: predicate, question_it: "Qual è il verbo?"}
  - {role: object, question_it: "Chi? Che cosa?"}
:::

::: schema concept_map
alt_it: "Mappa: dal predicato partono il soggetto, che fa l'azione, e il complemento oggetto, che la riceve."
root: p
nodes:
  - {id: p, text_it: "Il predicato", role: predicate}
  - {id: s, text_it: "Il soggetto", role: subject}
  - {id: o, text_it: "Il complemento oggetto", role: object}
edges:
  - {from: p, to: s, label_it: "chi fa"}
  - {from: p, to: o, label_it: "che cosa riceve"}
:::

## Dove si nasconde il soggetto {idea icon=user}

::: cases "Tre modi di trovarlo"
cases:
  - title_it: "Davanti al verbo"
    icon: user
    text_it: "Di solito il soggetto sta prima del predicato."
    example_it: "Il cane corre."
  - title_it: "Dopo il verbo"
    icon: repeat
    text_it: "A volte il soggetto viene dopo."
    example_it: "Arriva il treno."
  - title_it: "Sottinteso"
    icon: message-circle-question
    text_it: "Il verbo ti dice chi è, anche se non lo scrivi."
    example_it: "Mangiamo la pizza."
:::

::: check matching
prompt_it: "Per ogni frase scegli dove sta il soggetto."
reuse_right: true
left:
  - {id: l1, text_it: "Il cane corre."}
  - {id: l2, text_it: "Arriva il treno."}
  - {id: l3, text_it: "Mangiamo la pizza."}
right:
  - {id: r1, text_it: "Prima del verbo"}
  - {id: r2, text_it: "Dopo il verbo"}
  - {id: r3, text_it: "Sottinteso"}
answer: {l1: r1, l2: r2, l3: r3}
explain_it: "Cerca il verbo e chiediti chi fa l'azione."
:::

## Analizza una frase passo per passo {example icon=highlighter}

::: example
problem_it: "Analizza: Anna scrive una lettera."
diagram:
  type: sentence
  alt_it: "La frase Anna scrive una lettera, analizzata un passo alla volta: prima il predicato, poi il soggetto, poi l'oggetto."
  text_it: "Anna scrive una lettera"
  layout: line
  parts:
    - {id: s, text_it: "Anna", role: subject, label_it: "soggetto"}
    - {id: p, text_it: "scrive", role: predicate, label_it: "predicato"}
    - {id: o, text_it: "una lettera", role: object, label_it: "oggetto"}
  states:
    - {parts: [{id: p, text_it: "scrive", role: predicate, label_it: "predicato"}], op_it: "Trova il predicato"}
    - {parts: [{id: s, text_it: "Anna", role: subject, label_it: "soggetto"}, {id: p, text_it: "scrive", role: predicate, label_it: "predicato"}], op_it: "Chiedi: chi scrive?"}
    - {op_it: "Chiedi: che cosa scrive?"}
steps:
  - tag: predicate
    do_it: "Il predicato è scrive."
    why_it: "Dice che cosa succede."
  - tag: ask
    do_it: "Chi scrive? Anna."
    why_it: "Chi fa l'azione è il soggetto."
    blank:
      component: choice
      prompt_it: "Che cosa è Anna nella frase?"
      options:
        - {id: a, text_it: "il soggetto"}
        - {id: b, text_it: "il predicato"}
      answer: a
      explain_it: "Anna fa l'azione: è il soggetto."
  - tag: mark
    do_it: "Che cosa scrive? Una lettera."
    why_it: "Ciò che riceve l'azione è l'oggetto."
result_it: "Anna è il soggetto, scrive il predicato, una lettera il complemento oggetto."
:::

# Alla fine

## Errori da evitare {mistakes}

::: mistake
group_it: "Il soggetto"
wrong_it: "Nella frase Arriva il treno il soggetto è Arriva."
right_it: "Il soggetto è il treno."
why_it: "Il soggetto è chi fa l'azione, anche se sta dopo il verbo."
code: it_subject_for_predicate
:::

::: mistake
group_it: "L'oggetto"
wrong_it: "Nella frase Luca mangia la mela l'oggetto è Luca."
right_it: "L'oggetto è la mela."
why_it: "L'oggetto è ciò che riceve l'azione."
code: it_object_for_subject
:::

::: mistake
group_it: "Il verbo"
wrong_it: "Il predicato è sempre una sola parola."
right_it: "Può essere più di una parola, come è partito."
why_it: "I tempi composti usano due parole."
:::

## Prova tu {try}

::: try
intro_it: "Fai le analisi sul quaderno, poi controlla qui."
exercises:
  - text_it: "Trova il soggetto: Il bambino disegna un sole."
    check:
      component: span_select
      prompt_it: "Tocca il soggetto."
      text_it: "Il bambino disegna un sole"
      spans:
        - {id: s1, text_it: "Il bambino"}
        - {id: s2, text_it: "disegna"}
        - {id: s3, text_it: "un sole"}
      answer: [s1]
    solution_it: "Chi disegna? Il bambino."
  - text_it: "Trova il predicato: Il vento muove le foglie."
    check:
      component: span_select
      prompt_it: "Tocca il predicato."
      text_it: "Il vento muove le foglie"
      spans:
        - {id: s1, text_it: "Il vento"}
        - {id: s2, text_it: "muove"}
        - {id: s3, text_it: "le foglie"}
      answer: [s2]
    solution_it: "Muove dice che cosa fa il vento."
  - text_it: "Nella frase Arriva il treno, qual è il soggetto?"
    check:
      component: choice
      prompt_it: "Scegli il soggetto."
      options:
        - {id: a, text_it: "Arriva"}
        - {id: b, text_it: "il treno"}
      answer: b
    solution_it: "Chi arriva? Il treno."
  - text_it: "Scrivi il complemento oggetto: Paola legge un fumetto."
    check:
      component: normalized_text
      prompt_it: "Scrivi il complemento oggetto."
      answer: "un fumetto"
      accept: ["fumetto"]
    solution_it: "Che cosa legge Paola? Un fumetto."
:::

## In sintesi {summary}

::: summary
- Il predicato dice che cosa succede.
- Il soggetto è chi fa l'azione: chiedi chi?
- Il complemento oggetto è ciò che riceve l'azione: chiedi che cosa?
:::

::: schema concept_map
alt_it: "Mappa: la frase ha il predicato al centro, il soggetto che fa l'azione e il complemento oggetto che la riceve."
root: f
nodes:
  - {id: f, text_it: "La frase"}
  - {id: p, text_it: "Predicato", role: predicate}
  - {id: s, text_it: "Soggetto", role: subject}
  - {id: o, text_it: "Complemento oggetto", role: object}
edges:
  - {from: f, to: p}
  - {from: p, to: s, label_it: "chi?"}
  - {from: p, to: o, label_it: "che cosa?"}
:::

## Gli altri complementi {idea extra icon=puzzle}

::: schema table
alt_it: "Tabella dei complementi di tempo, luogo e causa con la domanda a cui rispondono e un esempio."
header: ["Complemento", "Domanda", "Esempio"]
rows:
  - ["tempo", "Quando?", "Parto domani."]
  - ["luogo", "Dove?", "Vivo a Roma."]
  - ["causa", "Perché?", "Resto per il freddo."]
:::
