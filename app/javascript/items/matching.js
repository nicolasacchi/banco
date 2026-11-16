// matching: one native select per left item, the right column as its options (n+1
// of them). Both columns arrive shuffled and re-keyed by the server (X-01). The raw
// answer is JSON text: {left id: right id}, with "" for a select left blank.
import { announceChange, el, handle, parseDraft, uid } from "items/dom"
import { renderInline } from "items/markup"

export function render(part, ctx) {
  const rows = (part.left || []).map((left, index) => {
    const id = uid("match")
    const select = el("select", { id, class: "answer-input", "data-left": left.id },
      el("option", { value: "", text: ctx.t.matching_blank }),
      (part.right || []).map((right) => el("option", { value: right.id, text: plain(right.text) })))
    const label = renderInline(left.text, el("label", { for: id, class: "match-left" }))
    return { select, row: el("div", { class: "match-row", "data-comment-anchor": `row:${index + 1}` }, label, select) }
  })
  // Each answer is used at most once: an entry picked in one select is greyed out in the others.
  // A classification (reuse_right, D-092) lets several rows share an answer: nothing is greyed out.
  const sync = () => {
    const taken = new Set(rows.map(({ select }) => select.value).filter((v) => v !== ""))
    rows.forEach(({ select }) => {
      for (const option of select.options) option.disabled = option.value !== "" && taken.has(option.value) && option.value !== select.value
    })
  }
  if (!part.reuse_right) rows.forEach(({ select }) => select.addEventListener("change", sync))
  const wrapper = el("div", { class: "answer" }, el("p", { class: "hint", text: part.reuse_right ? ctx.t.matching_reuse_label : ctx.t.matching_label }), rows.map((r) => r.row))
  // A row left empty is marked (class missing on the row, aria-invalid on its select) by showMissing(); the mark goes when it gets an answer.
  const clearMarks = () => rows.forEach(({ select, row }) => {
    if (select.value === "") return
    row.classList.remove("missing")
    select.removeAttribute("aria-invalid")
  })
  rows.forEach(({ select }) => select.addEventListener("change", () => { clearMarks(); announceChange(wrapper) }))
  const raw = () => JSON.stringify(Object.fromEntries(rows.map(({ select }) => [select.getAttribute("data-left"), select.value])))
  const isEmpty = () => rows.every(({ select }) => select.value === "")
  const rightIds = new Set((part.right || []).map((right) => right.id))
  return handle(wrapper, {
    raw,
    isEmpty,
    focus: () => rows[0]?.select.focus(),
    // Marks every row without an answer; the first one is scrolled into view and focused (pass false to mark only). Returns how many rows are marked.
    showMissing: (focusFirst = true) => {
      const missing = rows.filter(({ select }) => select.value === "")
      for (const { select, row } of missing) {
        row.classList.add("missing")
        select.setAttribute("aria-invalid", "true")
      }
      if (focusFirst && missing.length > 0) {
        missing[0].row.scrollIntoView?.({ block: "center" })
        missing[0].select.focus()
      }
      return missing.length
    },
    // A matching with some rows set is a draft: the raw answer, "" for a row not set.
    draft: () => (isEmpty() ? "" : raw()),
    restore: (draft) => {
      const picked = parseDraft(draft)
      if (!picked) return
      for (const { select } of rows) {
        const value = picked[select.getAttribute("data-left")]
        if (typeof value === "string" && (value === "" || rightIds.has(value))) select.value = value
      }
      sync()
      clearMarks()
    }
  })
}

// <option> holds text only: markup marks are dropped there.
function plain(text) {
  return String(text).replace(/\*\*/g, "").replace(/\$/g, "")
}
