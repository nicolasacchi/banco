---
# A bilingual spanish lesson with the figures of the pilot's tilde lesson (D-402): a sentence with states (hero and block), word_parts with states and with the
# stress legend, a mirror, a flow with labelled edges (`edges_it`), a table figure, a select check on syllables and a normalized_text check with its input
# fragments. test/validation/lesson_render_translation_test.rb draws it in Chrome and expects no translation finding.
schema: banco.lesson/2
bilingual: true
key: lezione.spanish.figures-fixture
kind: lezione
subject: spanish
title_es: "La tilde y las preguntas"
title_it: "La tilde e le domande"
goals_es:
  - "**Encontrar** la sílaba donde suena la voz"
goals_it:
  - "**Trovare** la sillaba dove batte la voce"
skills: [spanish.ser-estar]
refs:
  - {source: gallery-2026, line: 1, fragment: "ser y estar", role: taught_in}
scope: studied
minutes: 30
calculator: false
book_it: "Cerca «acentuación» sul libro."
why_es: "Cada tilde cuenta. Con las preguntas hablas de ti y de otros."
why_it: "Ogni tilde conta. Con le domande parli di te e degli altri."
glossary:
  - {term_es: "sílaba", term_it: "sillaba", def_es: "Un trozo de palabra que se dice de una vez.", def_it: "Un pezzo di parola che si dice in una volta sola."}
hero:
  type: sentence
  layout: line
  alt_es: "Una pregunta y su respuesta. Por qué lleva tilde y porque no la lleva."
  alt_it: "Una domanda e la sua risposta. Por qué ha la tilde e porque non ce l'ha."
  text_es: "¿Por qué estudias español?"
  parts:
    - {id: q, text_es: "Por qué", role: highlight, label_es: "pregunta: tilde", label_it: "chiede: tilde"}
    - {id: v, text_es: "estudias", role: verb, label_es: "tú estudias", label_it: "studi"}
    - {id: x, text_es: "español", role: muted, label_es: "la lengua", label_it: "la lingua"}
  states:
    - {op_es: "La pregunta", op_it: "La domanda", next_label_es: "La respuesta", next_label_it: "La risposta"}
    - text_es: "Porque me gusta"
      op_es: "La respuesta"
      op_it: "La risposta"
      parts:
        - {id: q, text_es: "Porque", role: highlight, label_es: "responde: sin tilde", label_it: "risponde: niente tilde"}
        - {id: v, text_es: "me gusta", role: verb, label_es: "me agrada", label_it: "mi piace"}
---

## En cada palabra la voz suena en una sílaba {idea short="La voz" short_it="La voce" it="In ogni parola la voce batte su una sillaba" icon=volume-2 id=voz}

Como en italiano, la voz suena más fuerte en una [[g:sílaba]]. Cuenta desde el final: última, penúltima.

::: it
Come in italiano, la voce batte più forte su una [[g:sillaba]]. Conta dalla fine: ultima, penultima.
:::

::: diagram word_parts
alt_es: "Tres palabras divididas en sílabas. En sillón suena la última, en ventana la penúltima."
alt_it: "Tre parole divise in sillabe. In sillón batte l'ultima, in ventana la penultima."
caption_es: "La sílaba fuerte tiene un punto."
caption_it: "La sillaba forte ha un punto."
view: syllables
words:
  - {form_es: 'sillón', label_es: "última", label_it: "ultima"}
  - {form_es: 'ventana', label_es: "penúltima", label_it: "penultima"}
  - {form_es: 'pájaro', label_es: "antepenúltima", label_it: "terzultima"}
  - {form_es: 'plátano', label_it: "banana"}
:::

::: check select
prompt_es: "Dilo en voz alta: camino. Toca la sílaba donde suena la voz."
prompt_it: "Dillo a voce alta: camino, cammino. Tocca la sillaba dove batte la voce."
targets: syllables
pick: one
answer: [w1s2]
errors:
  - {answer: [w1s1], message_es: "No suena en la primera.", message_it: "Non batte sulla prima."}
