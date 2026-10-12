---
# Gallery of the family `graph` (WAVE2 2.1, T4b), a lesson/2 file with invented content. It shows `network` (pair, hub with kind chips,
# fan, triangle, row, grid; states with badges, holds, hide and the crowd; the note on a node), `chain` (line, fan, ring; "Togli una
# causa"; a return arc; a link that is not causal; states that show), and the line layout of `flow` (the token, the second lane, the
# returns). `nested` (draft, W2-2) is not drawn yet. The select mode is drawn by the figure tests until the `select` check lands (T1).
# test/validation/lesson_graph_gallery_test.rb renders it with Chrome at the viewports of lesson2.render and keeps no finding at all.
schema: banco.lesson/2
key: ripasso.law_economics.gallery-graph
kind: ripasso
subject: law_economics
title_it: "Galleria dei grafi: relazioni, cause e percorsi"
goals_it:
  - "**Vedere** ogni figura della famiglia"
skills: [law_economics.gallery]
refs:
  - {source: gallery-2026, line: 1, fragment: "grafi", role: taught_in}
scope: studied
minutes: 30
calculator: false
why_it: "Una galleria serve a guardare le figure. Il contenuto è inventato."
---

## Chi deve che cosa a chi {idea icon=handshake id=relazioni-coppia}

Una coppia di persone, due frecce, e uno stato che mostra i ruoli. Tocca il nome di Anna per leggere la nota.

::: diagram network
alt_it: 'Anna vende la bicicletta a Paolo. Una freccia va da Anna a Paolo: consegna la bicicletta. Una va da Paolo ad Anna: paga 150 euro.'
layout: pair
nodes:
- {id: anna, label_it: 'Anna, venditrice', icon: user, role: duty, note_it: Deve consegnare la bicicletta., badge_it: debitrice}
- {id: paolo, label_it: 'Paolo, compratore', icon: user, role: right}
edges:
- {from: anna, to: paolo, kind: owes, label_it: consegna la bicicletta, what: goods}
- {from: paolo, to: anna, kind: pays, label_it: paga 150 euro, what: money}
states:
- op_it: Prima si accordano
  edges: []
- op_it: Poi si scambiano
  badges:
  - {node: anna, badge_it: debitrice}
  - {node: paolo, badge_it: creditore}
:::


## Chi elegge chi {idea icon=vote id=relazioni-centro}

Il Senato è al centro. I tipi di freccia si possono scegliere uno per uno.

::: diagram network
alt_it: 'Nel Parlamento d''esempio il Senato è al centro: il popolo elegge i senatori, i senatori danno la fiducia al governo e votano le leggi.'
layout: hub
centre: sen
filter: true
nodes:
- {id: sen, label_it: Senato, icon: landmark, role: legislative, note_it: Qui si votano le leggi.}
- {id: pop, label_it: Popolo, icon: users, role: people}
- {id: gov, label_it: Governo, icon: briefcase, role: executive}
- {id: pre, label_it: Presidente, icon: shield, role: guarantee}
- {id: gio, label_it: Giudici, icon: gavel, role: judicial}
edges:
- {from: pop, to: sen, kind: elects}
- {from: sen, to: gov, kind: trusts}
- {from: sen, to: pop, kind: votes_laws, label_it: vota le leggi per tutti}
- {from: pre, to: gov, kind: appoints}
- {from: gio, to: sen, kind: advises}
:::


## Tanti verso uno {idea icon=package id=relazioni-ventaglio}

Tre clienti, un solo negozio.

::: diagram network
alt_it: 'Tre clienti ordinano al negozio: ognuno manda un ordine e il negozio risponde con la merce.'
layout: fan
into: neg
nodes:
- {id: c1, label_it: Cliente uno, icon: users}
- {id: c2, label_it: Cliente due, icon: users}
- {id: c3, label_it: Cliente tre, icon: users}
- {id: neg, label_it: Negozio, icon: building-2}
edges:
- {from: c1, to: neg, kind: orders, what: order}
- {from: c2, to: neg, kind: orders, what: order}
- {from: c3, to: neg, kind: orders, what: order}
:::


## Tre ruoli {idea icon=scale id=relazioni-triangolo}

Chi presta, chi riceve e chi garantisce.

