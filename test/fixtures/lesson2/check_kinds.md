---
schema: banco.lesson/2
key: ripasso.italian.demo-check-kinds
kind: ripasso
subject: italian
title_it: "Le domande della lezione, una per tipo"
goals_it:
  - "**Rispondere** a ogni tipo di domanda della lezione"
skills: [italian.demo-sentence-parts]
uses: []
refs:
  - {source: seconda-2025-26, line: 31, fragment: "analisi logica della frase semplice", role: needed_by}
scope: studied
minutes: 20
calculator: false
why_it: "Una lezione di prova: una domanda per ogni modo di rispondere, per vedere che ognuno controlla davvero."
hero:
  type: sentence
  layout: centre
  alt_it: "La frase Marco legge un libro: il verbo legge è al centro."
  text_it: "Marco legge un libro"
  parts:
    - {id: s, text_it: "Marco", role: subject, label_it: "soggetto"}
    - {id: p, text_it: "legge", role: predicate, label_it: "predicato"}
    - {id: o, text_it: "un libro", role: object, label_it: "oggetto"}
---

# Scrivere e toccare

## Scrivere la parola {idea icon=pencil}

Una parola da scrivere.

::: check normalized_text
prompt_it: "Come si chiama la parola che dice che cosa succede in una frase?"
answer: "verbo"
errors:
  - {answer: "nome", code: it_noun_for_verb, message_it: "Il nome dice chi o che cosa. Cerca la parola che dice l'azione."}
explain_it: "Il verbo dice che cosa succede: corre, legge, dorme."
:::

## Costruire la frase {idea icon=puzzle}

Una frase da costruire con le parole.

::: check tiles
prompt_it: "Costruisci la frase."
tiles:
  - {id: a, text_it: "Marco"}
  - {id: b, text_it: "legge"}
  - {id: c, text_it: "un"}
  - {id: d, text_it: "libro"}
answer: [a, b, c, d]
errors:
  - {answer: [b, a, c, d], message_it: "Il soggetto va prima del verbo."}
explain_it: "Prima chi fa l'azione, poi l'azione, poi che cosa."
:::

## Mettere in ordine {idea icon=list-ordered}

Fatti da mettere in fila.

::: check ordering
prompt_it: "Metti i fatti nell'ordine in cui succedono."
items:
  - {id: a, text_it: "Rita esce di casa."}
  - {id: b, text_it: "Rita arriva al cinema."}
  - {id: c, text_it: "Rita si siede."}
answer: [a, b, c]
errors:
  - {answer: [b, a, c], message_it: "Prima esce di casa, poi arriva."}
explain_it: "Esce, arriva, si siede."
:::

## Toccare le parole giuste {idea icon=pointer}

Parole da toccare nella frase.

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

## Collegare {idea icon=link}

Parole da collegare.

::: check matching
prompt_it: "Collega ogni parola alla sua parte."
left:
  - {id: l1, text_it: "Marco"}
  - {id: l2, text_it: "legge"}
  - {id: l3, text_it: "un libro"}
right:
  - {id: r1, text_it: "soggetto"}
  - {id: r2, text_it: "predicato"}
  - {id: r3, text_it: "oggetto"}
answer: {l1: r1, l2: r2, l3: r3}
errors:
  - {answer: {l1: r2, l2: r1, l3: r3}, code: it_swap, message_it: "Marco fa l'azione: è il soggetto."}
explain_it: "Marco è il soggetto, legge il predicato, un libro l'oggetto."
:::

# Alla fine

## Errori da evitare {mistakes}

::: mistake
wrong_it: "Il soggetto è sempre la prima parola."
right_it: "Il soggetto è chi fa l'azione, dovunque stia."
why_it: "A volte il soggetto sta dopo il verbo: Arriva il treno."
:::

## Prova tu {try}

::: try
intro_it: "Fai le analisi sul quaderno, poi controlla qui."
exercises:
  - text_it: "Nella frase Arriva il treno, qual è il soggetto?"
    check:
      component: choice
      prompt_it: "Scegli il soggetto."
      options:
        - {id: a, text_it: "Arriva"}
        - {id: b, text_it: "il treno"}
      answer: b
      errors:
        - {answer: a, message_it: "Arriva dice che cosa succede: è il predicato."}
    solution_it: "Chi arriva? Il treno."
  - text_it: "Metti in ordine le parole: legge Paola un fumetto."
    check:
      component: tiles
      prompt_it: "Costruisci la frase."
      tiles:
        - {id: a, text_it: "Paola"}
        - {id: b, text_it: "legge"}
        - {id: c, text_it: "un fumetto"}
      answer: [a, b, c]
    solution_steps:
      - {do_it: "Chi legge? Paola.", why_it: "È il soggetto."}
      - {do_it: "Paola legge un fumetto.", why_it: "Poi il verbo, poi l'oggetto."}
:::

## In sintesi {summary}

::: summary
- Il verbo dice che cosa succede.
- Il soggetto è chi fa l'azione.
:::
