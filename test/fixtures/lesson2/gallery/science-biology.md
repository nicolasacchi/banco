---
# Gallery of the biology figures (WAVE2 1.2, 5.4; D-312): `cell` (family science) and `nested` (family graph), drawn in CI with Chrome at 320, 390, 768
# and 1280 px (text size 18, 20, 26 px) with no finding at all (V6), and shown to the lead for the look gate. Invented content only; the parts, their
# names and jobs are the vetted table bio/cell_parts.
#   `cell`: a bacterium and an animal cell with the four shared parts lit (card 1), the comparison of an animal and a plant cell with "Solo le
#     differenze" (2), an animal cell with every organelle and the RNA's arrow from the nucleus (3), a plant cell named on a tap with notes (4), the
#     water of the vacuole (5), a bacterium with its tail (6); select over its parts, one and many (7, 8).
#   `nested`: the levels of the body with the organelles inside the cell and a focus that moves out (9); select over the levels (10).
schema: banco.lesson/2
key: ripasso.biology.gallery-science
kind: ripasso
subject: biology
title_it: "Galleria della biologia: cellule e livelli"
goals_it:
  - "**Riconoscere** le parti di una cellula"
  - "**Ordinare** i livelli del corpo"
skills: [biology.gallery-science]
refs:
  - {source: seconda-2025-26, line: 1, fragment: "la cellula", role: taught_in}
scope: studied
minutes: 20
calculator: false
why_it: "Mostra le figure della biologia, una dopo l'altra."
---

# La cellula

## Quattro cose in ogni cellula {idea icon=microscope id=parti-comuni}

Batteri, piante, animali: ogni cellula ha **membrana**, **citoplasma**, **DNA** e **ribosomi**.

::: diagram cell
alt_it: "A sinistra un batterio, a destra una cellula della guancia. Tutte e due hanno membrana, citoplasma, DNA e ribosomi. Solo la cellula della guancia ha un nucleo."
labels: all
cells:
  - {kind: bacterium, label_it: "Batterio", parts: [membrane, cytoplasm, nucleoid, ribosomes, wall]}
  - {kind: animal, label_it: "Cellula della guancia", parts: [membrane, cytoplasm, nucleus, ribosomes, mitochondria]}
notes:
  - {part: nucleoid, text_it: "Il DNA sta nel citoplasma: intorno non c'è un nucleo."}
states:
  - {op_it: "Le due cellule"}
  - {op_it: "Le quattro parti di tutte e due", highlight: [membrane, cytoplasm, dna, ribosomes]}
:::

## Tre cose in più nella cellula vegetale {idea icon=leaf id=vegetale}

Premi **Solo le differenze**: si accendono le parti che ha una cellula sola.

::: diagram cell
alt_it: "A sinistra una cellula animale, a destra una cellula vegetale. Solo la vegetale ha la parete, i cloroplasti e il grande vacuolo; i mitocondri ci sono in tutte e due."
labels: all
cells:
  - {kind: animal, label_it: "Cellula animale", parts: [membrane, cytoplasm, nucleus, ribosomes, mitochondria]}
  - {kind: plant, label_it: "Cellula vegetale", parts: [wall, membrane, cytoplasm, nucleus, ribosomes, mitochondria, chloroplasts, vacuole]}
notes:
  - {part: mitochondria, text_it: "Ci sono in tutte e due: anche le piante respirano."}
:::

## Dentro una cellula animale {idea icon=scan-eye id=animale}

L'originale del DNA resta nel nucleo: **esce una copia**.

::: diagram cell
alt_it: "Una cellula animale con il nucleo, i mitocondri, il reticolo endoplasmatico, l'apparato di Golgi, le vescicole e i ribosomi. Poi una freccia va dal nucleo ai ribosomi."
labels: all
cells:
  - {kind: animal, parts: [membrane, cytoplasm, nucleus, ribosomes, mitochondria, er, golgi, vesicles]}
states:
  - {op_it: "Il DNA sta nel nucleo", highlight: [dna]}
  - {op_it: "Una copia va ai ribosomi", paths: [{from: nucleus, to: ribosomes, label_it: "copia di RNA"}]}
:::

## Tocca e scopri {idea icon=eye id=tocca}

Tocca una parte della cellula: leggi il suo nome e che cosa fa.

::: diagram cell
alt_it: "Una cellula vegetale senza scritte: tocca una parte per leggere il suo nome e che cosa fa."
labels: tap
cells:
  - {kind: plant, parts: [wall, membrane, cytoplasm, nucleus, ribosomes, mitochondria, chloroplasts, vacuole, er, golgi, vesicles]}
notes:
  - {part: chloroplasts, text_it: "Nelle radici sotto terra i cloroplasti non ci sono."}
:::

## Perché l'insalata appassisce {idea icon=droplet id=acqua}

Il vacuolo pieno d'acqua spinge sulla parete: la cellula è tesa. Con poca acqua la membrana si stacca dalla parete.

