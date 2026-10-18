// The fixed how-to line of a new check component (A9) and its "Come si risponde" entry. The line is printed on the component's first use
// in a lesson (first in the order of the cards, not the first the student happens to open); the entry, closed, sits under every use. Authors
// write nothing for either: the texts are config/locales/lesson_checks.it.yml (ctx.t.checks). Pure except howtoNodes, which builds DOM.
import { el } from "lesson/dom"

// the same address the check endpoint uses
export const locKey = (loc) => [loc.card, loc.block, loc.step, loc.ex, loc.part].map((x) => x ?? "").join("/")

const COMPONENTS = ["select", "tiles", "ordering"]

// {component => locKey of its first use}, walking the cards in order
export function firstUses(body) {
  const first = new Map()
  const note = (check, loc) => {
    if (check?.component && COMPONENTS.includes(check.component) && !first.has(check.component)) first.set(check.component, locKey(loc))
  }
  const block = (card, b) => {
    if (b.type === "check") note(b, { card: card.n, block: b.n })
    else if (b.type === "example") (b.steps ?? []).forEach((s, i) => note(s.blank, { card: card.n, block: b.n, step: i + 1 }))
    else if (b.type === "try") {
      for (const e of b.exercises ?? []) {
        const checks = e.checks ?? (e.check ? [e.check] : [])
        checks.forEach((c, k) => note(c, { card: card.n, block: b.n, ex: e.n, part: checks.length > 1 ? k + 1 : undefined }))
      }
    } else if (b.type === "more") (b.blocks ?? []).forEach((inner) => block(card, inner))
  }
  const ordered = [...(body?.cards ?? [])].sort((a, b) => (a.level === b.level ? a.n - b.n : a.level === "core" ? -1 : 1))
  for (const card of ordered) (card.blocks ?? []).forEach((b) => block(card, b))
  return first
}

// the key of the one-line text for a check: select has two (one tap or several), tiles two (neutral, or `builds: sentence`, D-310)
export function howtoKey(spec) {
  if (spec.component === "select") return spec.pick === "one" ? "select_one" : "select_many"
  if (spec.component === "tiles") return spec.builds === "sentence" ? "tiles_sentence" : "tiles"
  return COMPONENTS.includes(spec.component) ? spec.component : null
}

// [line | null, details | null]
export function howtoNodes(spec, ctx, loc) {
  const key = howtoKey(spec)
  const texts = ctx.t.checks
  if (!key || !texts) return [null, null]
  const line = ctx.firstUse?.get(spec.component) === locKey(loc) && texts.howto?.[key] ? el("p", { class: "hint howto", text: texts.howto[key] }) : null
  const entry = texts.help?.[key] ?? texts.help?.[spec.component]
  const more = entry
    ? el("details", { class: "howto-help" }, el("summary", { text: texts.help_title }), el("ul", { class: "plain" }, (entry.lines ?? []).map((l) => el("li", { text: l }))), entry.example ? el("p", { class: "howto-example" }, el("strong", { text: `${texts.help_example}: ` }), entry.example) : null)
    : null
  return [line, more]
}
