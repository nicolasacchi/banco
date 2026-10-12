---
schema: banco.lesson/2
key: ripasso.geography.gallery-chart
kind: ripasso
subject: geography
title_it: "Galleria dei grafici: climogramma, barre e seggi"
goals_it:
  - "**Leggere** un climogramma: pioggia, temperatura e mesi aridi"
  - "**Usare** la barra e la scala doppia per parti e percentuali"
skills: [geography.gallery-chart]
uses: []
refs:
  - {source: seconda-2025-26, line: 31, fragment: "climi e ambienti del mondo", role: needed_by}
  - {source: prima-2025-26, line: 21, fragment: "carte e grafici", role: taught_in}
scope: studied
minutes: 25
calculator: false
why_it: "Un grafico dice molte cose in poco spazio. Qui ne provi tre tipi, con numeri veri e con numeri inventati."
hero:
  type: climograph
  alt_it: "Il climogramma di Brasília: barre per la pioggia di ogni mese, una linea per la temperatura, i mesi aridi segnati."
  station: geo/stations.brasilia
  show: [bars, line, arid]
---

# Il clima in un grafico

## Prima la pioggia, poi la linea {idea icon=cloud-rain id=pioggia}

Guarda **una cosa alla volta**. Prima la pioggia, poi la temperatura.

::: diagram climograph
# the type `climograph`: stations, states, the read cursor
alt_it: "Il climogramma di Winnipeg, con la pioggia, poi la temperatura, poi il mese più caldo e quello più freddo."
station: geo/stations.winnipeg
show: [bars, line, range, total]
read: true
states:
  - {show: [bars], op_it: "Prima la pioggia"}
  - {show: [bars, line], op_it: "Poi la temperatura"}
  - {show: [bars, line, range, total], op_it: "Il più caldo, il più freddo, il totale"}
:::

## Un mese è arido {idea icon=sun-dim id=arido}

Un mese è **arido** se la barra sta sotto la linea. A Brasília succede da maggio a settembre.

::: diagram climograph
alt_it: "Il climogramma di Brasília: i mesi da maggio a settembre hanno la barra sotto la linea e sono tratteggiati."
station: geo/stations.brasilia
show: [bars, line, arid]
states:
  - {show: [bars, line], op_it: "Barre e linea"}
  - {show: [bars, line, arid], op_it: "I mesi aridi"}
:::

## Quando piove tantissimo {idea icon=trees id=monsone}

Sopra i 100 mm la scala cambia. A Mumbai piove moltissimo, ma per cinque mesi quasi niente.

::: diagram climograph
alt_it: "Il climogramma di Mumbai: sette mesi aridi e tre mesi di pioggia fortissima, che sale nella fascia sopra i cento millimetri."
station: geo/stations.mumbai
show: [bars, line, arid, total]
:::

## Sotto l'equatore le stagioni cambiano {idea icon=globe id=sud}

La linea tratteggiata è la città del sud: l'estate è a gennaio.

::: diagram climograph
alt_it: "Due linee di temperatura: Roma, con il caldo a luglio, e Città del Capo tratteggiata, con il caldo a gennaio."
station: geo/stations.rome
show: [line]
compare: {station: geo/stations.cape_town}
:::

# Le quantità

## Le parti di una barra {idea icon=coins id=parti}

Le parti sono larghe come i loro valori. Una parte nascosta è quello che resta.

::: diagram bar_model
# the type `bar_model`: the view parts here, the view percent below
alt_it: "Una barra divisa in tre parti: centoventi, duecento e il resto, che insieme fanno quattrocentottanta in tutto."
view: parts
bars:
  - label_it: "Vendite"
    parts:
      - {value: '120', label_it: "primo"}
      - {value: '200', label_it: "secondo"}
      - {value: '160', label_it: "resto", hidden: true}
total: {value: '480', label_it: "in tutto"}
:::

## Euro sopra, percentuale sotto {idea icon=coins id=percento}

Il cento per cento è la base. Il ventidue per cento è una parte della base.

::: diagram bar_model
alt_it: "Una scala doppia: sopra gli euro, sotto la percentuale, con il cento per cento a milleottocentosessanta e il ventidue per cento a quattrocentonove virgola venti."
view: percent
base: '1860,00'
unit: euro
marks:
  - {pct: '22', label_it: "parte"}
  - {pct: '122', label_it: "base e parte"}
chain:
  - {pct: '90'}
  - {pct: '95'}
:::

## Chi vota {idea icon=users id=seggi}

Ogni punto è un seggio. Pieno vuol dire sì, vuoto vuol dire no, piccolo vuol dire assente.

::: diagram seats
# the type `seats`: the hemicycle with sliders here, the grid below
alt_it: "Una camera inventata di quattrocento seggi in semicerchio: i presenti sono tra duecentottanta e trecentodieci e servono almeno centoquarantuno voti a favore."
layout: hemicycle
seats: 400
present: 300
yes: 170
thresholds: [legal_number, present_majority]
try: {present: [280, 310], yes: [150, 200]}
:::

::: diagram seats
alt_it: "Una griglia di cento seggi, dieci per riga: sessanta sono di un gruppo e venticinque di un altro."
# still to show, in batch w2-2: `chart` and `scale`
layout: grid
seats: 100
groups:
  - {label_it: "Primo gruppo", seats: 60}
  - {label_it: "Secondo gruppo", seats: 25}
:::