::: diagram cell
alt_it: "Una cellula vegetale: il vacuolo pieno d'acqua si svuota e la membrana si stacca dalla parete."
labels: all
cells:
  - {kind: plant, parts: [wall, membrane, cytoplasm, nucleus, ribosomes, chloroplasts, vacuole]}
states:
  - {op_it: "Tanta acqua: la cellula è tesa", fill: {vacuole: high}}
  - {op_it: "Meno acqua", fill: {vacuole: mid}}
  - {op_it: "Poca acqua: la cellula si affloscia", fill: {vacuole: low}}
:::

## Un batterio che nuota {idea icon=microscope id=flagello}

::: diagram cell
alt_it: "Un batterio con la parete, la membrana, il DNA nel citoplasma, i ribosomi e il flagello, la coda che lo fa muovere."
labels: all
cells:
  - {kind: bacterium, parts: [wall, membrane, cytoplasm, nucleoid, ribosomes, flagellum]}
:::

## Trova il DNA {idea icon=dna id=trova-dna}

::: check select
prompt_it: "Tocca il DNA del batterio."
diagram:
  type: cell
  alt_it: "Un batterio senza scritte: un bordo doppio, dentro tanti puntini e un groviglio di filo."
  labels: none
  cells:
    - {kind: bacterium, parts: [membrane, cytoplasm, nucleoid, ribosomes, wall]}
targets: parts
pick: one
answer: ['c1.nucleoid']
errors:
  - {answer: ['c1.ribosomes'], message_it: "Quelli sono i ribosomi: tanti puntini. Il DNA è un filo lungo e aggrovigliato."}
  - {answer: ['c1.wall'], message_it: "È la parete, il bordo esterno. Il DNA sta dentro, nel citoplasma."}
explain_it: "Il DNA del batterio è il groviglio nel citoplasma. Intorno non c'è un nucleo."
:::

## Solo nella pianta {idea icon=leaf id=trova-vegetale}

::: check select
prompt_it: "Tocca le tre parti che una cellula animale non ha."
diagram:
  type: cell
  alt_it: "Una cellula di una foglia senza scritte: un bordo spesso, dentro dei fagioli, un cerchio e una grande sacca."
  labels: none
  cells:
    - {kind: plant, parts: [wall, membrane, cytoplasm, nucleus, ribosomes, mitochondria, chloroplasts, vacuole]}
targets: parts
pick: many
answer: ['c1.wall', 'c1.chloroplasts', 'c1.vacuole']
errors:
  - {answer: ['c1.wall', 'c1.chloroplasts', 'c1.mitochondria'], message_it: "I mitocondri ci sono anche nella cellula animale: anche le piante respirano."}
  - {answer: ['c1.membrane', 'c1.chloroplasts', 'c1.vacuole'], message_it: "La membrana ce l'hanno tutte le cellule."}
explain_it: "Parete, cloroplasti e grande vacuolo sono solo della cellula vegetale."
:::

# Dalla cellula all'organismo

## Dalla cellula all'organismo {idea icon=layers id=livelli}

Cellule simili formano un **tessuto**. Più tessuti formano un **organo**, più organi un **apparato**.

::: diagram nested
alt_it: "Cinque riquadri uno dentro l'altro: cellula muscolare del cuore, tessuto muscolare del cuore, cuore, apparato circolatorio, corpo umano. Dentro la cellula, tratteggiati, gli organuli."
levels:
  - {id: cell, label_it: "cellula", example_it: "cellula muscolare del cuore"}
  - {id: tissue, label_it: "tessuto", example_it: "tessuto muscolare del cuore"}
  - {id: organ, label_it: "organo", example_it: "cuore"}
  - {id: system, label_it: "apparato", example_it: "apparato circolatorio"}
  - {id: organism, label_it: "organismo", example_it: "corpo umano"}
inside: {label_it: "organuli", note_it: "stanno dentro la cellula: non sono un livello del corpo"}
states:
  - {focus: cell, op_it: "Una cellula"}
  - {focus: tissue, op_it: "Tante cellule simili"}
  - {focus: organ, op_it: "Più tessuti insieme"}
  - {focus: system, op_it: "Più organi, un solo compito"}
  - {focus: organism, op_it: "Il vivente intero"}
:::

## A che livello sta {idea icon=boxes id=trova-livello}

::: check select
prompt_it: "Il cervello: tocca il riquadro del suo livello."
diagram:
  type: nested
  alt_it: "Cinque riquadri uno dentro l'altro, senza i nomi dei livelli: ognuno ha il suo esempio."
  levels:
    - {id: cell, label_it: "cellula", example_it: "un neurone"}
    - {id: tissue, label_it: "tessuto", example_it: "tante cellule nervose vicine"}
    - {id: organ, label_it: "organo", example_it: "il cervello"}
    - {id: system, label_it: "apparato", example_it: "il sistema nervoso"}
    - {id: organism, label_it: "organismo", example_it: "un gatto"}
targets: levels
pick: one
answer: ['organ']
errors:
  - {answer: ['tissue'], message_it: "Un tessuto è fatto di cellule simili; il cervello è fatto di più tessuti."}
explain_it: "Il cervello è un organo: è fatto di più tessuti."
:::