explain_es: "Ca-mi-no: suena en mi, la penúltima."
explain_it: "Ca-mi-no: batte su mi, la penultima."
diagram:
  type: word_parts
  alt_es: "La palabra camino dividida en sílabas."
  alt_it: "La parola camino divisa in sillabe."
  view: syllables
  words:
    - {form_es: 'camino'}
:::

## El plural: cuenta otra vez {idea short="El plural" short_it="Il plurale" it="Al plurale rifai il conto" icon=pen-line id=plural}

Con -es el plural tiene una sílaba más.

::: it
Con -es il plurale ha una sillaba in più.
:::

::: diagram word_parts
alt_es: "Corazón lleva tilde. Corazones no la lleva. Origen no la lleva; orígenes sí la lleva."
alt_it: "Corazón ha la tilde. Corazones non ce l'ha. Origen non ce l'ha; orígenes sì."
view: syllables
words:
  - {form_es: 'corazón', label_es: "última: tilde", label_it: "ultima: tilde"}
  - {form_es: 'origen', label_es: "penúltima: sin tilde", label_it: "penultima: niente tilde"}
states:
  - {op_es: "El singular", op_it: "Il singolare"}
  - op_es: "El plural con -es"
    op_it: "Il plurale con -es"
    words:
      - {form_es: 'corazones', label_es: "penúltima: sin tilde", label_it: "penultima: niente tilde"}
      - {form_es: 'orígenes', label_es: "antepenúltima: tilde", label_it: "terzultima: tilde"}
:::

::: legend
roles:
  - {role: stress, note_es: "Aquí suena la voz", note_it: "Qui batte la voce", question_es: "¿Dónde suena?", question_it: "Dove batte?"}
  - {role: verb, note_es: "El verbo", note_it: "Il verbo"}
:::

::: check normalized_text
prompt_es: "Escribe el plural: un botón, dos …"
prompt_it: "Scrivi il plurale: un botón, dos …"
input_before: "dos"
input_after: "bonitos."
answer: "botones"
errors:
  - {answer: "botónes", message_es: "Sin tilde en el plural.", message_it: "Niente tilde al plurale."}
explain_es: "Botones: suena en la penúltima y acaba en s."
explain_it: "Botones: batte sulla penultima e finisce in s."
:::

::: check choice
prompt_es: "¿Qué palabra completa la frase?"
prompt_it: "Quale parola completa la frase?"
sentence_es: "El libro de ___ es bonito."
translate_material: false
options:
  - {id: a, text_es: "tú"}
  - {id: b, text_es: "tu"}
answer: a
errors:
  - {answer: b, message_es: "Tu sin tilde es «tuyo», no «de ti».", message_it: "Tu senza tilde è «tuo», non «di te»."}
explain_es: "Tú es la persona: de ti."
explain_it: "Tú è la persona: di te."
:::

## Qué o cuál {idea short="Qué o cuál" short_it="Qué e cuál" it="Qué e cuál" icon=languages id=que}

Delante de un nombre se dice qué.

::: it
Davanti a un nome si dice qué.
:::

::: diagram mirror
alt_es: "Italiano arriba, español abajo. Quale libro leggi es Qué libro lees; quale preferisci es Cuál prefieres."
alt_it: "Italiano sopra, spagnolo sotto. Quale libro leggi è Qué libro lees; quale preferisci è Cuál prefieres."
rows:
  - pieces_it: ['Quale', 'libro', 'leggi']
    pieces_es: ['Qué', 'libro', 'lees']
    links: [[0, 0, shift], [1, 1, same], [2, 2, same]]
    notes:
      - {side: es, piece: 0, note_es: "delante de un nombre: qué", note_it: "davanti a un nome: qué"}
  - pieces_it: ['Quale', 'preferisci']
    pieces_es: ['Cuál', 'prefieres']
    links: [[0, 0, same], [1, 1, same]]
    notes:
      - {side: es, piece: 0, note_es: "sin nombre detrás: cuál", note_it: "senza un nome dopo: cuál"}
:::

