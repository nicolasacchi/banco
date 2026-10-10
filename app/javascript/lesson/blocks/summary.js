// summary: the points of the summary card, each with its own icon: a keyword of the point picks a fitting one from our sprite,
// the others take the next of a short list, so no two tiles in a row look the same.
import { el, icon } from "lesson/dom"
import { renderInlineRich } from "lesson/text"

const BY_WORD = [[/verific|controll/i, "check-check"], [/impossibil|indetermin|infinit|ogni /i, "infinity"], [/soluzion|incognit/i, "target"], [/sviluppa|sposta|somma|passi|metodo/i, "list-checks"], [/frazion|divid|rapport/i, "divide"], [/regol|principio/i, "scale"]]
const SPARE = ["puzzle", "pin", "milestone", "sigma", "equal"]

export function iconFor(text, used) {
  const plain = String(text).replace(/[$\\{}]/g, " ")
  const hit = BY_WORD.find(([re, name]) => re.test(plain) && !used.includes(name))
  const name = hit ? hit[1] : SPARE.find((n) => !used.includes(n)) ?? "check"
  used.push(name)
  return name
}

export function render(block, ctx) {
  const list = el("ul", { class: "block summary-points" })
  const used = []
  for (const point of block.points_it) list.appendChild(el("li", {}, icon(iconFor(point, used), "point-ic"), renderInlineRich(point, el("span", { class: "point-text" }), ctx)))
  return list
}
