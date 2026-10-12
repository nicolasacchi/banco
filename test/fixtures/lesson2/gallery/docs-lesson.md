---
schema: banco.lesson/2
key: ripasso.business.gallery-docs
kind: ripasso
subject: business
title_it: "La fattura e le parole della legge"
goals_it:
  - "**Leggere** una fattura, riga per riga"
  - "**Calcolare** l'imponibile, l'IVA e il totale"
  - "**Trovare** le parole che contano in un articolo"
skills: [business.demo-invoice]
uses: [business.demo-vat]
refs:
  - {source: prima-2025-26, line: 148, fragment: "la fattura di vendita", role: taught_in}
  - {source: seconda-2025-26, line: 20, fragment: "gli strumenti di pagamento", role: needed_by}
scope: studied
minutes: 30
calculator: true
why_it: "Una fattura dice quanto devi pagare e perché. Se sai leggerla, trovi subito un errore."
---

## Una fattura, riga per riga {idea icon=receipt id=fattura}

::: diagram document
alt_it: "Fattura di Cartoleria Alfa a Studio Beta: 800 quaderni a 2,50 euro, sconto del 10%, spese del venditore 60,00 euro, spese anticipate 50,00 euro, IVA 22%, totale 2.319,20 euro."
kind: invoice
view: sheet
head: {seller_it: "Cartoleria Alfa srl", buyer_it: "Studio Beta", number: '41', date: '2026-10-12'}
lines:
  - {text_it: "Quaderni A4", qty: '800', price: '2,50', vat: '22'}
discounts: ['10']
costs:
  - {text_it: "Imballaggio", amount: '60,00', documented: false}
  - {text_it: "Corriere pagato per il cliente", amount: '50,00', documented: true}
mark: [base]
:::

::: check choice
prompt_it: "Nella fattura, chi compra?"
options:
  - {id: a, text_it: "Studio Beta"}
  - {id: b, text_it: "Cartoleria Alfa"}
  - {id: c, text_it: "Il corriere"}
answer: a
errors:
  - {answer: b, code: business_documented_taxed, message_it: "Chi vende è Cartoleria Alfa: la trovi sotto «Chi vende»."}
explain_it: "Studio Beta è sotto «Chi compra»."
:::

## Prima togli, poi aggiungi {idea icon=sigma id=cascata}

::: diagram document
alt_it: "La stessa fattura come una cascata in cinque passi: prima si toglie lo sconto, poi si aggiungono le spese, l'IVA e le spese anticipate."
kind: invoice
view: cascade
head: {seller_it: "Cartoleria Alfa srl", buyer_it: "Studio Beta"}
lines:
  - {text_it: "Quaderni A4", qty: '800', price: '2,50', vat: '22'}
discounts: ['10']
costs:
  - {text_it: "Imballaggio", amount: '60,00', documented: false}
  - {text_it: "Corriere pagato per il cliente", amount: '50,00', documented: true}
states:
  - {rows: [gross], op_it: "Il lordo della merce."}
  - {rows: [gross, discounts, net], op_it: "Togli lo sconto."}
  - {rows: [gross, discounts, net, costs_in, base], mark: [base], op_it: "Aggiungi le spese del venditore: ecco l'imponibile."}
  - {rows: [gross, discounts, net, costs_in, base, vat], mark: [base], op_it: "Calcola l'IVA sull'imponibile."}
  - {rows: [gross, discounts, net, costs_in, base, vat, costs_out, total], mark: [base], op_it: "Aggiungi le spese anticipate: ecco il totale."}
:::

::: check number
prompt_it: "Netto 2.000,00 euro. Spese del venditore 80,00 euro. Quanto è l'imponibile?"
input_before: "Imponibile"
answer: '2080'
errors:
  - {answer: '2000', code: business_costs_omitted, message_it: "Le spese del venditore stanno dentro l'imponibile."}
explain_it: "2.000,00 + 80,00 = 2.080,00."
:::

## Le parole della legge {idea icon=landmark id=legge}

