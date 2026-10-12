---
# Gallery of the family computing (WAVE2 1.2, 5.4): every available type, view and mode below is drawn in CI with Chrome at 320, 390, 768 and
# 1280 px (text size 18, 20, 26 px) with no finding at all (V6), and shown to the lead for the look gate. Invented content only.
#
# Built so far (T9, w2-1):
#   `input: bits` (check option on normalized_text with the binary profile; schema final, track T9): card 9, eight switches in two groups of four.
#     The check carries `profile`, which is T1's option and still reserved: the gallery is parsed with allow_reserved until it lands.
#   `register` (diagram): the row view (weights, two's complement, groups, group digits, toggles with goals, states) and the ring view
#     (both readouts, the seam, the pointer with its stepper, highlights, a move); select targets: bits, codes (mode `select`); modes: student,
#     teacher, print, render, select. Cards 1 to 6.
#   `column_calc` (diagram): add, sub, mul; reveal columns with the stepper; the carry that falls out; the borrow across zeros; select
#     targets: digits. Cards 6 to 8.
# Still to come, in this file when each is built:
#   `sheet` (diagram; reserved, schema none, batch w2-3, track T9)
#   `program` (diagram; draft, schema draft, batch w2-2, track T9): select targets blocks; states: the first, a middle and the last
#   `rgb` (diagram; reserved, schema none, batch w2-3, track T9)
#   `column_calc` `op: repeated_division` (reserved, w2-3)
schema: banco.lesson/2
key: ripasso.computer_science.gallery-computing
kind: ripasso
subject: computer_science
title_it: "Galleria del calcolo: registri e colonne"
goals_it:
  - "**Leggere** un registro bit per bit"
  - "**Seguire** una somma in colonna"
skills: [computer_science.gallery]
refs:
  - {source: seconda-2025-26, line: 1, fragment: "calcolo binario", role: taught_in}
scope: studied
minutes: 20
calculator: false
why_it: "Mostra tutte le figure del calcolo, una dopo l'altra."
---

# Il registro

## Otto bit con i loro pesi {idea icon=binary id=otto-bit}

::: diagram register
alt_it: "Un registro di otto bit: 1111 1011. Sopra ogni bit il suo peso; il primo pesa meno centoventotto. La somma dei pesi dei bit a uno dà meno cinque."
view: row
width: 8
base: 2
value: '11111011'
read: twos
weights: true
groups: 4
mark: [{at: 1, role: sign, label_it: "segno"}]
states:
  - {value: '00000101', op_it: "5 su 8 bit"}
  - {value: '11111010', op_it: "Inverti ogni bit"}
  - {value: '11111011', op_it: "Aggiungi 1"}
:::

## Accendi i bit {idea icon=toggle-right id=accendi}

::: diagram register
alt_it: "Un registro di otto bit: tocca un bit per cambiarlo e guarda come cambia il valore."
view: row
width: 8
base: 2
value: '00101101'
read: unsigned
weights: true
groups: 4
toggle: true
goals: ['45', '255', '0']
:::

## Con il segno {idea icon=scale id=con-segno}

::: diagram register
alt_it: "Un registro di otto bit tutto a zero. Tocca i bit e prova a fare meno uno, meno centoventotto e centoventisette."
view: row
width: 8
base: 2
value: '00000000'
read: twos
weights: true
groups: 4
toggle: true
goals: ['-1', '-128', '127']
mark: [{at: 1, role: sign, label_it: "segno"}]
:::

## Altre basi {idea icon=binary id=altre-basi}

::: diagram register
alt_it: "Un registro in base sedici di quattro cifre: 00FF. Sotto ogni cifra non c'è altro: il valore senza segno è duecentocinquantacinque."
view: row
width: 4
base: 16
value: '00FF'
read: unsigned
weights: true
:::

::: diagram register
alt_it: "Un contatore di tre cifre decimali che torna indietro: da zero zero due a zero zero uno, zero zero zero e poi nove nove nove."
view: row
width: 3
base: 10
value: '002'
states:
  - {value: '002'}
  - {value: '001', op_it: "Indietro di 1"}
  - {value: '000', op_it: "Indietro di 1"}
  - {value: '999', op_it: "999 sta prima di 000"}
:::

::: diagram register
alt_it: "Otto bit scritti in due gruppi di quattro, con la cifra esadecimale sotto ogni gruppo: B e sei."
view: row
width: 8
base: 2
value: '10110110'
read: unsigned
groups: 4
group_digits: true
:::

## La ruota dei codici {idea icon=rotate-ccw id=ruota}

::: diagram register
alt_it: "La ruota dei sedici codici di quattro bit: fuori il valore senza segno, dentro quello con segno; il salto è tra zero uno uno uno e uno zero zero zero."
view: ring
width: 4
read: both
cliff: true
pointer: '0010'
step: true
highlight: [{code: '1111', label_it: "-1"}]
moves: [{from: '0111', by: 1, label_it: "7 + 1", role: carry}]
:::

::: diagram register
alt_it: "La ruota degli otto codici di tre bit, con il valore con segno da meno quattro a tre."
view: ring
width: 3
read: twos
cliff: true
pointer: '111'
step: true
:::

# La colonna

## Una somma che esce dal registro {idea icon=plus id=somma}

::: diagram column_calc
alt_it: "Somma in colonna di 0000 0101 e 1111 1011 su otto bit: il riporto attraversa tutte le colonne e il nono bit esce dal registro."
base: 2
op: add
a: '00000101'
b: '11111011'
width: 8
reveal: columns
read: twos
:::

## Una sottrazione con il prestito {idea icon=divide id=sottrazione}

::: diagram column_calc
alt_it: "Sottrazione in colonna di 0000 0001 da 1000 0000: il prestito passa attraverso tutti gli zeri."
base: 2
op: sub
a: '10000000'
b: '00000001'
width: 8
reveal: columns
:::

## Una moltiplicazione {idea icon=multiply id=moltiplicazione}

::: diagram column_calc
alt_it: "Moltiplicazione in colonna di 0000 0101 per 101: tre prodotti parziali spostati e la loro somma."
base: 2
op: mul
a: '00000101'
b: '101'
width: 8
reveal: columns
read: unsigned
:::

::: diagram column_calc
alt_it: "Addizione in colonna in base dieci, su tre cifre: quattrocentoottantasette più duecentocinquantasei."
base: 10
op: add
a: '487'
b: '256'
width: 3
:::

## Scrivi i bit con gli interruttori {idea icon=toggle-right id=interruttori}

::: check normalized_text
prompt_it: 'Scrivi $-3$ in complemento a 2 su 8 bit.'
input: bits
profile: {name: binary, width: 8, leading_zeros: required}
answer: '11111101'
errors:
  - {answer: '00000001', code: inverted_before_padding, message_it: 'Hai invertito prima di portare il numero a 8 bit.'}
  - {answer: '11111100', code: invert_without_plus_one, message_it: 'Manca il più 1.'}
explain_it: 'Il 3 è $0000\,0011$. Invertito diventa $1111\,1100$. Più 1 fa $1111\,1101$.'
:::
