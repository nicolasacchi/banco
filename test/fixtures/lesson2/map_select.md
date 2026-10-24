---
schema: banco.lesson/2
key: ponte.history.map-select-probe
kind: ponte
subject: history
title_it: "Prova delle carte da toccare"
goals_it:
  - "**Toccare** una zona sulla carta"
skills: [history.ancient-map]
uses: []
refs:
  - {source: seconda-2025-26, line: 127, fragment: "L' Impero Romano: nascita", role: needed_by}
scope: studied
minutes: 10
calculator: false
why_it: "Una lezione di prova: due domande da rispondere toccando la carta."
hero:
  type: map
  base: mediterraneo_antico
  alt_it: "Il Mediterraneo antico con l'Italia in evidenza."
  highlight:
    - {id: italia, role: rome}
---

# Le carte da toccare

## Zone {idea short="Zone" icon=map}

Una domanda sulle zone.

::: check select
prompt_it: "In quale zona sta Cartagine? Tocca la zona sulla carta."
diagram:
  type: map
  base: mediterraneo_antico
  alt_it: "Carta del Mediterraneo senza nomi: quattro zone si possono toccare."
  candidates: [africa-proconsolare, egitto, macedonia, hispania]
targets: areas
pick: one
answer: [africa-proconsolare]
errors:
  - {answer: [egitto], code: carthage_misplaced, message_it: "Questo è l'Egitto, molto più a est."}
explain_it: "Cartagine sta sulla costa dell'Africa del Nord, di fronte alla Sicilia."
:::

## Ancora zone {idea short="Ancora" icon=map}

Il testo di una scheda senza domande.

# I luoghi

## Luoghi {idea short="Luoghi" icon=map}

Una domanda sui luoghi.

::: check select
prompt_it: "Dov'è Cartagine? Tocca il punto sulla carta."
diagram:
  type: map
  base: mediterraneo_antico
  alt_it: "Carta del Mediterraneo senza nomi: quattro luoghi si possono toccare."
  places:
    - {id: roma}
    - {id: cartagine}
    - {id: atene}
    - {id: alessandria}
targets: places
pick: one
answer: [cartagine]
explain_it: "Cartagine sta sulla costa dell'Africa del Nord."
:::

## Ancora luoghi {idea short="Ancora" icon=map}

Il testo di una scheda senza domande.
