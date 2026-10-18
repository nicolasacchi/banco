// check component tiles (WAVE2 2.11, T1): build a sentence (or a list) from tiles; the tiles outside the answer are distractors. The tiles
// arrive shuffled under fresh ids (e1..eN), no answer in the page; Controlla sends the ids in the line, the server grades the sequence.
//
//   render(check, ctx, hooks) -> an input handle { element, raw(), isEmpty(), focus() } that renderCheck (lesson/blocks/check.js) wraps
//   buildTiles(spec, ctx, options) -> { element, ids(), clear(), focus(), onChange }   the same input without the check around it: the
//                                     `oral` outline (T8) builds on it
//
// Tiles are buttons. Tap a tile of the bank: it goes to the end of the line. Tap a tile of the line: it goes back. A tile of the line moves
// with the left and right arrows. "Svuota" empties the line. A tile of the bank that is in the line stays in its place as an empty outline,
// so the bank does not jump while the student builds (no layout shift). Texts of the target language carry their lang; an Italian tile is
// drawn with the inline markup of the lesson (a formula, bold), its button named by its plain text.
// The fixed words are neutral ("La tua risposta", "Le tessere": the tiles may be facts, symbols or words); a check with `builds: sentence`
// says "La tua frase", "Le parole" (D-310).
// "Ascolta la frase": only when ctx.speaker(lang) gives a speaker, i.e. an accepted local voice exists (T2, "Ascolta"); never autoplays.
import { handle } from "items/dom"
import { button, el, uid } from "lesson/dom"
import { createTiles } from "lesson/checks/sequence_model"
import { insideControl, plainText, renderInlineRich } from "lesson/text"

export const type = "tiles"

export const textOf = (tile) => tile.text_en ?? tile.text_es ?? tile.text_it ?? ""
export const langOf = (tile) => (tile.text_en != null ? "en" : tile.text_es != null ? "es" : null)
// what a screen reader and the live region say of a tile: its words, never its markup
export const nameOf = (tile) => (langOf(tile) ? textOf(tile) : plainText(textOf(tile)))

// The fixed words of a check: { line, bank, empty, used, placed } (pure: texts is ctx.t.checks).
export function tilesTexts(spec, texts) {
  const own = { line: texts.tiles_line, bank: texts.tiles_bank, empty: texts.tiles_empty, used: texts.tile_used, placed: texts.tile_placed }
  return spec.builds === "sentence" ? { ...own, ...texts.tiles_sentence } : own
}

const fill = (template, values) => String(template).replace(/%\{(\w+)\}/g, (_, k) => values[k] ?? "")

function tileLabel(tile, ctx) {
  const lang = langOf(tile)
  if (lang) return el("span", { class: "tile-text", lang, text: textOf(tile) })
  return renderInlineRich(textOf(tile), el("span", { class: "tile-text" }), insideControl(ctx))
}

