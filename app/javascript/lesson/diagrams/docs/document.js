// document (WAVE2 2.7, track T8): one type, a registry of kinds, each a template of fixed zones our code draws. W2-1 builds the frame and the
// `invoice` kind in two views: `sheet` (the invoice as a document: head, goods lines, the rows) and `cascade` (the same rows as a waterfall,
// with the fence around the imponibile). The other kinds are W2-2 drafts the registry holds back. The rows are computed by lesson/lib/money
// from the data (never written by the agent); with `error` the figure is drawn as that typical error computes it.
//
// A hidden row (hide) is drawn as an empty dashed box with a "?", and describe() and printed() say "da calcolare": the value is never
// read, so a hidden amount does not reach the description, the speech or the labels (L10). A cascade cannot hide a row (its bars would show it).
// Below 560 px the sheet opens into zone cards in reading order (the goods lines stack); the rows are always label and amount on one line.
// Select targets: `zones` (seller, buyer, number, date, lines, costs) and `rows`.
import palette from "lesson/palette"
import schema from "lesson/diagram_schemas/document"
import * as N from "lesson/num"
import * as Money from "lesson/lib/money"
import { effectiveState, fail, finish, label, roleInfo, shape, stateCount } from "lesson/diagrams/common"
import { run } from "lesson/diagrams/run"

export const type = "document"
export { schema }

export const IT = {
  gross: "Merce (lordo)", discounts: "Sconti", net: "Netto merce", costs_in: "Spese del venditore", base: "Imponibile", vat: "IVA",
  costs_out: "Spese anticipate per il cliente", interest: "Interessi", total: "Totale fattura",
  seller: "Chi vende", buyer: "Chi compra", invoice: "Fattura", invoice_n: "Fattura n. %{n}", error_title: "Fattura con un errore", date: "del %{date}",
  goods: "Merce", qty: "Quantità", price: "Prezzo", amount: "Importo", vat_col: "IVA", blank: "da calcolare",
  months: ["gennaio", "febbraio", "marzo", "aprile", "maggio", "giugno", "luglio", "agosto", "settembre", "ottobre", "novembre", "dicembre"]
}
const ROW_ROLE = { discounts: "discount", base: "base", vat: "tax", costs_out: "outside" }
const FENCE_ROWS = ["net", "costs_in", "base"]
const AMOUNT = /\d{1,3}(?:\.\d{3})*,\d{2}|\d+,\d{2}/g
const euro = (text) => `€ ${Money.display(text)}`

export const states = (data) => stateCount(data)

// ---- what the figure says -----------------------------------------------------------------------------------

// The rows that matter for this invoice, in our fixed order (the same as Lessons::Diagrams::Document.shown_rows).
export function defaultRows(eff) {
  const costs = eff.costs ?? []
  return Money.ROWS.filter((id) => {
    if (id === "discounts") return (eff.discounts ?? []).length > 0
    if (id === "costs_in") return costs.some((k) => !k.documented)
    if (id === "costs_out") return costs.some((k) => k.documented)
    if (id === "interest") return !!eff.interest
    return true
  })
}

const rowsOf = (eff) => eff.rows ?? defaultRows(eff)
const inputsOf = (eff) => ({ lines: eff.lines, discounts: eff.discounts, costs: eff.costs, interest: eff.interest, error: eff.error })

// { lines, rows } from the data; null when Money refuses it (the semantic check has said why)
function compute(eff) {
  try {
    return Money.invoice(inputsOf(eff))
  } catch (_error) {
    return null
  }
}

function dateIt(iso) {
  const m = /^(\d{4})-(\d{2})-(\d{2})$/.exec(iso ?? "")
  return m ? `${Number(m[3])} ${IT.months[Number(m[2]) - 1]} ${m[1]}` : ""
}

