---
# Gallery of the family science (WAVE2 1.2, 5.4): every available type, view and mode below is drawn in CI with Chrome at 320, 390, 768 and
# 1280 px (text size 18, 20, 26 px) with no finding at all (V6), and shown to the lead for the look gate. Invented content only.
#
# Built so far (T7, w2-1):
#   `formula` (diagram): the decoder with its pieces, labels, arrows, count table and molecules, one and several formulas, the brackets of a
#     group, a focus followed through the states; select targets: pieces (mode `select`). Cards 1 to 4.
# Still to come, in this file when each is built:
#   `molecule` (diagram; reserved, schema final, batch w2-1, track T7): select targets items, atoms
#   `periodic_table` (diagram; reserved, schema final, batch w2-1, track T7): select targets cells
#   `strand` (diagram; reserved, schema final, batch w2-1, track T7): select targets bases, backbone, rungs
#   `particles` (diagram; draft, schema draft, batch w2-2, track T7)
#   `phase_changes` (diagram; draft, schema draft, batch w2-2, track T7)
#   `cell` (diagram; draft, schema draft, batch w2-2, track T7)
schema: banco.lesson/2
key: ripasso.chemistry.gallery-science
kind: ripasso
subject: chemistry
title_it: "Galleria della scienza: formule, molecole, tavola e filamenti"
goals_it:
  - "**Leggere** una formula pezzo per pezzo"
  - "**Contare** gli atomi senza sbagliare"
skills: [chemistry.gallery-science]
refs:
  - {source: seconda-2025-26, line: 1, fragment: "formule e simboli", role: taught_in}
scope: studied
minutes: 20
calculator: false
why_it: "Mostra le figure della chimica e della biologia, una dopo l'altra."
---

# Leggere una formula

## Una formula, un pezzo alla volta {idea icon=atom id=pezzi}

Guarda **un pezzo alla volta**. Prima i simboli, poi i pedici, poi il conto.

::: diagram formula
alt_it: "La formula 3 H2O: il coefficiente 3, il simbolo H con il pedice 2, il simbolo O. Sotto, tre molecole d'acqua."
formulas: ['3 H2O']
show: [parts]
states:
  - {show: [parts], op_it: "Trova i simboli"}
  - {show: [parts, count], focus: H, op_it: "Il pedice 2 è dell'H"}
  - {show: [parts, count, molecules], op_it: "Tre molecole, sei atomi di idrogeno"}
:::

## Le parentesi {idea icon=parentheses id=parentesi}

::: diagram formula
alt_it: "La formula 2 Ca(NO3)2: il coefficiente 2, il simbolo Ca, il pacchetto NO3 con il pedice 2. Sotto il conto degli atomi."
formulas: ['2 Ca(NO3)2']
show: [parts, count]
focus: O
:::

# Cosa disegna una formula

## Due formule vicine {idea icon=git-compare id=vicine}

::: diagram formula
alt_it: "Due formule vicine: il cobalto Co, un solo simbolo, e il monossido di carbonio CO, con due simboli. Sotto, cosa disegnano."
formulas: ['Co', 'CO']
show: [parts, count, molecules]
:::

## Un sale non ha molecole {idea icon=boxes id=sale}

::: diagram formula
alt_it: "La formula NaCl: il simbolo Na e il simbolo Cl. Sotto, un reticolo di ioni con una unità in un riquadro."
formulas: ['NaCl']
show: [parts, molecules]
:::

## Trova il pedice {idea icon=subscript id=trova-pedice}

::: check select
prompt_it: "Tocca il pedice dell'idrogeno: il numero piccolo accanto al suo simbolo."
diagram:
  type: formula
  alt_it: "Una formula con un numero davanti, due simboli e un numero piccolo in basso. Ogni pezzo si può toccare."
  formulas: ['3 H2O']
targets: pieces
pick: one
answer: ['f1p3']
errors:
  - {answer: ['f1p1'], code: coefficient_for_subscript, message_it: "Quello è il coefficiente, il numero grande davanti."}
explain_it: "Il pedice è il numero piccolo in basso: il 2 conta gli atomi di H."
:::
