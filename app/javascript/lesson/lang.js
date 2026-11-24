// The language of a lesson's text (D-266; the Ruby twin is Lessons::Lang). In a lesson of a language subject a colour role span holds words of
// that language unless it says |it, so the parser is told which. Keys and spans of a language belong to the subjects that teach it (the server
// checks that, E-LESSON-LANG); the browser only needs the target of the subject.
export const TARGET_OF = {"english": "en", "spanish": "es"}

export const targetOf = (subject) => TARGET_OF[subject] ?? null

// D-402: in a bilingual lesson the server has folded each pair (Lessons::Bilingual.fold) so that every `_it` slot the renderer reads holds the TARGET text,
// and the Italian travels in `tr`, a table {target string: Italian} on the body, a card or a block. A string that reaches the page unchanged finds its
// Italian here; one that code built finds none and gets no translation. The page's language is `lang` of the body ("en", "es", absent in a legacy lesson).
export const PAIR_LANGS = ["en", "es"]

// The Italian of `text` in the table of the nearest scope that has it: `scopes` runs from the block outwards (block, card, body); null when none has it.
export function italianOf(text, ...scopes) {
  for (const scope of scopes) {
    const found = scope?.tr?.[text]
    if (typeof found === "string") return found
  }
  return null
}

// The text of `base` that the target layer shows in a hash (Lessons::Lang.pick): `<base>_<lang>` when it has it, else `<base>_it`. For a served lesson
// that was folded the answer is always `<base>_it`, so only items and unfolded data need this.
export function pick(hash, base, lang = null) {
  const found = lang ?? PAIR_LANGS.find((l) => `${base}_${l}` in hash)
  return (found && hash[`${base}_${found}`]) || hash[`${base}_it`]
}

// Whether `hash` holds the pair of `base`: the target text and its Italian (Lessons::Lang.pair?).
export const hasPair = (hash, base) => PAIR_LANGS.some((l) => `${base}_${l}` in hash) && `${base}_it` in hash