function rowLabel(id, eff) {
  if (id === "vat") {
    const rates = [...new Set((eff.lines ?? []).map((l) => l.vat))]
    return rates.length === 1 ? `${IT.vat} ${rates[0]}%` : IT.vat
  }
  if (id === "discounts") {
    const d = eff.discounts ?? []
    if (d.length === 1) return `Sconto ${d[0]}%`
    return d.length > 1 ? `Sconti ${d.slice(0, -1).map((x) => `${x}%`).join(", ")} e ${d[d.length - 1]}%` : IT.discounts
  }
  if (id === "interest" && eff.interest) return `${IT.interest} ${eff.interest.rate}%`
  return IT[id]
}

// ---- the checks the browser repeats (the same as Lessons::Diagrams::Document) ---------------------------------

export function semantic(data) {
  const bad = (path, message, code = "E-LESSON-DIAGRAM") => ({ path, message, code })
  if (data.kind !== "invoice") return bad("/kind", `${data.kind} is not available yet`)
  const lines = data.lines ?? []
  if (lines.length === 0) return bad("/lines", "an invoice has at least one goods line")
  for (let i = 0; i < lines.length; i++) {
    if (!Money.RATES.includes(lines[i].vat)) return bad(`/lines/${i}/vat`, "the VAT rate is not one of the programme")
    for (const key of ["qty", "price"]) {
      const v = N.parse(lines[i][key])
      if (!v || v.n <= 0n) return bad(`/lines/${i}/${key}`, `${key} is a number over 0`)
    }
  }
  const discounts = data.discounts ?? []
  for (let i = 0; i < discounts.length; i++) {
    const v = N.parse(discounts[i])
    if (!v || v.n <= 0n || N.compare(v, N.int(100)) >= 0) return bad(`/discounts/${i}`, "a discount is a percentage over 0 and under 100")
  }
  const costs = data.costs ?? []
  for (let i = 0; i < costs.length; i++) {
    const v = N.parse(costs[i].amount)
    if (!v || v.n <= 0n) return bad(`/costs/${i}/amount`, "a cost is an amount over 0")
  }
  if (new Set(lines.map((l) => l.vat)).size > 1 && costs.some((k) => !k.documented)) return bad("/costs", "with two VAT rates a cost that is not documented has no rate")
  if (data.interest) {
    const v = N.parse(data.interest.rate)
    if (!v || v.n <= 0n) return bad("/interest/rate", "the interest rate is a percentage over 0")
  }
  const hiddenAnywhere = [data, ...(data.states ?? [])].some((s) => (s.hide ?? []).length > 0)
  if (data.view === "cascade" && hiddenAnywhere) return bad("/view", "a cascade has no hidden rows: its bars would show the value")
  for (let s = 0; s < stateCount(data); s++) {
    const where = (data.states ?? []).length === 0 ? "" : `/states/${s}`
    const eff = effectiveState(data, s)
    for (const key of ["rows", "hide", "mark"]) {
      const list = eff[key] ?? []
      for (let i = 0; i < list.length; i++) if (!Money.ROWS.includes(list[i])) return bad(`${where}/${key}/${i}`, `${list[i]} is not a row of an invoice`)
    }
  }
  if (data.head?.date && new Date(`${data.head.date}T00:00:00Z`).toISOString().slice(0, 10) !== data.head.date) return bad("/head/date", "not a date that exists")
  let right
  try {
    right = Money.invoice(inputsOf({ ...data, error: undefined }))
    if (data.error) {
      const wrong = Money.invoice(inputsOf(data))
      if (JSON.stringify(wrong.rows) === JSON.stringify(right.rows)) return bad("/error", `${data.error} changes nothing on this invoice`)
    }
  } catch (error) {
    return bad(data.error ? "/error" : "/lines", error.message)
  }
  return altAmounts(data, right)
}

