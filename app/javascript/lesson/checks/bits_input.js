// check option `input: bits` (WAVE2 2.11; T9): the answer of a normalized_text check with the binary profile is written with switches, one per bit,
// in groups of four. No weights are drawn: the profile does not say whether the first bit is a sign (the page's cards teach that).
// The response is the string of bits, exactly as wide as the profile ("00101101"), so the server grades it like a typed one.
// Served: spec.input_width (the profile's width; the profile itself is dropped, L1).
import { handle } from "items/dom"
import { el } from "lesson/dom"

const GROUP = 4
const THIN = "\u202f" // a narrow no-break space between groups of four

export function bitsInput(spec, ctx) {
  const n = spec.input_width
  const bits = Array(n).fill("0")
  let touched = false
  const shown = () => bits.join("").replace(new RegExp(`(?=(.{${GROUP}})+$)`, "g"), THIN).replace(new RegExp(`^${THIN}`), "")
  const group = el("div", { class: "bits-input", role: "group", "aria-label": ctx.t.bits_group })
  const readout = el("p", { class: "bits-readout", "aria-hidden": "true" })
  const live = el("p", { class: "sr-only", role: "status", "aria-live": "polite" })
  const buttons = bits.map((_, i) => {
    const b = el("button", { type: "button", class: "bit-switch", role: "switch", "aria-checked": "false", "data-bit": i, text: "0" })
    return b
  })
  const refresh = (i) => {
    const b = buttons[i]
    b.textContent = bits[i]
    b.setAttribute("aria-checked", String(bits[i] === "1"))
    b.setAttribute("aria-label", ctx.t.bits_label.replace("%{n}", i + 1).replace("%{total}", n).replace("%{value}", bits[i]))
    readout.textContent = shown()
  }
  buttons.forEach((b, i) => {
    refresh(i)
    b.addEventListener("click", () => {
      bits[i] = bits[i] === "1" ? "0" : "1"
      touched = true
      refresh(i)
      live.textContent = ctx.t.bits_now.replace("%{bits}", shown())
    })
  })
  for (let start = 0; start < n; start += GROUP) {
    group.appendChild(el("span", { class: "bit-group" }, buttons.slice(start, start + GROUP)))
  }
  const box = el("div", { class: "answer answer-bits" }, el("p", { class: "hint bits-hint", text: ctx.t.bits_hint }), group, readout, live)
  return handle(box, {
    raw: () => bits.join(""),
    isEmpty: () => !touched,
    focus: () => buttons[0].focus()
  })
}