export function buildTiles(spec, ctx, options = {}) {
  const texts = ctx.t.checks
  const words = tilesTexts(spec, texts)
  const byId = new Map(spec.tiles.map((t) => [t.id, t]))
  const model = createTiles(spec.tiles.map((t) => t.id))
  const name = uid("tiles")
  const lineLabel = el("p", { class: "tiles-label", id: `${name}-line`, text: options.lineLabel ?? words.line })
  const line = el("ol", { class: "tiles-line", "aria-labelledby": `${name}-line` })
  const bankLabel = el("p", { class: "tiles-label", id: `${name}-bank`, text: words.bank })
  const bank = el("div", { class: "tiles-bank", role: "group", "aria-labelledby": `${name}-bank` })
  const live = el("p", { class: "sr-only", role: "status", "aria-live": "polite" })
  const clearButton = button(texts.tiles_clear, { class: "button secondary small tiles-clear" }, () => {
    model.clear()
    draw()
    say(texts.tiles_cleared)
    bankButtons().find((b) => !b.disabled)?.focus()
  })
  const actions = el("p", { class: "tiles-actions" }, clearButton)
  const root = el("div", { class: "answer tiles", "data-component": "tiles" }, lineLabel, line, bankLabel, bank, actions, live)
  const result = { element: root, ids: () => model.line(), clear: () => { model.clear(); draw() }, focus: () => (bankButtons().find((b) => !b.disabled) ?? clearButton).focus(), onChange: options.onChange }

  const bankButtons = () => [...bank.querySelectorAll("button")]
  const say = (text) => { live.textContent = text }
  const sentence = () => model.line().map((id) => nameOf(byId.get(id))).join(" ")

  function speakerFor() {
    const langs = new Set(model.line().map((id) => langOf(byId.get(id))).filter(Boolean))
    return langs.size === 1 ? ctx.speaker?.([...langs][0]) ?? null : null
  }

  function draw(focusId = null) {
    line.replaceChildren()
    const ids = model.line()
    if (ids.length === 0) line.appendChild(el("li", { class: "tiles-empty", "aria-hidden": "true", text: words.empty }))
    ids.forEach((id, i) => {
      const tile = byId.get(id)
      const b = el("button", {
        type: "button", class: "tile tile-built", "data-id": id,
        "aria-label": fill(texts.tile_built, { text: nameOf(tile), n: i + 1, total: ids.length })
      }, tileLabel(tile, ctx))
      b.addEventListener("click", () => {
        const at = model.line().indexOf(id)
        model.remove(id)
        draw()
        say(fill(texts.tile_removed, { text: nameOf(tile) }))
        options.onChange?.()
        const next = line.querySelectorAll("button.tile-built")[Math.min(at, model.line().length - 1)]
        ;(next ?? bank.querySelector(`button[data-id="${id}"]`))?.focus()
      })
      b.addEventListener("keydown", (event) => {
        if (event.altKey || event.ctrlKey || event.metaKey || (event.key !== "ArrowLeft" && event.key !== "ArrowRight")) return
        event.preventDefault()
        model.move(id, event.key === "ArrowLeft" ? -1 : 1)
        draw(id)
        say(fill(texts.tile_moved, { n: model.line().indexOf(id) + 1, total: model.line().length }))
        options.onChange?.()
      })
      const li = el("li", { class: "tiles-slot" }, b)
      line.appendChild(li)
    })
    bank.replaceChildren()
    for (const tile of spec.tiles) {
      const used = model.has(tile.id)
      const b = el("button", {
        type: "button", class: `tile tile-bank${used ? " is-used" : ""}`, "data-id": tile.id,
        "aria-disabled": used ? "true" : null, tabindex: used ? "-1" : null,
        "aria-label": used ? fill(words.used, { text: nameOf(tile) }) : null
      }, tileLabel(tile, ctx))
      b.addEventListener("click", () => {
        if (model.has(tile.id)) return
        const order = spec.tiles.map((t) => t.id)
        const at = order.indexOf(tile.id)
        model.place(tile.id)
        draw()
        say(fill(words.placed, { text: sentence() }))
        options.onChange?.()
        // the focus moves to the next tile still in the bank, else the one before it, else the button that empties the line
        const free = (id) => !model.has(id)
        const nextId = order.slice(at + 1).find(free) ?? order.slice(0, at).reverse().find(free)
        ;(nextId ? bank.querySelector(`button[data-id="${nextId}"]`) : clearButton)?.focus()
      })
      bank.appendChild(b)
    }
    clearButton.disabled = ids.length === 0
    const speaker = speakerFor()
    actions.querySelector(".tiles-listen")?.remove()
    if (speaker && ids.length > 0) {
      actions.appendChild(button(texts.tiles_listen, { class: "button secondary small tiles-listen" }, () => speaker.speak(sentence())))
    }
    if (focusId) line.querySelector(`button[data-id="${focusId}"]`)?.focus()
  }
  draw()
  return result
}

export function render(spec, ctx, _hooks) {
  const input = buildTiles(spec, ctx)
  return handle(input.element, { raw: () => JSON.stringify(input.ids()), isEmpty: () => input.ids().length === 0, focus: input.focus })
}