// Every euro amount of alt_it and caption_it is a row or a line the figure computes, or an amount written in the data; none is a hidden row's.
function altAmounts(data, right) {
  const shown = Money.invoice(inputsOf(data))
  const known = new Set([...Object.values(shown.rows), ...shown.lines, ...(data.lines ?? []).map((l) => l.price), ...(data.costs ?? []).map((k) => k.amount)].map((s) => String(s).replaceAll(".", "")))
  const hiddenIds = new Set([data, ...(data.states ?? [])].flatMap((s) => s.hide ?? []))
  const hidden = new Set([...hiddenIds].map((id) => shown.rows[id]).filter(Boolean).map((s) => s.replaceAll(".", "")))
  void right
  for (const key of ["alt_it", "caption_it"]) {
    for (const text of String(data[key] ?? "").match(AMOUNT) ?? []) {
      const flat = text.replaceAll(".", "")
      if (hidden.has(flat)) return { path: `/${key}`, message: `${text} is the amount of a hidden row`, code: "E-LESSON-ALT" }
      if (!known.has(flat)) return { path: `/${key}`, message: `${text} is not an amount of the invoice`, code: "E-LESSON-ALT" }
    }
  }
  return null
}

// ---- layout ---------------------------------------------------------------------------------------------------

export function layout(data, opts) {
  return run(data, opts, { schema, semantic, build: (d, ctx) => build(d, ctx, opts) })
}

function build(data, ctx, opts) {
  const eff = effectiveState(data, ctx.state)
  const calc = compute(eff)
  if (!calc) return fail("/lines", "the invoice cannot be computed", "E-LESSON-DIAGRAM")
  const view = { calc, eff, select: opts?.mode === "select", hidden: new Set(eff.hide ?? []), marks: new Set(eff.mark ?? []), shown: rowsOf(eff) }
  return eff.view === "cascade" ? cascade(ctx, view) : sheet(ctx, view)
}

const strongCls = (id) => (id === "total" ? " dg-doc-strong" : "")

// A label with the room it needs; returns it with its box.
function put(ctx, text, x, y, o = {}) {
  return label(ctx, text, x, y, { anchor: o.anchor ?? "start", maxW: o.maxW, cls: o.cls ?? "" })
}

// A tap area for the select check (mode "select" only): the stored target id travels on the shape.
function hit(ctx, v, key, x, y, w, h) {
  if (v.select) shape(ctx, "rect", { x, y, w, h, r: 4, cls: "dg-hit-area", target: key, key: `t:${key}` })
}

const roleCls = (ctx, role) => (roleInfo(palette, ctx.subject, role) ? role : "muted")

function marker(ctx, id, x, y, size) {
  const role = ROW_ROLE[id]
  const info = role && roleInfo(palette, ctx.subject, role)
  if (!info) return
  shape(ctx, "marker", { shape: info.shape ?? "square", x, y, w: size, h: size, cls: `mk-${role}`, key: `m:${id}` })
}

// The title and the date of the sheet.
function head(ctx, v, y) {
  const { eff } = v
  const W = ctx.width
  const lh = ctx.lineH
  const pad = ctx.pad
  const title = eff.error ? IT.error_title : eff.head?.number ? IT.invoice_n.replace("%{n}", eff.head.number) : IT.invoice
  const sub = eff.error && eff.head?.number ? IT.invoice_n.replace("%{n}", eff.head.number) : null
  const date = eff.head?.date ? IT.date.replace("%{date}", dateIt(eff.head.date)) : null
  const together = date && W >= 560 && ctx.measure(title, ctx.fontPx).w + ctx.measure(date, ctx.fontPx).w + 3 * pad <= W
  const t = put(ctx, title, pad, y, { cls: "dg-doc-title", maxW: W - 2 * pad - (together ? ctx.measure(date, ctx.fontPx).w + pad : 0) })
  let bottom = t.y + t.h
  if (eff.head?.number) hit(ctx, v, "number", 0, y - pad / 2, together ? W / 2 : W, bottom - y + pad)
  if (sub) bottom = put(ctx, sub, pad, bottom, { cls: "dg-doc-sub" }).y + lh
  if (date) {
    const d = together ? put(ctx, date, W - pad, y, { anchor: "end", cls: "dg-doc-sub" }) : put(ctx, date, pad, bottom, { cls: "dg-doc-sub" })
    hit(ctx, v, "date", together ? W / 2 : 0, d.y - pad / 2, together ? W / 2 : W, d.h + pad)
    if (!together) bottom = d.y + d.h
  }
  shape(ctx, "line", { x1: 0, y1: bottom + pad, x2: W, y2: bottom + pad, cls: "dg-doc-rule" })
  return bottom + pad * 2
}

