// matching: one native select per left item, the right column as its options (n+1
// of them). Both columns arrive shuffled and re-keyed by the server (X-01). The raw
// answer is JSON text: {left id: right id}, with "" for a select left blank.
import { el, handle, uid } from "items/dom"
import { renderInline } from "items/markup"

export function render(part, ctx) {
  const rows = (part.left || []).map((left) => {
    const id = uid("match")
    const select = el("select", { id, class: "answer-input", "data-left": left.id },
      el("option", { value: "", text: ctx.t.matching_blank }),
      (part.right || []).map((right) => el("option", { value: right.id, text: plain(right.text) })))
    const label = renderInline(left.text, el("label", { for: id, class: "match-left" }))
    return { select, row: el("div", { class: "match-row" }, label, select) }
  })
  const wrapper = el("div", { class: "answer" }, el("p", { class: "hint", text: ctx.t.matching_label }), rows.map((r) => r.row))
  return handle(wrapper, {
    raw: () => JSON.stringify(Object.fromEntries(rows.map(({ select }) => [select.getAttribute("data-left"), select.value]))),
    isEmpty: () => rows.every(({ select }) => select.value === ""),
    focus: () => rows[0]?.select.focus()
  })
}

// <option> holds text only: markup marks are dropped there.
function plain(text) {
  return String(text).replace(/\*\*/g, "").replace(/\$/g, "")
}
