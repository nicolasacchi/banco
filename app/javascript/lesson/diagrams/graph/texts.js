// The Italian words of the graph family that a layout or a description prints. The locale file config/locales/lesson_graph.it.yml
// holds the same strings (key `scene`), the Ruby twins read them from there, and graph_texts.test.mjs fails when the two differ.
// Short sentences, common words: the student reads with difficulty.
export const TEXT = {
  everyone: "Tutti gli altri",
  not_causal: "solo prima",
  hypothesis: "Senza questa causa, questi fatti perdono una delle loro ragioni. Che cosa sarebbe successo davvero non lo sappiamo: è un'ipotesi.",
  nothing_grey: "Ogni fatto ha ancora una causa.",
  remove_label: "Togli una causa",
  remove_hint: "Tocca una causa per toglierla. Toccala di nuovo per rimetterla.",
  removed: "tolta",
  filter_label: "Che cosa vuoi vedere?",
  filter_hint: "Tocca un tipo di freccia per vedere solo quelle.",
  note_hint: "Tocca la casella per leggere la nota.",
  no_edges: "Per ora non c'è nessuna freccia.",
  moves_title: "Le mosse",
  station_here: "Tu sei qui",
  return_label: "Si torna indietro",
  journey_title: "Il percorso",
  path_here: "Ora siamo qui:",
  grey_tag: "senza causa",
  removed_now: "Ora hai tolto"
}

// The fixed areas of a cause (WAVE2 2.1): an icon and a word each, not a colour role.
export const AREAS = {
  economy: { icon: "coins", label_it: "economia" },
  society: { icon: "users", label_it: "società" },
  politics: { icon: "landmark", label_it: "politica" },
  military: { icon: "swords", label_it: "guerra" },
  religion: { icon: "church", label_it: "religione" },
  environment: { icon: "trees", label_it: "ambiente" },
  science: { icon: "atom", label_it: "scienza" }
}

// What a link says when the author wrote no word: by layout.
export const DEFAULT_WORD = { line: "porta a", fan: "quindi", ring: "poi" }