function parties(ctx, v, y) {
  const { eff } = v
  const W = ctx.width
  const pad = ctx.pad
  const items = [["seller", eff.head?.seller_it, "creditor"], ["buyer", eff.head?.buyer_it, "debtor"]].filter(([, name]) => name)
  if (items.length === 0) return y
  const wide = W >= 560
  const gap = pad * 2
  const colW = wide ? (W - 2 * pad - gap * (items.length - 1)) / items.length : W - 2 * pad
  let cursor = y
  items.forEach(([key, name, role], i) => {
    const x = wide ? pad + i * (colW + gap) : pad
    const top = wide ? y : cursor
    const cap = put(ctx, IT[key], x + pad, top + pad, { cls: "dg-doc-cap", maxW: colW - 2 * pad })
    const nm = put(ctx, name, x + pad, cap.y + cap.h, { cls: "dg-doc-name", maxW: colW - 2 * pad })
    const h = nm.y + nm.h + pad - top
    shape(ctx, "rect", { x, y: top, w: colW, h, r: 10, cls: `dg-doc-box st-${roleCls(ctx, role)}`, key: `z:${key}` })
    hit(ctx, v, key, x, top, colW, h)
    cursor = wide ? Math.max(cursor, top + h) : top + h + gap
  })
  return cursor + (wide ? gap : 0)
}

// The goods lines: a table from 560 px, a card per line below.
function lines(ctx, v, y) {
  const { eff, calc } = v
  const W = ctx.width
  const f = ctx.fontPx
  const pad = ctx.pad
  const gap = pad * 2
  const start = y
  if (W >= 560) {
    const m = (text) => ctx.measure(text, f).w
    const wIva = Math.max(m(IT.vat_col), m("22%"))
    const wAmount = Math.max(m(IT.amount), m("€ 99.999,99"))
    const wPrice = Math.max(m(IT.price), m("€ 9.999,99"))
    const wQty = Math.max(m(IT.qty), m("9.999"))
    const xIva = W - pad
    const xAmount = xIva - wIva - gap
    const xPrice = xAmount - wAmount - gap
    const xQty = xPrice - wPrice - gap
    const descW = xQty - wQty - gap - pad
    if (descW >= 7 * f) {
      put(ctx, IT.goods, pad, y, { cls: "dg-doc-cap" })
      put(ctx, IT.qty, xQty, y, { anchor: "end", cls: "dg-doc-cap" })
      put(ctx, IT.price, xPrice, y, { anchor: "end", cls: "dg-doc-cap" })
      put(ctx, IT.amount, xAmount, y, { anchor: "end", cls: "dg-doc-cap" })
      put(ctx, IT.vat_col, xIva, y, { anchor: "end", cls: "dg-doc-cap" })
      y += ctx.lineH + pad / 2
      shape(ctx, "line", { x1: 0, y1: y, x2: W, y2: y, cls: "dg-doc-rule" })
      y += pad
      eff.lines.forEach((l, i) => {
        const d = put(ctx, l.text_it, pad, y, { maxW: descW })
        put(ctx, l.qty, xQty, y, { anchor: "end" })
        put(ctx, euro(Money.roundHalfUp(l.price)), xPrice, y, { anchor: "end" })
        put(ctx, euro(calc.lines[i]), xAmount, y, { anchor: "end" })
        put(ctx, `${l.vat}%`, xIva, y, { anchor: "end" })
        y += Math.max(d.h, ctx.lineH) + pad
      })
      hit(ctx, v, "lines", 0, start, W, y - start)
      return y
    }
  }
  eff.lines.forEach((l, i) => {
    const top = y
    const inner = W - 4 * pad
    const d = put(ctx, l.text_it, 2 * pad, top + pad, { maxW: inner, cls: "dg-doc-name" })
    const sum = put(ctx, `${l.qty} × ${euro(Money.roundHalfUp(l.price))} = ${euro(calc.lines[i])}`, 2 * pad, d.y + d.h, { maxW: inner })
    const iva = put(ctx, `${IT.vat} ${l.vat}%`, 2 * pad, sum.y + sum.h, { cls: "dg-doc-sub" })
    const h = iva.y + iva.h + pad - top
    shape(ctx, "rect", { x: pad, y: top, w: W - 2 * pad, h, r: 10, cls: "dg-doc-box st-muted", key: `line:${i}` })
    y = top + h + pad
  })
  hit(ctx, v, "lines", 0, start, W, y - start)
  return y
}

