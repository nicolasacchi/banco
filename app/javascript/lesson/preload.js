// What a lesson body needs loaded before its first card is drawn (WAVE2 1.2, D-264): the diagram types that are not in the main bundle and
// the check components of lesson/checks. renderLesson draws synchronously, so the page awaits `preloadFor(body)` first; a lesson that uses
// only the nine types of release 1 and the six built-in components waits for nothing. A module that fails to load does not stop the page:
// the figure draws its fallback (alt text and description) and the check says it cannot be shown.
import { TYPES, preload as preloadTypes } from "lesson/diagrams/registry"
import { preload as preloadChecks } from "lesson/checks/registry"

const BUILT_IN = ["choice", "number", "fraction", "normalized_text", "matching", "span_select"]

// { types: Set, components: Set } used by a body (the student projection or the full body).
export function usedBy(body) {
  const types = new Set()
  const components = new Set()
  const diagram = (d) => { if (d?.type) types.add(d.type) }
  const check = (c) => {
    if (!c?.component) return
    components.add(c.component)
    if (c.component === "select") diagram(c.diagram)
  }
  const block = (b) => {
    switch (b?.type) {
      case "diagram": diagram(b.diagram); break
      case "schema": diagram(b.schema); break
      case "cases": (b.cases ?? []).forEach((c) => diagram(c.diagram)); break
      case "check": check(b); break
      case "example": diagram(b.diagram); (b.steps ?? []).forEach((s) => check(s.blank)); break
      case "try": (b.exercises ?? []).forEach((e) => { diagram(e.diagram); check(e.check); (e.checks ?? []).forEach(check) }); break
      case "more": (b.blocks ?? []).forEach(block); break
      default: break
    }
  }
  diagram(body?.hero)
  for (const card of body?.cards ?? []) (card.blocks ?? []).forEach(block)
  return { types, components }
}

// The subjects whose formulas may hold \ce{} and \pu{} (the server refuses them elsewhere): they load KaTeX's mhchem before the first card is drawn.
export const MHCHEM_SUBJECTS = ["chemistry", "biology"]

export async function preloadFor(body) {
  const { types, components } = usedBy(body)
  if (MHCHEM_SUBJECTS.includes(body?.subject)) {
    try { await import("katex/mhchem") } catch (_error) { /* the formulas then show as plain text */ }
  }
  const wanted = [...types].filter((t) => !TYPES[t])
  const modules = [...components].filter((c) => !BUILT_IN.includes(c))
  const settle = (list) => Promise.allSettled(list)
  await Promise.all([settle([preloadTypes(wanted)]), settle([preloadChecks(modules)])])
}
