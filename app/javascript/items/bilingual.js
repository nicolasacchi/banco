// The target-language text of an item and its authored Italian (D-402): how the item templates and the practice page read a served pair and draw it.
// A bilingual item carries `lang` ("en" or "es") and, next to each target text, its Italian: `stem_en` + `stem_it`, `hint_es` + `hint_it`, an option's
// `text` + `text_it` (the neutral keys hold the target text, rule R2). A legacy item has neither: its `_it` text is drawn as it always was and gets no button.
//
// The state, the node and the buttons are items/translation.js (one machine with the lessons); here is only what is specific to the items:
//   sides()      reads a pair from a served hash, the same code for a bilingual and a legacy payload;
//   trNode()     the Italian as a translation node, its markup drawn like the target's;
//   block()      a target text and its translation, with a small button of its own when the Italian is long;
//   cell()       the same for a fragment inside a control (an option, a row, a cell): never a button;
//   reveal()     the passage's translation, added only when the item is over (the reading rule: the Italian must not be on the page before the answer).
//   passageBox() the passage's target text.
import { renderInline, renderMarkup } from "items/markup"
import { toggleButton, node, unitLabel } from "items/translation"

export const PAIR_LANGS = ["en", "es"]

// A translation longer than this many words gets a button of its own (the exercise's «Traduzione» opens all of them anyway).
export const LONG_WORDS = 20

// The language of an item payload; null for a legacy one. A sub item inherits the testlet's.
export const langOf = (part, fallback = null) => (PAIR_LANGS.includes(part?.lang) ? part.lang : fallback)

// The pair `base` of a served hash: { text, italian, lang }, with the target text under `<base>_<lang>` and its Italian under `<base>_it`; a legacy
// payload has only `<base>_it`, which is { text, italian: null, lang: null }. null when the hash has neither. `lang` narrows the target key when the
// page knows the item's language; without it the key of either language is found (a reply carries only one).
export function sides(hash, base, lang = null) {
  if (!hash) return null
  const found = (lang ? [lang] : PAIR_LANGS).find((l) => hash[`${base}_${l}`] !== undefined && hash[`${base}_${l}`] !== null)
  if (found) return { text: hash[`${base}_${found}`], italian: hash[`${base}_it`] ?? null, lang: found }
  const legacy = hash[`${base}_it`]
  return legacy === undefined || legacy === null ? null : { text: legacy, italian: null, lang: null }
}

// A field whose bare key already holds the target text (an option's `text`, `final`, a table's cells): { text, italian } with the Italian under `<key>_it`
// only for a bilingual item (`lang` set), so that a legacy payload that happens to carry the key is read as it was.
export const bare = (hash, key, lang) => ({ text: hash?.[key], italian: lang ? (hash?.[`${key}_it`] ?? null) : null })

const wordCount = (text) => String(text).trim().split(/\s+/).filter(Boolean).length

// The Italian as a translation node. A single paragraph is drawn inline into the node, so the small «IT» label sits in front of the text.
export const trNode = (italian, { tag = "div" } = {}) => renderInline(String(italian), node(null, { tag }))

// A text unit: `target` (the DOM the caller drew: a fragment or an element) followed by its translation, in a block of its own that a button flips.
// The button is drawn when the Italian is long (or `long`), inside the last paragraph of the target so that it takes no line of its own; it is never
// called from inside a control. `source` is the target's plain text, whose first words name the button. Without an Italian the target is returned as is.
export function block(target, source, italian, ctx, { long = false, tag = "div" } = {}) {
  if (italian === null || italian === undefined || italian === "") return target
  const wrapper = document.createElement("div")
  wrapper.setAttribute("class", "tr-block")
  wrapper.appendChild(target)
  if ((long || wordCount(italian) > LONG_WORDS) && ctx?.t?.translation_unit) {
    wrapper.setAttribute("data-tr-scope", "block")
    const button = toggleButton({ text: "IT", unit: true, ariaLabel: unitLabel(ctx.t.translation_unit, source) })
    const last = wrapper.children[wrapper.children.length - 1]
    ;(last && last.tagName?.toLowerCase() === "p" ? last : wrapper).appendChild(button)
  }
  wrapper.appendChild(trNode(italian, { tag }))
  return wrapper
}

// The same, for a fragment: the translation node goes into `host` (after what is there); no button. A control has the exercise's button only.
export function cell(host, italian, { tag = "span" } = {}) {
  if (italian !== null && italian !== undefined && italian !== "") host.appendChild(trNode(italian, { tag }))
  return host
}

// The passage's Italian, after the exercise is over: appended to the `.passage` under `root` (one per item), as a translation node that the exercise's
// «Traduzione» shows (the item is inert by then, so the passage gets no button of its own). Idempotent: the solution after the answer leaves it as it is.
// Returns whether a translation was added.
export function reveal(root, italian) {
  if (!italian || !root) return false
  const passage = root.querySelector?.(".passage[data-lang]")
  if (!passage || passage.querySelector?.(".tr")) return false
  passage.appendChild(trNode(italian))
  return true
}

// The target text of a passage as markup, in the passage box: `lang` on the box tells the voice and `data-lang` finds it for reveal().
export function passageBox(text, lang, className = "passage") {
  const box = document.createElement("div")
  box.setAttribute("class", className)
  box.setAttribute("lang", lang)
  box.setAttribute("data-lang", lang)
  box.appendChild(renderMarkup(text))
  return box
}