// The costs of the invoice under the goods: the seller's own and the ones advanced in the buyer's name.
function costsList(ctx, v, y) {
  const costs = v.eff.costs ?? []
  if (costs.length === 0) return y
  const W = ctx.width
  const pad = ctx.pad
  const start = y
  const amountW = ctx.measure("€ 9.999,99", ctx.fontPx).w
  costs.forEach((k) => {
    const d = put(ctx, `${k.text_it} (${k.documented ? "anticipata" : "del venditore"})`, pad, y, { maxW: W - 2 * pad - amountW - 2 * pad })
    put(ctx, euro(Money.roundHalfUp(k.amount)), W - pad, y, { anchor: "end" })
    y += Math.max(d.h, ctx.lineH) + pad
  })
  hit(ctx, v, "costs", 0, start, W, y - start)
  return y
}

// The fence and the marks, drawn once the rows have their places: spans is {row id => [top, bottom]}.
function fences(ctx, v, spans) {
  const pad = ctx.pad
  const W = ctx.width
  const fenced = FENCE_ROWS.filter((id) => spans.has(id))
  if (v.marks.has("base") && fenced.length > 0) {
    const top = spans.get(fenced[0])[0] - pad / 2
    const bottom = spans.get(fenced[fenced.length - 1])[1] + pad / 2
    shape(ctx, "rect", { x: 2, y: top, w: W - 4, h: bottom - top, r: 8, cls: "dg-doc-fence st-base", key: "fence" })
  }
  for (const id of v.marks) {
    if (id === "base" || !spans.has(id)) continue
    const [a, b] = spans.get(id)
    shape(ctx, "rect", { x: 2, y: a - pad / 2, w: W - 4, h: b - a + pad, r: 8, cls: "dg-doc-mark", key: `mark:${id}` })
  }
}

function summary(ctx, v, y) {
  const { calc } = v
  const W = ctx.width
  const pad = ctx.pad
  const f = ctx.fontPx
  const amountW = ctx.measure("€ 99.999,99", f).w
  const edge = pad * 1.5 // room for the fence and the marks around the rows
  const labelW = W - 2 * edge - amountW - 3 * pad
  const mark = Math.round(f * 0.7)
  const spans = new Map()
  shape(ctx, "line", { x1: 0, y1: y, x2: W, y2: y, cls: "dg-doc-rule" })
  y += pad
  for (const id of v.shown) {
    const top = y
    const offset = ROW_ROLE[id] && roleInfo(palette, ctx.subject, ROW_ROLE[id]) ? mark + pad : 0
    const l = put(ctx, rowLabel(id, v.eff), edge + offset, top, { maxW: labelW - offset, cls: strongCls(id) })
    marker(ctx, id, edge, top + (ctx.lineH - mark) / 2, mark)
    if (v.hidden.has(id)) {
      shape(ctx, "rect", { x: W - edge - amountW, y: top, w: amountW, h: ctx.lineH, r: 6, cls: "dg-doc-blank", key: `b:${id}` })
      put(ctx, "?", W - edge - amountW / 2, top, { anchor: "middle", cls: "dg-doc-q" })
    } else {
      put(ctx, euro(calc.rows[id]), W - edge, top, { anchor: "end", cls: strongCls(id) })
    }
    const h = Math.max(l.h, ctx.lineH)
    spans.set(id, [top, top + h])
    hit(ctx, v, id, 0, top - pad / 2, W, h + pad)
    y = top + h + pad
    shape(ctx, "line", { x1: 0, y1: y - pad / 2, x2: W, y2: y - pad / 2, cls: "dg-doc-rule dg-doc-rule-soft" })
  }
  fences(ctx, v, spans)
  return y
}

