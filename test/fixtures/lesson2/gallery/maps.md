---
schema: banco.lesson/2
key: ripasso.geography.gallery-maps
kind: ripasso
subject: geography
title_it: "Galleria delle carte: gli strumenti per leggere il mondo"
goals_it:
  - "**Leggere** una carta con i suoi lati"
  - "**Vedere** perché la luce scalda meno lontano dall'equatore"
  - "**Capire** che salendo di quota fa più freddo"
skills: [geography.gallery-maps]
uses: []
refs:
  - {source: seconda-2025-26, line: 31, fragment: "carte geografiche e fusi climatici", role: needed_by}
scope: studied
minutes: 30
calculator: false
why_it: "Le carte, la luce del Sole e l'altezza dei monti spiegano il clima. Questa lezione di prova mostra gli strumenti, con contenuto inventato."
hero:
  type: map
  alt_it: "Una carta dell'America del Sud con il Brasile in evidenza, l'equatore e il tropico del Capricorno."
  base: south_america
  graticule: [equator, tropics]
  highlight:
    - {id: BRA, role: place}
---

# Le carte

## Una carta con i suoi lati {idea icon=globe id=carta}

In ogni carta il nord è in alto. A sinistra c'è l'ovest, a destra l'est. Le linee tratteggiate sono l'equatore e il tropico.

::: diagram map
alt_it: "Una carta dell'America del Sud con il Brasile in evidenza, due linee di latitudine, un fiume, una città e un punto sulla costa."
base: south_america
graticule: [equator, tropics]
highlight:
  - {id: BRA, role: place}
  - {id: ARG, role: temperate}
places:
  - {id: brasilia}
points:
  - {lat: '0', lon: '-51,1', label_it: "Macapá"}
lines:
  - {id: amazon}
states:
  - {op_it: "Il Brasile e il suo vicino a sud"}
  - {lines: [{kind: meridian, lon: '-46,6', label_it: "Tordesillas, 1494"}], op_it: "Una linea di longitudine"}
  - {highlight: [{id: BRA, role: place}], bands: [{from_lat: '-23,4', to_lat: '23,4', role: hot, label_it: "fascia calda"}], op_it: "La fascia calda"}
:::

## Il mondo a continenti {idea icon=earth id=mondo}

Un planisfero mostra tutti i continenti insieme. Le fasce di latitudine hanno trame diverse, non solo colori diversi.

::: diagram map
alt_it: "Il mondo con l'Europa e l'Africa in evidenza, le linee dei tropici e due fasce di latitudine con trame diverse."
base: world
graticule: [equator, tropics, polar_circles]
highlight:
  - {id: europe, role: temperate}
  - {id: africa, role: hot}
bands:
  - {from_lat: '-23,4', to_lat: '23,4', role: hot, label_it: "fascia calda"}
  - {from_lat: '23,4', to_lat: '66,6', role: temperate, label_it: "fascia temperata"}
:::

## L'Italia e le sue regioni {idea icon=map-pin id=italia}

Le regioni dell'Italia sono venti. Qui si vedono il Lazio e la Toscana, con Roma.

::: diagram map
alt_it: "L'Italia con le venti regioni, il Lazio e la Toscana in evidenza con trame diverse e la città di Roma segnata."
base: italy
highlight:
  - {id: lazio, role: place}
  - {id: toscana, role: temperate, pattern: dots}
places:
  - {id: rome}
:::

## Il Mediterraneo antico {idea icon=landmark id=antico}

I confini antichi non si conoscono con precisione: la carta dice sempre "Confini approssimativi". Muovi l'anno e guarda che cosa cambia.

::: diagram map
alt_it: "Il Mediterraneo antico: tra il 264 e il 133 prima di Cristo Roma conquista nuove terre, che appaiono man mano sulla carta."
base: mediterraneo_antico
places:
  - {id: roma}
  - {id: cartagine}
highlight:
  - {id: italia, role: place}