::: source
kind: legal
title_it: "Codice di prova, art. 1"
ref: codice-di-prova
parts:
  - text_it: "Il venditore consegna la merce nel luogo e nel giorno indicati nel contratto."
    plain_it: "Il venditore porta la merce dove e quando dice il contratto."
    marks:
      - {text_it: "Il venditore", role: creditor}
  - text_it: "Se il compratore non ritira la merce entro cinque giorni dalla consegna, il venditore può depositarla a spese del compratore"
    plain_it: "Se il compratore non ritira la merce entro cinque giorni, il venditore la mette in deposito. Il deposito lo paga il compratore."
    marks:
      - {text_it: "il compratore", role: debtor}
guide:
  - {span_it: "a spese del compratore", note_it: "Il costo del deposito è del compratore."}
:::

::: check choice
prompt_it: "Dopo cinque giorni, chi paga il deposito della merce?"
options:
  - {id: a, text_it: "Il venditore"}
  - {id: b, text_it: "Il compratore"}
answer: b
explain_it: "La legge dice «a spese del compratore»."
:::

## Che cosa fai? {idea icon=scale id=bivio}

::: reveal
who_it: "Sei il venditore"
situation_it: "Hai spedito la merce. Il cliente non paga la fattura da due mesi. Che cosa fai?"
options:
  - {id: a, text_it: "Aspetto ancora, senza dire niente", then_it: "Il tempo passa e il cliente non si muove."}
  - {id: b, text_it: "Gli scrivo e chiedo di pagare", then_it: "Il cliente sa che aspetti. Resta una prova scritta.", real: true}
  - {id: c, text_it: "Non consegno più nulla, senza avvisare", then_it: "Rischi di non rispettare il contratto."}
real_it: "Di solito il venditore manda prima un sollecito scritto. Poi può pensare ad altri passi."
:::

## Pensaci, poi gira {idea icon=calculator id=errore}

::: reveal
prompt_it: "Perché le spese anticipate per il cliente restano fuori dall'imponibile?"
answer_it: "Sono spese del cliente. Il venditore le paga per lui e le rimette nel totale."
:::

::: diagram document
alt_it: "Una fattura di Cartoleria Alfa a Studio Beta. L'imponibile e il totale sono da calcolare."
kind: invoice
view: sheet
head: {seller_it: "Cartoleria Alfa srl", buyer_it: "Studio Beta", number: '42', date: '2026-10-19'}
lines:
  - {text_it: "Penne", qty: '200', price: '1,20', vat: '22'}
costs:
  - {text_it: "Trasporto", amount: '30,00', documented: true}
hide: [base, total]
mark: [base]
:::

::: check number
prompt_it: "Quanto è il totale della fattura?"
input_before: "Totale"
answer: '329,28'
errors:
  - {answer: '290,40', code: business_costs_omitted, message_it: "Manca una riga: le spese anticipate si aggiungono dopo l'IVA."}
explain_it: "240,00 + 52,80 di IVA + 30,00 di spese anticipate."
:::

## Un esempio {example icon=calculator id=esempio}

::: example
problem_it: "Calcola il totale: 10 risme a 4,00 euro, IVA 22%."
steps:
  - tag: read
    do_it: "10 risme per 4,00 euro fanno 40,00 euro."
    why_it: "Quantità per prezzo."
  - tag: tax
    do_it: "L'IVA è 8,80 euro."
    why_it: "Il 22% di 40,00."
    blank:
      component: number
      prompt_it: "Quanto è il 22% di 40,00 euro?"
      input_before: "IVA"
      answer: '8,80'
      explain_it: "40,00 per 0,22 fa 8,80."
  - tag: total
    do_it: "Il totale è 48,80 euro."
    why_it: "Imponibile più IVA."
result_it: "Il totale è 48,80 euro."
:::

## Prova a dirlo {idea icon=megaphone id=orale}

::: oral
question_it: "Spiega come si arriva dal lordo al totale di una fattura."
outline:
  - {id: o1, text_it: "Parto dal lordo della merce"}
  - {id: o2, text_it: "Tolgo gli sconti e ho il netto"}
  - {id: o3, text_it: "Aggiungo le spese del venditore: ecco l'imponibile"}
  - {id: o4, text_it: "Calcolo l'IVA e aggiungo le spese anticipate"}