::: diagram sentence
alt_es: "Tres frases. Tú tienes tu libro; Él coge el tren; Mi hermano piensa en mí."
alt_it: "Tre frasi. Tú tienes tu libro; Él coge el tren; Mi hermano piensa en mí."
layout: line
text_es: "Tú tienes tu dinero"
parts:
  - {id: a, text_es: "Tú", role: highlight, label_es: "tú: la persona", label_it: "tú: tu, la persona"}
  - {id: v, text_es: "tienes", role: verb, label_es: "tienes", label_it: "hai"}
  - {id: b, text_es: "tu", role: muted, label_es: "tu: de ti", label_it: "tu: tuo"}
  - {id: n, text_es: "dinero", role: muted, label_es: "el dinero", label_it: "i soldi"}
states:
  - {op_es: "Tú y tu", op_it: "Tú e tu"}
  - text_es: "Él coge el tren triste"
    op_es: "Él y el"
    op_it: "Él ed el"
    parts:
      - {id: a, text_es: "Él", role: highlight, label_es: "él: ese chico", label_it: "él: lui"}
      - {id: v, text_es: "coge", role: verb, label_es: "toma", label_it: "prende"}
      - {id: b, text_es: "el", role: muted, label_es: "el: artículo", label_it: "el: il"}
      - {id: n, text_es: "tren triste", role: muted, label_es: "un tren", label_it: "un treno"}
:::

## La regla en un esquema {idea short="Esquema" short_it="Schema" it="La regola in uno schema" icon=footprints id=esquema}

::: schema flow
alt_es: "Cómo decides la tilde. Buscas dónde suena la voz. Si es la última, tilde con vocal, n o s. Si es la penúltima, tilde con otras consonantes."
alt_it: "Come decidi la tilde. Cerchi dove batte la voce. Se è l'ultima, tilde con vocale, n o s. Se è la penultima, tilde con le altre consonanti."
nodes:
  - {id: s, kind: step, text_es: "Busca dónde suena la voz", text_it: "Cerca dove batte la voce"}
  - {id: q, kind: decision, text_es: "¿En qué sílaba?", text_it: "Su quale sillaba?"}
  - {id: a, kind: end, text_es: "Tilde con vocal, n o s", text_it: "Tilde con vocale, n o s"}
  - {id: b, kind: end, text_es: "Siempre tilde", text_it: "Sempre la tilde"}
edges:
  - [s, q]
  - [q, a, "última"]
  - [q, b, "penúltima"]
edges_it:
  - ~
  - "ultima"
  - "penultima"
:::

::: schema table
alt_es: "Tabla de palabras: la palabra y dónde suena la voz."
alt_it: "Tabella di parole: la parola e dove batte la voce."
header: ["Palabra", "La voz"]
header_it: ["Parola", "La voce"]
rows:
  - ["jamón", "la última"]
  - ["ángel", "la penúltima"]
rows_it:
  - ["prosciutto", "l'ultima"]
  - ["angelo", "la penultima"]
:::

## Prueba tú {try short="Prueba" short_it="Prova tu" it="Prova tu" icon=pen-line id=try}

::: try
intro_es: "Elige la forma correcta."
intro_it: "Scegli la forma giusta."
exercises:
  - text_es: "El libro de ___ es bonito."
    text_it: "Il libro di ___ è bello."
    check:
      component: choice
      prompt_es: "¿Qué palabra va bien?"
      prompt_it: "Quale parola va bene?"
      options:
        - {id: a, text_es: "tú", text_it: "tu"}
        - {id: b, text_es: "tu", text_it: "tuo"}
      answer: a
    solution_es: "Tú es la persona: de ti."
    solution_it: "Tú è la persona: di te."
    final_es: "tú"
    final_it: "tu"
  - check:
      component: normalized_text
      prompt_es: "Escribe la palabra que falta."
      prompt_it: "Scrivi la parola che manca."
      input_before: "¿Dónde"
      input_after: "tu tía?"
      answer: "vive"
    solution_es: "Vive es la forma de ella."
    solution_it: "Vive è la forma di lei."
    final_es: "vive"
    final_it: "vive"
:::