::: diagram network
alt_it: 'Tre persone in un prestito: chi presta, chi riceve i soldi e chi garantisce. Le frecce dicono chi deve che cosa a chi.'
layout: triangle
nodes:
- {id: cre, label_it: Creditore, icon: briefcase, role: right}
- {id: deb, label_it: Debitore, icon: users, role: duty}
- {id: ter, label_it: Garante, icon: user, role: guarantee}
edges:
- {from: deb, to: cre, kind: owes, label_it: restituisce, what: money}
- {from: ter, to: cre, kind: promises, label_it: garantisce, what: promise}
:::


## Quattro tappe di una merce {idea icon=truck id=relazioni-riga}

Le frecce vanno da sinistra a destra.

::: diagram network
alt_it: 'Quattro tappe di una merce: il produttore la manda al grossista, il grossista al negozio, il negozio al cliente.'
layout: row
nodes:
- {id: p, label_it: Produttore, icon: route}
- {id: g, label_it: Grossista, icon: route}
- {id: n, label_it: Negozio, icon: route}
- {id: c, label_it: Cliente, icon: route}
edges:
- {from: p, to: g, kind: sends, what: goods}
- {from: g, to: n, kind: sends, what: goods}
- {from: n, to: c, kind: gives, what: goods}
:::


## Quattro poteri {idea icon=gavel id=relazioni-griglia}

Chi comanda, chi vota, chi giudica, chi garantisce.

::: diagram network
alt_it: 'Quattro poteri che si controllano: chi comanda, chi vota, chi giudica e chi garantisce. Le frecce mostrano chi blocca chi.'
layout: grid
nodes:
- {id: a, label_it: Chi comanda, icon: crown}
- {id: b, label_it: Chi vota, icon: vote}
- {id: c, label_it: Chi giudica, icon: gavel}
- {id: d, label_it: Chi garantisce, icon: shield}
edges:
- {from: a, to: b, kind: commands}
- {from: c, to: a, kind: vetoes}
- {from: d, to: c, kind: appoints}
:::


## Il re cede un potere {idea icon=crown id=relazioni-poteri}

Tutti gli altri devono obbedire. Nel secondo stato il potere passa al consiglio.