answer: [o1, o2, o3, o4]
errors:
  - {answer: [o1, o3, o2, o4], code: business_costs_omitted, message_it: "Prima si toglie lo sconto, poi si aggiungono le spese."}
connectives: ["prima", "poi", "infine"]
terms: ["lordo", "netto", "imponibile", "IVA"]
model_it: "Parto dal lordo della merce. Poi tolgo gli sconti e ho il netto. Aggiungo le spese del venditore e ottengo l'imponibile. Infine calcolo l'IVA sull'imponibile e aggiungo le spese anticipate: ecco il totale."
:::

## Errori da evitare {mistakes}

::: mistake
group_it: "Percentuali"
wrong_it: "Sconti del 10% e del 5%: tolgo il 15%."
right_it: "Tolgo il 10%, poi il 5% sul prezzo già scontato."
why_it: "Ogni sconto si calcola sul prezzo che resta."
code: business_discounts_added
:::

::: mistake
group_it: "Percentuali"
wrong_it: "L'IVA si calcola sul lordo."
right_it: "L'IVA si calcola sull'imponibile."
why_it: "Prima togli lo sconto."
code: business_vat_on_gross
:::

::: mistake
group_it: "Il recinto"
wrong_it: "Le spese anticipate entrano nell'imponibile."
right_it: "Le spese anticipate si aggiungono dopo l'IVA."
why_it: "Sono spese del cliente."
code: business_documented_taxed
:::

## Prova tu {try}

::: try
intro_it: "Fai i conti sul quaderno, poi scrivi il risultato."
exercises:
  - text_it: "Imponibile 640,00 euro, IVA 22%. Quanto è l'IVA?"
    check:
      component: number
      prompt_it: "Quanto è l'IVA?"
      input_before: "IVA"
      answer: '140,80'
      errors:
        - {answer: '780,80', code: business_vat_on_gross, message_it: "Questo è imponibile più IVA."}
    solution_it: "640,00 per 0,22 fa 140,80."
  - text_it: "Netto 2.400,00 euro. Imballaggio del venditore 50,00 euro. Quanto è l'imponibile?"
    check:
      component: number
      prompt_it: "Quanto è l'imponibile?"
      input_before: "Imponibile"
      answer: '2450'
      errors:
        - {answer: '2400', code: business_costs_omitted, message_it: "Le spese del venditore stanno dentro."}
    solution_it: "2.400,00 + 50,00 = 2.450,00."
  - text_it: "40 sedie a 75,00 euro, sconti del 10% e del 5%. Quanto è il netto?"
    check:
      component: number
      prompt_it: "Quanto è il netto?"
      input_before: "Netto"
      answer: '2565'
      errors:
        - {answer: '2550', code: business_discounts_added, message_it: "Il secondo sconto va sul prezzo già scontato."}
    solution_it: "3.000,00 meno 300,00 fa 2.700,00. Meno il 5%, cioè 135,00, fa 2.565,00."
  - text_it: "Imponibile 1.000,00 euro, IVA 22%, spese anticipate 30,00 euro. Quanto è il totale?"
    check:
      component: number
      prompt_it: "Quanto è il totale?"
      input_before: "Totale"
      answer: '1250'
    solution_it: "1.000,00 + 220,00 + 30,00 = 1.250,00."
:::

## In sintesi {summary}

::: summary
- Prima togli gli sconti, uno dopo l'altro.
- L'imponibile è il netto più le spese del venditore.
- Il totale è imponibile, IVA e spese anticipate.
:::

::: schema table
alt_it: "Tabella con le righe di una fattura e il modo di calcolarle: netto, imponibile, IVA e totale."
caption_it: "Le righe di una fattura"
header: ["Riga", "Come si calcola"]
rows:
  - ["Netto", "Lordo meno gli sconti"]
  - ["Imponibile", "Netto più spese del venditore"]
  - ["IVA", "Imponibile per l'aliquota"]
  - ["Totale", "Imponibile, IVA e spese anticipate"]
:::
