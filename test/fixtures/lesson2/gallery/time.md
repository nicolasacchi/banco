---
# Gallery of the family `time` (WAVE2 2.2, T4a), a lesson/2 file with invented content (history). It shows `timeline` on the scale of years:
# periods, events with notes, an approximate date, century bands, the zoom as states with a span whose value comes in the last one, two
# eras with no year 0, lanes, a long line with a step chosen by the width, and the measure tool. The tense scale is in time-english.md.
# `calendar` (reserved, W2-3) is not drawn yet. test/validation/lesson_time_gallery_test.rb renders it with Chrome at the viewports of
# lesson2.render and keeps no finding at all; test/system/lesson_time_gallery_test.rb takes the shots of the look gate.
schema: banco.lesson/2
key: ripasso.history.gallery-time
kind: ripasso
subject: history
title_it: "Galleria della linea del tempo: anni, periodi e righe"
goals_it:
  - "**Leggere** una linea del tempo con gli anni prima e dopo Cristo"
  - "**Contare** gli anni che passano tra due fatti"
skills: [history.gallery-time]
refs:
  - {source: seconda-2025-26, line: 31, fragment: "la linea del tempo", role: needed_by}
  - {source: prima-2025-26, line: 21, fragment: "gli anni e i secoli", role: taught_in}
scope: studied
minutes: 25
calculator: false
why_it: "Una linea del tempo mette i fatti nell'ordine giusto e mostra quanto sono lontani. Il contenuto è inventato."
---

## Un periodo e i suoi fatti {idea icon=hourglass id=periodo}

Guarda una cosa alla volta. Prima tutta la linea, poi un pezzo ingrandito. Tocca un punto per leggere la nota.

::: diagram timeline
alt_it: "Una linea del tempo dal 146 al 27 avanti Cristo con un periodo e quattro fatti inventati. Poi si ingrandisce il primo tratto e si conta il tempo tra due fatti."
scale: years
from: '-146'
to: '-27'
every: 10
centuries: true
periods:
  - {from: '-146', to: '-27', label_it: Il periodo di prova, role: senate}
events:
  - {id: e1, at: '-133', label_it: Primo fatto di prova, note_it: "Un fatto inventato, il primo.", role: cause}
  - {id: e2, at: '-100', label_it: Secondo fatto, role: rome}
  - {id: e3, at: '-82', label_it: Terzo fatto di prova, approx: true, role: effect}
  - {id: e4, at: '-44', label_it: Quarto fatto, role: effect, note_it: "Un fatto inventato, l'ultimo."}
spans:
  - {from: e1, to: e4, show_value: true}
states:
  - {op_it: "Tutta la linea"}
  - {from: '-146', to: '-100', periods: [{from: '-146', to: '-100', label_it: Il primo tratto, role: senate}], events: [{id: e1, at: '-133', label_it: Primo fatto di prova, role: cause}, {id: e2, at: '-100', label_it: Secondo fatto, role: rome}], spans: [{from: e1, to: e2}], op_it: "Un pezzo ingrandito"}
  - {from: '-146', to: '-100', periods: [{from: '-146', to: '-100', label_it: Il primo tratto, role: senate}], events: [{id: e1, at: '-133', label_it: Primo fatto di prova, role: cause}, {id: e2, at: '-100', label_it: Secondo fatto, role: rome}], spans: [{from: e1, to: e2, show_value: true}], op_it: "Quanti anni passano?"}
:::

## Non c'è l'anno zero {idea icon=calendar id=ere}

Dopo l'1 avanti Cristo viene l'1 dopo Cristo. Nessun anno in mezzo: da 27 a.C. a 14 d.C. passano **40 anni**, non 41.

::: diagram timeline
alt_it: "Una linea del tempo dal 50 avanti Cristo al 50 dopo Cristo con due fatti inventati. Tra i due passano quaranta anni."
scale: years
from: '-50'
to: '50'
every: 10
events:
  - {id: a, at: '-27', label_it: Fatto prima}
  - {id: b, at: '14', label_it: Fatto dopo, role: effect}
spans:
  - {from: a, to: b, show_value: true}
:::

Ora tocca tu. La linea non dice i nomi: guarda dove stanno i punti.

::: check select
prompt_it: "Tocca il punto del fatto che succede per primo."
targets: events
pick: one
answer: [e1]
explain_it: "Il primo punto a sinistra è il più lontano nel tempo."
diagram:
  type: timeline
  alt_it: "Una linea del tempo dal 150 al 20 avanti Cristo con tre punti, uno per ogni fatto. Tocca il punto giusto."
  scale: years
  from: '-150'
  to: '-20'
  every: 20
  events:
    - {id: e1, at: '-133', label_it: Primo}
    - {id: e2, at: '-100', label_it: Secondo}
    - {id: e3, at: '-44', label_it: Terzo}
:::

## Due righe, due popoli {idea icon=users id=righe}

Ogni riga ha i suoi fatti. Le fasce dicono in che secolo siamo.

::: diagram timeline
alt_it: "Una linea del tempo dal 300 al 100 avanti Cristo con due righe, Roma e altri popoli, e tre fatti inventati."
scale: years
from: '-300'
to: '-100'
centuries: true
lanes:
  - {id: rome, label_it: Roma}
  - {id: other, label_it: Altri popoli}
periods:
  - {from: '-300', to: '-200', label_it: Un periodo lungo di prova, role: other}
events:
  - {id: r1, at: '-264', label_it: Fatto a Roma, lane: rome, role: rome}
  - {id: r2, at: '-146', label_it: Un altro fatto a Roma, lane: rome, role: rome}
  - {id: o1, at: '-218', label_it: Fatto altrove, lane: other, role: other, approx: true}
:::

## Una storia lunga {idea icon=landmark id=lunga}

Quando la linea è lunga, i numeri sugli anni si fanno più rari.

::: diagram timeline
alt_it: "Una linea del tempo dal 753 avanti Cristo al 476 dopo Cristo con tre periodi inventati e tre fatti."
scale: years
from: '-753'
to: '476'
centuries: true
periods:
  - {from: '-753', to: '-509', label_it: Il primo periodo, role: rome}
  - {from: '-509', to: '-27', label_it: Il secondo periodo, role: senate}
  - {from: '-27', to: '476', label_it: Il terzo, role: princeps}
events:
  - {id: w1, at: '-753', label_it: Inizio, role: rome}
  - {id: w2, at: '-27', label_it: Svolta, role: princeps}
  - {id: w3, at: '476', label_it: Fine, role: effect}
spans:
  - {from: w1, to: w3, show_value: true}
:::

## Quanti anni passano? {idea icon=signpost id=misura}

Scegli due fatti. La linea dice quanti anni passano tra loro.

::: diagram timeline
alt_it: "Una linea del tempo dal 150 al 20 avanti Cristo con tre fatti inventati. Scegli due fatti per vedere quanti anni passano."
scale: years
from: '-150'
to: '-20'
every: 10
measure: true
events:
  - {id: m1, at: '-133', label_it: Primo fatto}
  - {id: m2, at: '-100', label_it: Secondo fatto}
  - {id: m3, at: '-44', label_it: Terzo fatto}
:::
