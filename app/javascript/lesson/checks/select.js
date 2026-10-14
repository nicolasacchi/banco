// check component select (WAVE2 2.11, T1): tap zones of a drawing. The check's own figure (a type that declares target sets) is drawn in
// mode "select": its layout marks each candidate with a target id tN in reading order and draws every candidate alike (L3), the
// descriptions are the type's neutral ones. The student taps (pick many: toggles; pick one: a single choice), a live line says how many are
// chosen, Controlla sends the sorted list of tN; the server maps them back through the same order (Lessons::SelectTargets) and grades.
//
// Keyboard (draw.js selectTargets): one tab stop, arrows to the geometrically nearest target, Home and End, Space or Enter toggles.
// A screen reader hears "zona 3 di 12" and the type's neutral description, never a name.
// If the figure draws no target (a layout error, safe mode), a plain list of toggle buttons stands in, so the check still works.
import { handle } from "items/dom"
import { button, el } from "lesson/dom"
import { figureFor } from "lesson/blocks/diagram"
import { moduleFor } from "lesson/diagrams/registry"
import { targetLabel } from "lesson/checks/select_model"

export const type = "select"

const fill = (template, values) => String(template).replace(/%\{(\w+)\}/g, (_, k) => values[k] ?? "")

// [{ key, bbox, neutral_it }] of the figure's set, or [] when the type cannot say (never throws).
export function targetsOf(spec) {
  try {
    const mod = moduleFor(spec.diagram?.type)
    return typeof mod?.targets === "function" ? mod.targets(spec.diagram, spec.targets, { select: true }) ?? [] : []
  } catch (_error) {
    return []
  }
}

export function render(spec, ctx, _hooks) {
  const texts = ctx.t.checks
  const chosen = new Set()
  // A map needs its base loaded before it can list a set, so the list is asked again until it is not empty (the figure is drawn after the load).
  let known = targetsOf(spec)
  const entries = () => (known.length ? known : (known = targetsOf(spec)))
  const infoNow = () => new Map(entries().map((t, i) => [`t${i + 1}`, t]))
  const live = el("p", { class: "select-live", role: "status", "aria-live": "polite" })
  const root = el("div", { class: "answer select", "data-component": "select", "data-pick": spec.pick })
  const sorted = () => [...chosen].sort((a, b) => Number(a.slice(1)) - Number(b.slice(1)))
  const say = () => {
    live.textContent = chosen.size === 0 ? (spec.pick === "one" ? texts.select_none_one : texts.select_none) : fill(texts.select_count, { n: chosen.size })
  }
  const fallbackSync = []
  const selectApi = {
    get info() { return infoNow() },
    get total() { return entries().length },
    pick: spec.pick,
    isOn: (id) => chosen.has(id),
    toggle: (id) => {
      if (chosen.has(id)) chosen.delete(id)
      else {
        if (spec.pick === "one") chosen.clear()
        chosen.add(id)
      }
      say()
      for (const sync of fallbackSync) sync()
    },
    onNoTargets: () => showFallback()
  }
  const figure = figureFor(spec.diagram, ctx, { mode: "select", select: selectApi, set: spec.targets })
  figure.node.classList.add("dg-select")
  figure.node.selectTotal = () => selectApi.total
  const list = el("ul", { class: "select-fallback", hidden: "", "aria-label": texts.select_group })
  function showFallback() {
    if (!list.hidden || list.children.length) return
    for (let i = 1; i <= selectApi.total; i++) {
      const id = `t${i}`
      const b = button(targetLabel(texts.select_zone_short, i, selectApi.total, selectApi.info.get(id)?.neutral_it), { class: "span-chip", "aria-pressed": "false", "data-target": id }, () => selectApi.toggle(id))
      fallbackSync.push(() => b.setAttribute("aria-pressed", String(chosen.has(id))))
      list.appendChild(el("li", {}, b))
    }
    list.hidden = false
  }
  if (ctx.safe) setTimeout(showFallback, 0)
  root.append(figure.node, live, list, el("p", { class: "select-print", text: texts.select_print }))
  say()
  return handle(root, {
    raw: () => JSON.stringify(sorted()),
    isEmpty: () => chosen.size === 0,
    focus: () => (root.querySelector(".dg-target[tabindex='0']") ?? root.querySelector("button"))?.focus()
  })
}