::: diagram network
alt_it: 'Il re da solo, poi il re e il consiglio: nel secondo stato il re cede un potere e il consiglio ne riceve uno.'
layout: pair
everyone: true
nodes:
- {id: re, label_it: Il re, icon: crown, role: legislative}
- {id: con, label_it: Il consiglio, icon: users, role: people}
holds:
- node: re
  items_it: [fa le leggi, guida l'esercito]
edges:
- {from: everyone, to: re, kind: owes, label_it: obbedisce}
states:
- {op_it: Il re ha tutto}
- op_it: Il re cede un potere
  holds:
  - node: re
    items_it: [guida l'esercito]
  - node: con
    items_it: [fa le leggi]
  edges:
  - {from: everyone, to: re, kind: owes, label_it: obbedisce}
  - {from: everyone, to: con, kind: owes, label_it: obbedisce}
- op_it: Solo il re
  hide: [con]
  edges:
  - {from: everyone, to: re, kind: owes, label_it: obbedisce}
  holds:
  - node: re
    items_it: [fa le leggi, guida l'esercito]
:::


## Una catena che cresce {idea icon=git-branch id=catena-linea}

Una causa dopo l'altra. Puoi togliere una causa e vedere che cosa perde la sua ragione.

::: diagram chain
alt_it: 'Una catena di cause: una siccità rovina il raccolto, per questo il pane costa di più e la gente protesta in piazza.'
layout: line
remove: true
nodes:
- {id: a, kind: cause, area: environment, text_it: Una lunga siccità}
- {id: b, kind: cause, area: economy, text_it: Il raccolto è scarso}
- {id: c, kind: effect, area: economy, text_it: Il pane costa di più}
- {id: d, kind: effect, area: society, text_it: La gente protesta}
links:
- {from: a, to: b, word: porta a}
- {from: b, to: c, word: per questo}
- {from: c, to: d, word: quindi}
:::


## Tante cause, un solo fatto {idea icon=git-branch id=catena-ventaglio}

Cinque cause portano a un fatto. Togli una causa alla volta.

::: diagram chain
alt_it: 'Cinque cause portano alla fine di un regno d''esempio: guerre lontane, terre ai ricchi, poveri in città, soldati fedeli al generale, consiglio fermo.'
layout: fan
remove: true
nodes:
- {id: c1, kind: cause, area: military, text_it: Guerre lunghe e lontane}
- {id: c2, kind: cause, area: economy, text_it: Terre in mano ai ricchi}
- {id: c3, kind: cause, area: society, text_it: Contadini poveri in città}
- {id: c4, kind: cause, area: military, text_it: Soldati fedeli al generale}
- {id: c5, kind: cause, area: politics, text_it: Il consiglio blocca le riforme}
- {id: ev, kind: event, text_it: Fine del regno}
- {id: e1, kind: effect, text_it: Nasce un impero}
links:
- {from: c1, to: c2, word: quindi}
- {from: c2, to: c3, word: quindi}
- {from: c3, to: c4, word: quindi}
- {from: c4, to: ev}
- {from: c5, to: ev}
- {from: ev, to: e1, word: porta a}
states:
- show: [c1]
  op_it: Si comincia dalle guerre
- show: [c1, c2, c3]
  op_it: La terra cambia padrone
- show: [c1, c2, c3, c4, c5, ev, e1]
  op_it: Tutto insieme
:::


## Un giro che ricomincia {idea icon=repeat id=catena-anello}

Quattro tappe e poi di nuovo la prima.

::: diagram chain
alt_it: 'Il ciclo dell''acqua in quattro tappe: evaporazione, nuvole, pioggia, fiumi. Poi tutto ricomincia dall''evaporazione.'
layout: ring
nodes:
- {id: s1, kind: stage, text_it: L'acqua evapora}
- {id: s2, kind: stage, text_it: Si formano le nuvole}
- {id: s3, kind: stage, text_it: Cade la pioggia}
- {id: s4, kind: stage, text_it: I fiumi tornano al mare}
links:
- {from: s1, to: s2}
- {from: s2, to: s3}
- {from: s3, to: s4}
- {from: s4, to: s1}
:::


## Un giro vizioso e una freccia solo prima {idea icon=undo-2 id=catena-ritorno}

La prima catena torna al suo inizio. La seconda ha una causa che viene solo prima.

::: diagram chain
alt_it: 'Un giro vizioso: i prezzi salgono, i salari salgono, e i prezzi salgono ancora. L''ultima freccia torna al primo fatto.'
layout: line
nodes:
- {id: a, kind: event, text_it: I prezzi salgono}
- {id: b, kind: effect, text_it: Servono salari più alti}
- {id: c, kind: effect, text_it: Le imprese spendono di più}
links:
- {from: a, to: b, word: porta a}
- {from: b, to: c, word: quindi}
- {from: c, to: a, back: true, word: porta a}
:::


## Il viaggio di una lettera {idea icon=route id=percorso-lettera}

Un segnalino che cammina, una strada più corta e un ritorno.

::: diagram flow
alt_it: 'Il viaggio di una lettera: imbucata, ufficio postale, smistamento, portalettere, casa. Se l''indirizzo è sbagliato la lettera torna indietro.'
layout: line
nodes:
- {id: imb, kind: step, text_it: Imbucata, icon: file-text}
- {id: uff, kind: step, text_it: Ufficio postale, icon: building-2, actor_it: un impiegato la timbra}
- {id: smi, kind: step, text_it: Smistamento, icon: route, actor_it: le macchine la dividono per città}
- {id: por, kind: step, text_it: Portalettere, icon: clock, actor_it: la porta all'indirizzo}
- {id: cas, kind: end, text_it: A casa, icon: key-round}
branch:
  from: imb
  to: smi
  label_it: Posta prioritaria
  nodes:
  - {id: pri, kind: step, text_it: Corsia veloce, icon: stamp}
returns:
- {from: por, to: smi, label_it: indirizzo sbagliato}
token: imb
states:
- token: uff
  via: [imb, uff]
  op_it: La lettera arriva all'ufficio
- token: smi
  via: [uff, smi]
  op_it: Le macchine la smistano
- token: por
  via: [smi, por]
  op_it: Il portalettere la prende
- token: smi
  via: [por, smi]
  op_it: 'L''indirizzo è sbagliato: torna indietro'
:::


## Un percorso corto {idea icon=route id=percorso-corto}

Tre tappe e basta.

::: diagram flow
alt_it: 'Un percorso con tre tappe: si parte, si passa dal controllo, si arriva. Il segnalino sta alla partenza.'
layout: line
nodes:
- {id: a, kind: step, text_it: Partenza, icon: route}
- {id: b, kind: step, text_it: Controllo, icon: shield}
- {id: c, kind: end, text_it: Arrivo, icon: key-round}
token: a
:::