function sheet(ctx, v) {
  let y = ctx.pad
  y = head(ctx, v, y)
  y = parties(ctx, v, y)
  y = lines(ctx, v, y)
  y = costsList(ctx, v, y)
  y = summary(ctx, v, y + ctx.pad)
  return finish(ctx, y + ctx.pad, { sheet: true })
}

// ---- the cascade ------------------------------------------------------------------------------------------------

const num = (text) => N.toNumber(N.parse(text))

// The segment [from, to] of each row on the euro scale: take away, then add.
function segments(rows) {
  const v = Object.fromEntries(Money.ROWS.map((id) => [id, num(rows[id])]))
  return {
    gross: [0, v.gross],
    discounts: [v.net, v.net + v.discounts],
    net: [0, v.net],
    costs_in: [v.net, v.net + v.costs_in],
    base: [0, v.base],
    vat: [v.base, v.base + v.vat],
    costs_out: [v.base + v.vat, v.base + v.vat + v.costs_out],
    interest: [v.base + v.vat + v.costs_out, v.base + v.vat + v.costs_out + v.interest],
    total: [0, v.total]
  }
}

const BAR_ROLE = { gross: "muted", discounts: "discount", net: "muted", costs_in: "base", base: "base", vat: "tax", costs_out: "outside", interest: "muted", total: "muted" }

function cascade(ctx, v) {
  const { calc } = v
  const W = ctx.width
  const pad = ctx.pad
  const f = ctx.fontPx
  const seg = segments(calc.rows)
  const max = Math.max(1, ...Money.ROWS.map((id) => Math.max(seg[id][0], seg[id][1])))
  const side = W >= 700
  const amountW = ctx.measure("€ 99.999,99", f).w
  const edge = pad * 1.5 // room for the fence around the rows
  const labelW = side ? Math.min(W * 0.36, ctx.measure("Spese anticipate per il cliente", f).w + pad) : 0
  const x0 = edge + labelW + (side ? pad : 0)
  const x1 = W - edge - (side ? amountW + pad : 0)
  const barH = Math.round(f * 1.1)
  let y = pad
  const spans = new Map()
  for (const id of v.shown) {
    const top = y
    const text = rowLabel(id, v.eff)
    const l = put(ctx, text, edge, top, { maxW: side ? labelW : W - 2 * edge - amountW - pad, cls: strongCls(id) })
    put(ctx, euro(calc.rows[id]), W - edge, top, { anchor: "end", cls: strongCls(id) })
    const [a, b] = seg[id]
    const left = x0 + (Math.min(a, b) / max) * (x1 - x0)
    const width = Math.max(3, (Math.abs(b - a) / max) * (x1 - x0))
    const by = side ? top + Math.max(0, (l.h - barH) / 2) : top + l.h + 2
    const role = roleCls(ctx, BAR_ROLE[id])
    const cls = id === "discounts" ? `dg-doc-bar dg-doc-removed st-${role}` : `dg-doc-bar mk-${role}`
    shape(ctx, "rect", { x: left, y: by, w: width, h: barH, r: 5, cls, key: `bar:${id}` })
    const bottom = Math.max(top + l.h, by + barH)
    spans.set(id, [top, bottom])
    hit(ctx, v, id, 0, top - pad / 2, W, bottom - top + pad)
    y = bottom + pad * 1.5
  }
  fences(ctx, v, spans)
  return finish(ctx, y, { cascade: true })
}