slider: {from: '-264', to: '-133'}
regions_since:
  - {id: sicilia, since: '-241', role: place}
  - {id: sardegna-corsica, since: '-238', role: place}
  - {id: hispania, since: '-197', role: place}
  - {id: africa-proconsolare, since: '-146', role: place}
  - {id: macedonia, since: '-146', role: place}
:::

## Tanti luoghi, i numeri {idea icon=map id=numeri}

Se i nomi non entrano nella carta, ogni luogo ha un numero. L'elenco sotto la carta dice quale è quale.

::: diagram map
alt_it: "Il Mediterraneo antico con dodici luoghi segnati da numeri che si leggono nell'elenco sotto la carta."
base: mediterraneo_antico
places:
  - {id: roma}
  - {id: cartagine}
  - {id: atene}
  - {id: alessandria}
  - {id: bisanzio}
  - {id: gerusalemme}
  - {id: ravenna}
  - {id: milano}
  - {id: azio}
  - {id: canne}
  - {id: zama}
  - {id: alesia}
:::

## Un percorso sulla carta {idea icon=route id=percorso}

Una linea collega i luoghi di un viaggio, nell'ordine in cui si fanno.

::: diagram map
alt_it: "Il Mediterraneo antico con il percorso di un generale dalla Gallia a Roma, passando per il fiume Rubicone."
base: mediterraneo_antico
places:
  - {id: rubicone}
  - {id: roma}
routes:
  - {via: [gallia, rubicone, roma], role: place, label_it: "Cesare, 49 a.C."}
:::

# La luce e l'altezza

## La stessa luce, più terreno {idea icon=sun id=luce}

Lontano dall'equatore la luce arriva storta e si spalma su più terreno. Per questo scalda meno.

::: diagram insolation
alt_it: "La Terra vista di lato con raggi paralleli del Sole su tre latitudini: più lontano dall'equatore la stessa luce copre più terreno."
latitudes: ['0', '30', '60']
subsolar: '0'
stepper: true
spread: true
states:
  - {subsolar: '0', op_it: "Equinozio"}
  - {subsolar: '23,4', op_it: "21 giugno"}
  - {subsolar: '-23,4', op_it: "21 dicembre"}
:::

## Salire in quota {idea icon=mountain-snow id=quota}

Ogni mille metri si perdono circa sei gradi. Per questo le cime vicine all'equatore hanno la neve.

::: diagram cross_section
alt_it: "La sezione di un vulcano ideale all'equatore con le fasce di vegetazione e la temperatura che scende con la quota."
x: {to: '200', unit: km}
points: [['0', '0'], ['80', '3000'], ['100', '5000'], ['120', '3000'], ['200', '0']]
features:
  - {at: '100', label_it: "cima", kind: peak}
  - {at: '20', label_it: "pianura", kind: plain}
belts:
  - {from_alt: '0', to_alt: '1000', label_it: "foresta", role: temperate}
  - {from_alt: '1000', to_alt: '3000', label_it: "foresta di montagna", role: place}
  - {from_alt: '3000', to_alt: '4500', label_it: "prato alto", role: cold}
  - {from_alt: '4500', to_alt: '5000', label_it: "ghiaccio", role: arid}
lapse: {base_temp: '26', per_km: '6'}
stepper: true
:::

## In sintesi {summary}

::: summary
- Il nord è in alto, l'ovest a sinistra, l'est a destra.
- Una trama aiuta quando i colori non bastano.
- Più lontano dall'equatore la luce copre più terreno.
- Salendo di mille metri si perdono circa sei gradi.
:::

::: schema flow
alt_it: "Dalla latitudine alla temperatura: più lontano dall'equatore la luce copre più terreno, quindi scalda meno e fa più freddo."
nodes:
  - {id: s, kind: step, text_it: "Più lontano dall'equatore"}
  - {id: a, kind: step, text_it: "La luce arriva storta"}
  - {id: b, kind: step, text_it: "Copre più terreno"}
  - {id: e, kind: end, text_it: "Scalda meno"}
edges:
  - [s, a]
  - [a, b]
  - [b, e]
:::
