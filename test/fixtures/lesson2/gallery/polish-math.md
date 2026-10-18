---
# The renderer problems the maths author reported in wave 3 (D-310), one card each, invented content: formulas in the part and total labels
# of a `bar_model`, formulas in the header cells of a `schema table`, a `math` block written in YAML quotes (single and double), a `number`
# check with text before and after the box, a `choice` check whose options are formulas with colour roles, and a `cases` block whose title
# holds a formula. test/validation/lesson_polish_gallery_test.rb draws it in Chrome at the viewports of lesson2.render and keeps no finding.
schema: banco.lesson/2
key: ripasso.math.gallery-polish
kind: ripasso
subject: math
title_it: "Galleria delle correzioni del disegno"
goals_it:
  - "**Vedere** i pezzi corretti"
skills: [math.gallery]
refs:
  - {source: gallery-2026, line: 1, fragment: "potenze", role: taught_in}
scope: studied
minutes: 30
calculator: false
why_it: "Una galleria serve a guardare le figure. Il contenuto è inventato."
---

## Stessa base, prodotto {idea icon=plus id=prodotto}

$a^3 \cdot a^4$ è un prodotto di 3 fattori e poi di altri 4: in tutto 7.

::: diagram bar_model
alt_it: "Una barra di 7 fattori uguali ad a: i primi 3 sono a alla terza, gli altri 4 sono a alla quarta. Insieme fanno a alla settima."
caption_it: 'Gli esponenti si sommano: $3 + 4 = 7$.'
view: parts
bars:
  - label_it: '$a^3 \cdot a^4$'
    parts:
      - {value: '3', label_it: '$a^3$'}
      - {value: '4', label_it: '$a^4$'}
total: {value: '7', label_it: 'fattori di $a^7$'}
:::

::: check number
prompt_it: "Conta i fattori della barra."
input_before: '$a^3 \cdot a^4$ ha'
input_after: 'fattori uguali ad $a$.'
answer: '7'
errors:
  - {answer: '12', code: product_exponents_multiplied, message_it: "Hai moltiplicato gli esponenti: i fattori si contano."}
explain_it: '$3 + 4 = 7$.'
:::

## Le potenze di un numero {idea icon=layout-grid id=tabella}

::: schema table
alt_it: "Tabella delle potenze di 2 e di 3: la base, il quadrato e il cubo."
header: ['$n$', '$n^2$', '$n^3$']
rows:
  - ['2', '4', '8']
  - ['3', '9', '27']
:::

::: math
'(a^2)^3 = a^{2 \cdot 3} = a^6'
:::

::: math
"a^7 : a^3 = a^{7 - 3} = a^4"
:::

## Quale potenza {idea icon=multiply id=scelta}

::: cases "Prodotto e potenza di $a^2$"
cases:
  - title_it: '$a^2 \cdot a^3$'
    text_it: "Gli esponenti si sommano."
    example_it: '$a^{2 + 3} = a^5$'
  - title_it: '$(a^2)^3$'
    text_it: "Gli esponenti si moltiplicano."
    example_it: '$a^{2 \cdot 3} = a^6$'
:::

::: check choice
prompt_it: 'Quanto fa $(x^4)^3$?'
options:
  - {id: a, text_it: '$x^7$'}
  - {id: b, text_it: '$x^{12}$'}
  - {id: c, text_it: '$\role{unknown}{x}^{64}$'}
answer: b
errors:
  - {answer: a, code: power_of_power_adds, message_it: "Hai sommato gli esponenti: qui si moltiplicano."}
explain_it: '$(x^4)^3 = x^{4 \cdot 3} = x^{12}$.'
:::
