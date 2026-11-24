// matching: one native select per left item, the right column as its options (n+1
// of them). Both columns arrive shuffled and re-keyed by the server (X-01). The raw
// answer is JSON text: {left id: right id}, with "" for a select left blank.
import { announceChange, el, handle, parseDraft, uid } from "items/dom"
import { renderInline } from "items/markup"
import { bare, langOf, trNode } from "items/bilingual"

export function render(part, ctx) {
  const lang = langOf(part)
  const rows = (part.left || []).map((left, index) => {
    const id = uid("match")
    const select = el("select", { id, class: "answer-input", "data-left": left.id },
      el("option", { value: "", text: ctx.t.matching_blank }),
      (part.right || []).map((right) => el("option", { value: right.id, text: plain(right.text) })))
    const label = renderInline(left.text, el("label", { for: id, class: "match-left" }))
    // A bilingual row (D-402): the Italian of the left text under the row, when the exercise's translation is open. The right-hand answers are the
    // options of a native select, which holds text only: their Italian is the legend under the rows (legendOf).
    const { italian } = bare(left, "text", lang)
    if (lang) label.setAttribute("lang", lang)
    return { select, row: el("div", { class: "match-row", "data-comment-anchor": `row:${index + 1}` }, label, select, italian ? trNode(italian) : null) }
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
  const wrapper = el("div", { class: "answer" }, el("p", { class: "hint", text: part.reuse_right ? ctx.t.matching_reuse_label : ctx.t.matching_label }), rows.map((r) => r.row), legendOf(part.right, lang))
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
        row.dataset.missing = ctx.t.missing
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

// The Italian of the right-hand answers (D-402): a native <select> holds text only, so a bilingual matching whose right labels have a `text_it` draws them as a
// small legend under the rows, one line per label (the target text, then its Italian), shown with the exercise's translation and hidden with it. A label
// without an Italian has no line, and an item with none (a form material: the labels are the forms the student judges) has no legend at all.
// Returns the list, or null.
function legendOf(right, lang) {
  const lines = lang ? (right || []).map((label) => ({ label, italian: bare(label, "text", lang).italian })).filter((line) => line.italian) : []
  if (lines.length === 0) return null
  const list = el("ul", { class: "match-legend", "data-nospeech": "" })
  for (const { label, italian } of lines) {
    const target = renderInline(plain(label.text), el("span", { class: "match-legend-target", lang }))
    const translation = renderInline(String(italian), el("span", { class: "match-legend-it", lang: "it" }))
    list.appendChild(el("li", {}, target, document.createTextNode(" = "), translation))
  }
  return list
}

// <option> holds text only: markup marks are dropped there.
function plain(text) {
  return String(text).replace(/\*\*/g, "").replace(/\$/g, "")
}
