// The Italian words of the words family that a layout or a description prints. config/locales/lesson_words.it.yml holds the same strings (key
// `scene`), the Ruby twins read them from there, and words_texts.test.mjs fails when the two differ. Short sentences, common words.
export const TEXT = {
  together: "Tutto insieme",
  strong_key: "Sillaba forte",
  mark_stem: "radice",
  mark_ending: "desinenza",
  mark_change: "lettere che cambiano",
  mark_attached: "pezzo attaccato",
  link_same: "uguale",
  link_meaning: "stesso significato",
  link_shift: "cambia",
  link_false_friend: "falso amico",
  link_none: "senza coppia",
  italian_side: "Italiano",
  english_side: "Inglese",
  spanish_side: "Spagnolo",
  pair_number: "Coppia",
  note_label: "Nota"
}

// The chrome words of the mirror and of the word_parts legend in the language of a bilingual lesson (D-402), by the lesson's language: the figure draws these and says
// the Italian ones (TEXT) in its translation panel, like a sentence's role names. Only the keys these figures draw; a legacy lesson draws TEXT.
export const TARGET_TEXT = {
  en: { mark_stem: "root", mark_ending: "ending", mark_change: "changing letters", mark_attached: "attached piece", strong_key: "Stress here", link_same: "same", link_meaning: "same meaning", link_shift: "changes", link_false_friend: "false friend", link_none: "no partner", italian_side: "Italian", english_side: "English", spanish_side: "Spanish", pair_number: "Pair" },
  es: { mark_stem: "raíz", mark_ending: "desinencia", mark_change: "letras que cambian", mark_attached: "pieza añadida", strong_key: "Sílaba fuerte", link_same: "igual", link_meaning: "mismo significado", link_shift: "cambia", link_false_friend: "falso amigo", link_none: "sin pareja", italian_side: "italiano", english_side: "inglés", spanish_side: "español", pair_number: "Pareja" }
}

// The caps the layouts mirror (config/banco/validation_rules.yml, lesson2.types).
export const CAPS = {
  word_parts: { words: [1, 4], parts: 4, letters: 20, syllables: 8, meaning_words: 12 },
  mirror: { rows: [1, 3], words_per_side: 12 }
}

export const chromeOf = (lang) => TARGET_TEXT[lang] ?? null

// The «word in the language of the lesson → Italian» pairs of the chrome a mirror draws, for the figure's translation panel (its labels carry the lesson's
// language, so the render check leaves them out and the panel says them): the sides, the link kinds that appear, «no partner» when a piece has none, and
// «Pair» when there are several rows. Empty in a legacy lesson.
export function mirrorChromePairs(data, lang) {
  const words = chromeOf(lang)
  if (!words) return []
  const keys = []
  const add = (key) => { if (!keys.includes(key)) keys.push(key) }
  data.rows.forEach((row, i) => {
    const target = row.pieces_en != null ? "en" : row.pieces_es != null ? "es" : null
    if (!target) return
    const tg = target === "en" ? row.pieces_en : row.pieces_es
    const links = row.links ?? []
    add("italian_side")
    add(`${{ en: "english", es: "spanish" }[target]}_side`)
    if (data.rows.length > 1 && i === 0) add("pair_number")
    for (const l of links) add(`link_${l[2]}`)
    if (row.pieces_it.some((_, p) => links.every((l) => l[0] !== p)) || tg.some((_, p) => links.every((l) => l[1] !== p))) add("link_none")
  })
  return keys.map((k) => [words[k], TEXT[k]])
}

export const markWord = (mark) => TEXT[`mark_${mark}`]
export const countIt = (n, one, many) => (n === 1 ? `una ${one}` : `${n} ${many}`)