// ---- what is said, read and printed -------------------------------------------------------------------------------

// The Italian reading of the state that is visible (default: the first). A hidden row is "da calcolare", its amount is never read (L10).
export function describe(data, ctx = {}) {
  const eff = effectiveState(data, ctx.state ?? 0)
  const calc = compute(eff)
  if (!calc) return data.alt_it ?? ""
  const hidden = new Set(eff.hide ?? [])
  const parts = []
  const who = [eff.head?.seller_it ? `${IT.seller.toLowerCase()}: ${eff.head.seller_it}` : null, eff.head?.buyer_it ? `${IT.buyer.toLowerCase()}: ${eff.head.buyer_it}` : null].filter(Boolean)
  parts.push(`${eff.error ? IT.error_title : IT.invoice}${eff.head?.number ? ` numero ${eff.head.number}` : ""}${eff.head?.date ? ` ${IT.date.replace("%{date}", dateIt(eff.head.date))}` : ""}${who.length ? `. ${who.join("; ")}` : ""}.`)
  eff.lines.forEach((l, i) => parts.push(`${l.text_it}: ${l.qty} per ${euro(Money.roundHalfUp(l.price))}, ${euro(calc.lines[i])}, IVA ${l.vat}%.`))
  for (const k of eff.costs ?? []) parts.push(`${k.text_it}: ${euro(Money.roundHalfUp(k.amount))}, ${k.documented ? "anticipata" : "del venditore"}.`)
  const rows = rowsOf(eff).map((id) => `${rowLabel(id, eff)}: ${hidden.has(id) ? IT.blank : euro(calc.rows[id])}`)
  parts.push(`Righe. ${rows.join("; ")}.`)
  if (eff.view === "cascade") parts.push("Le righe sono disegnate come una cascata: prima si toglie, poi si aggiunge.")
  if ((eff.mark ?? []).includes("base")) parts.push("Un recinto tratteggiato racchiude le righe che formano l'imponibile.")
  if (stateCount(data) > 1) parts.push(`La figura ha ${stateCount(data)} passi.`)
  return parts.join(" ")
}

// Every string the state prints, describe() included; a hidden row's amount is not among them (L4).
export function printed(data, state = 0) {
  const eff = effectiveState(data, state)
  const calc = compute(eff)
  const out = [describe(data, { state }), data.alt_it, data.caption_it, eff.op_it].filter(Boolean)
  if (!calc) return out
  const hidden = new Set(eff.hide ?? [])
  const head = eff.head ?? {}
  out.push(...[head.seller_it, head.buyer_it, head.number, head.date].filter(Boolean))
  eff.lines.forEach((l, i) => out.push(l.text_it, l.qty, l.price, l.vat, calc.lines[i]))
  for (const k of eff.costs ?? []) out.push(k.text_it, k.amount)
  for (const id of rowsOf(eff)) if (!hidden.has(id)) out.push(calc.rows[id])
  return out.map(String)
}

// The select targets of a set in reading order: the same keys as Lessons::Diagrams::Document.targets. The boxes come from the Scene's
// shapes[].target (mode "select").
export function targets(data, set) {
  const eff = effectiveState(data, 0)
  if (set === "rows") return rowsOf(eff).map((key, i) => ({ key, bbox: null, neutral_it: `riga ${i + 1}` }))
  if (set !== "zones") throw new Error(`document has no select set ${set}`)
  const h = eff.head ?? {}
  const keys = []
  if (h.seller_it) keys.push("seller")
  if (h.buyer_it) keys.push("buyer")
  if (h.number) keys.push("number")
  if (h.date) keys.push("date")
  keys.push("lines")
  if ((eff.costs ?? []).length > 0) keys.push("costs")
  return keys.map((key, i) => ({ key, bbox: null, neutral_it: `zona ${i + 1}` }))
}
