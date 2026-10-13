// The Italian words of the words family that a layout or a description prints. config/locales/lesson_words.it.yml holds the same strings (key
// `scene`), the Ruby twins read them from there, and words_texts.test.mjs fails when the two differ. Short sentences, common words.
export const TEXT = {
  together: "Tutto insieme",
  strong_key: "Qui batte la voce",
  mark_stem: "radice",
  mark_ending: "desinenza",
  mark_change: "lettere che cambiano",
  mark_attached: "pezzo attaccato",
  link_same: "uguale",
  link_shift: "cambia",
  link_false_friend: "falso amico",
  link_none: "senza coppia",
  italian_side: "Italiano",
  english_side: "Inglese",
  spanish_side: "Spagnolo",
  pair_number: "Coppia",
  note_label: "Nota"
}

// The caps the layouts mirror (config/banco/validation_rules.yml, lesson2.types).
export const CAPS = {
  word_parts: { words: [1, 4], parts: 4, letters: 20, syllables: 8, meaning_words: 12 },
  mirror: { rows: [1, 3], words_per_side: 12 }
}

export const markWord = (mark) => TEXT[`mark_${mark}`]
export const countIt = (n, one, many) => (n === 1 ? `una ${one}` : `${n} ${many}`)
