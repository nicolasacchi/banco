// summary: the points of the summary card, each with its own icon: a keyword of the point picks a fitting one from our sprite,
// the others take the next of a short list, so no two tiles in a row look the same.
import { el, icon } from "lesson/dom"
import { renderInlineRich } from "lesson/text"

const BY_WORD = [[/verific|controll/i, "check-check"], [/impossibil|indetermin|infinit|ogni /i, "infinity"], [/soluzion|incognit/i, "target"], [/sviluppa|sposta|somma|passi|metodo/i, "list-checks"], [/frazion|divid|rapport/i, "divide"], [/regol|principio/i, "scale"]]
const SPARE = ["puzzle", "pin", "milestone", "sigma", "equal"]
// the keyword icons of numbers (infinity, divide, scale) and the spare sigma and equals sign mean nothing outside the maths: other subjects
// take only the neutral ones, so a history summary never wears a sigma
const MATH_ONLY = new Set(["infinity", "divide", "scale", "sigma", "equal"])
const SPARE_OTHER = ["puzzle", "pin", "milestone", "lightbulb", "compass", "telescope", "sparkles"]

export function iconFor(text, used, subject = "math") {
  const maths = subject === "math"
  const plain = String(text).replace(/[$\\{}]/g, " ")
  const hit = BY_WORD.find(([re, name]) => re.test(plain) && !used.includes(name) && (maths || !MATH_ONLY.has(name)))
  const name = hit ? hit[1] : (maths ? SPARE : SPARE_OTHER).find((n) => !used.includes(n)) ?? "check"
  used.push(name)
  return name
}

export function render(block, ctx) {
  const list = el("ul", { class: "block summary-points" })
  const used = []
  for (const point of block.points_it) list.appendChild(el("li", {}, icon(iconFor(point, used, ctx.subject), "point-ic"), renderInlineRich(point, el("span", { class: "point-text" }), ctx)))
  return list
}
