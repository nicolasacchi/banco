// source, the legal half (WAVE2 2.7): the words of a law, with its plain version first. A switch ("In parole semplici" / "Testo della
// legge") opens on the plain text and S then finds it in the legal words; both are printed. The parts are the commi, numbered in the margin.
// Marked words carry their role colour and icon (never colour alone). "Leggi con me" lists the spans the author guides. Our code never changes
// a quotation: each part's text was checked as an exact piece of the imported reference (E-QUOTE-REF). The historical half (kinds written,
// iconographic, material) is W2-2.
import { button, el, icon } from "lesson/dom"
import { insideControl, plainText as plainWords, renderInlineRich, roleOf } from "lesson/text"

// The quotation as nodes: the marked pieces wrapped in their role (first occurrence each, never overlapping), the rest as text.
export function quotationNodes(text, marks, ctx) {
  const spots = []
  for (const mark of marks ?? []) {
    const at = text.indexOf(mark.text_it)
    if (at < 0 || spots.some((s) => at < s.to && at + mark.text_it.length > s.from)) continue
    spots.push({ from: at, to: at + mark.text_it.length, role: mark.role })
  }
  spots.sort((a, b) => a.from - b.from)
  const out = []
  let cursor = 0
  for (const s of spots) {
    if (s.from > cursor) out.push(document.createTextNode(text.slice(cursor, s.from)))
    const info = roleOf(ctx.subject, s.role)
    const span = el("span", { class: `role role-${s.role} source-mark` })
    if (info?.carrier === "icon" && info.icon) span.appendChild(icon(info.icon, "role-ic"))
    span.appendChild(document.createTextNode(text.slice(s.from, s.to)))
    out.push(span)
    cursor = s.to
  }
  if (cursor < text.length) out.push(document.createTextNode(text.slice(cursor)))
  return out
}

function guideList(block, ctx) {
  if (!block.guide?.length) return null
  const list = el("ol", { class: "source-guide-list" })
  for (const g of block.guide) {
    list.appendChild(el("li", {}, el("q", { class: "source-span", text: g.span_it }), renderInlineRich(` ${g.note_it}`, el("span", { class: "source-note" }), ctx)))
  }
  return el("details", { class: "source-guide" }, el("summary", { text: ctx.t.docs.source_guide }), list)
}

export function render(block, ctx) {
  const root = el("section", { class: "block source", "data-kind": block.kind, "aria-label": block.title_it ? plainWords(block.title_it) : null })
  const hasPlain = block.parts.every((p) => p.plain_it)
  let view = hasPlain && block.open !== "original" ? "plain" : "original"
  root.dataset.view = view
  const head = el("header", { class: "source-head" }, icon("book-open", "source-ic"), renderInlineRich(block.title_it ?? "", el("strong", { class: "source-title" }), insideControl(ctx)))
  root.appendChild(head)
  const plainButton = hasPlain ? button(ctx.t.docs.source_plain, { class: "source-switch", "aria-pressed": String(view === "plain") }) : null
  const originalButton = hasPlain ? button(ctx.t.docs.source_original, { class: "source-switch", "aria-pressed": String(view === "original") }) : null
  const list = el("ol", { class: "source-parts" })
  block.parts.forEach((part, i) => {
    const n = i + 1
    const item = el("li", { class: "source-part", value: n })
    item.appendChild(el("span", { class: "source-no", "aria-hidden": "true", text: String(n) }))
    item.appendChild(el("span", { class: "sr-only", text: ` ${ctx.t.docs.source_comma.replace("%{n}", n)}. ` }))
    const body = el("div", { class: "source-body" })
    if (hasPlain) {
      const plainText = renderInlineRich(part.plain_it, el("p", { class: "source-plain" }), ctx)
      plainText.hidden = view !== "plain"
      body.appendChild(plainText)
    }
    const original = el("p", { class: "source-original" }, ...quotationNodes(part.text_it, part.marks, ctx))
    original.hidden = view !== "original"
    body.appendChild(original)
    item.appendChild(body)
    list.appendChild(item)
  })
  const set = (next) => {
    view = next
    root.dataset.view = view
    for (const node of root.querySelectorAll(".source-plain")) node.hidden = view !== "plain"
    for (const node of root.querySelectorAll(".source-original")) node.hidden = view !== "original"
    plainButton?.setAttribute("aria-pressed", String(view === "plain"))
    originalButton?.setAttribute("aria-pressed", String(view === "original"))
  }
  if (hasPlain) {
    plainButton.addEventListener("click", () => set("plain"))
    originalButton.addEventListener("click", () => set("original"))
    root.appendChild(el("div", { class: "source-switchbox", role: "group", "aria-label": ctx.t.docs.source_switch_label }, plainButton, originalButton))
  }
  root.appendChild(list)
  // print, the teacher's view and safe mode show both texts
  if (ctx.openAll) {
    for (const node of root.querySelectorAll(".source-plain, .source-original")) node.hidden = false
    root.dataset.view = "both"
  }
  const guide = guideList(block, ctx)
  if (guide) root.appendChild(guide)
  return root
}
