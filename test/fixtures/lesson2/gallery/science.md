---
# Gallery of the family science (WAVE2 1.2, 5.4): every available type, view and mode below is drawn in CI with Chrome at 320, 390, 768 and
# 1280 px (text size 18, 20, 26 px) with no finding at all (V6), and shown to the lead for the look gate. Invented content only.
#
# Built so far (T7, w2-1):
#   `formula` (diagram): the decoder with its pieces, labels, arrows, count table and molecules, one and several formulas, the brackets of a
#     group, a focus followed through the states; select targets: pieces (mode `select`). Cards 1 to 4.
#   `molecule` (diagram): balls and sticks, copies by the coefficient, the angle and the partial charges from the library, salts and metals as a
#     patch with one unit framed, never as molecules; select targets: items, atoms (mode `select`). Cards 6 to 10.
#   `periodic_table` (diagram): periods 1 to 4 and the main groups, symbols with names or atomic numbers, highlight sets, the latin ring, the element
#     card on a tap, the list by group below 600 px; select targets: cells (mode `select`). Cards 11 to 14.
# Still to come, in this file when each is built:
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

# Le molecole

## Quattro molecole {idea icon=flask-conical id=quattro}

Ogni atomo ha **il suo simbolo** scritto dentro. Gli idrogeni sono i più piccoli.

::: diagram molecule
alt_it: "Quattro molecole: CO con un carbonio e un ossigeno, CO2 con due ossigeni, H2O con due idrogeni, H2O2 con due idrogeni e due ossigeni."
items:
  - {formula: 'CO', label_it: "monossido di carbonio"}
  - {formula: 'CO2', label_it: "anidride carbonica"}
  - {formula: 'H2O', label_it: "acqua"}
  - {formula: 'H2O2', label_it: "acqua ossigenata"}
style: balls
show: [symbols]
:::

## L'angolo e le cariche {idea icon=thermometer id=angolo}

::: diagram molecule
alt_it: "Una molecola d'acqua e una di anidride carbonica: l'angolo tra i legami dell'acqua e le cariche parziali dei suoi atomi."
items:
  - {formula: 'H2O'}
  - {formula: 'CO2'}
show: [symbols, angle, partial]
:::

## Più copie, solo le aste {idea icon=copy id=copie}

::: diagram molecule
alt_it: "Due molecole di ossigeno e tre di idrogeno, disegnate con le sole aste: ogni molecola ha due atomi legati."
items:
  - {formula: '2 O2'}
  - {formula: '3 H2'}
style: sticks
:::

## Un sale e un metallo {idea icon=boxes id=reticoli}

::: diagram molecule
alt_it: "Il cloruro di sodio, l'idrossido di calcio e il cobalto: nessuna molecola, ma reticoli con una unità in un riquadro."
items:
  - {formula: 'NaCl'}
  - {formula: 'Ca(OH)2'}
  - {formula: 'Co'}
:::

## Trova la molecola {idea icon=test-tube id=trova-molecola}

::: check select
prompt_it: "Tocca la molecola che ha quattro atomi."
diagram:
  type: molecule
  alt_it: "Quattro molecole in fila, di due, tre, tre e quattro atomi. Ogni molecola si può toccare."
  items:
    - {formula: 'CO'}
    - {formula: 'CO2'}
    - {formula: 'H2O'}
    - {formula: 'H2O2'}
targets: items
pick: one
answer: ['i4']
errors:
  - {answer: ['i2'], code: count_letters, message_it: "Quella ha tre atomi: due ossigeni e un carbonio."}
explain_it: "Conta le palline: la quarta molecola ne ha quattro."
:::

# La tavola periodica

## Le prime quattro righe {idea icon=layers-3 id=quattro-righe}

Tocca un elemento: si apre **la sua scheda**.

::: diagram periodic_table
alt_it: "Le prime quattro righe della tavola periodica. Sono evidenziati idrogeno, carbonio, azoto, ossigeno, sodio, cloro, calcio e ferro."
range: periods_1_4
show: symbol_name
highlight:
  - {symbols: [H, C, N, O, Na, Cl, Ca, Fe], label_it: "in questa lezione"}
mark_latin: true
:::

## I gruppi, uno alla volta {idea icon=boxes id=gruppi}

::: diagram periodic_table
alt_it: "Le prime quattro righe della tavola periodica, un gruppo alla volta: prima i metalli alcalini, poi gli alogeni, poi i gas nobili."
range: periods_1_4
show: symbol
states:
  - {highlight: [{symbols: [Li, Na, K], label_it: "metalli alcalini"}], op_it: "Gruppo 1"}
  - {highlight: [{symbols: [Li, Na, K], label_it: "metalli alcalini"}, {symbols: [F, Cl, Br], label_it: "alogeni"}], op_it: "Gruppo 17"}
  - {highlight: [{symbols: [He, Ne, Ar, Kr], label_it: "gas nobili"}], op_it: "Gruppo 18"}
:::

## I gruppi principali {idea icon=case-sensitive id=principali}

::: diagram periodic_table
alt_it: "I gruppi principali della tavola periodica, con il numero atomico sopra ogni simbolo e il cerchio vuoto sugli elementi che vengono dal latino."
range: main_groups
show: symbol_z
mark_latin: true
:::

## Trova il sodio {idea icon=tag id=trova-sodio}

::: check select
prompt_it: "Tocca il simbolo del sodio."
diagram:
  type: periodic_table
  alt_it: "Le prime quattro righe della tavola periodica, ogni elemento con il suo simbolo. Ogni simbolo si può toccare."
  range: periods_1_4
targets: cells
pick: one
answer: ['na']
errors:
  - {answer: ['n'], code: n_for_na, message_it: "Quello è l'azoto, il simbolo N. Il sodio ha due lettere."}
explain_it: "Il sodio è Na: la N maiuscola e la a minuscola."
:::
