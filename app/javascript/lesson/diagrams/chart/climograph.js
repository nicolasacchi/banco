// climograph (T6, WAVE2 2.4; geography 3.2): twelve months of rain as bars and of temperature as a line, on the Bagnouls-Gaussen scale that
// our code fixes (the mm axis is twice the degrees axis, zeros aligned). Rain above 100 mm falls in a marked band with a smaller scale, as
// Walter and Lieth draw it, so a monsoon still fits. The arid months (P <= 2T), the range, the total and the extremes are computed here,
// never author data (1.1). One scale at a time: the states add the layers in order, and the axis of a layer that is not shown is not drawn.
// Ruby twin: Lessons::Diagrams::Climograph; shared vectors: test/fixtures/lesson2/climate.json and test/fixtures/diagrams/types/climograph.json.
import * as N from "lesson/num"
import schema from "lesson/diagram_schemas/climograph"
import { effectiveState, finish, label, listIt, plain, shape, stateCount } from "lesson/diagrams/common"
import { run } from "lesson/diagrams/run"
import { ABBR, INITIALS, MONTHS, monthList, stats } from "lesson/diagrams/chart/climate"
import { authorValue, formatValue } from "lesson/diagrams/chart/format"
import { linear, valueTable } from "lesson/diagrams/chart/axis"

export const type = "climograph"
export { schema }
export const states = stateCount

const TEMP_RANGE = [-60, 45]
const PRECIP_RANGE = [0, 1500]
const BAND = 100 // mm: above it the scale is smaller

const layersOf = (eff) => new Set(eff.show ?? ["bars", "line"])
const numbers = (list) => list.map((v) => N.parse(v))
const inRange = (v, [lo, hi]) => v !== null && N.toNumber(v) >= lo && N.toNumber(v) <= hi
const num = (x, places) => formatValue(x, places)

export function semantic(data) {
  if (!data.temp || !data.precip) return { path: "/station", message: `${data.station ?? "the station"} is not resolved: the server puts the numbers of a station in the page`, code: "E-LESSON-DATA" }
  for (const [key, range] of [["temp", TEMP_RANGE], ["precip", PRECIP_RANGE]]) {
    for (let i = 0; i < 12; i++) if (!inRange(N.parse(data[key][i]), range)) return { path: `/${key}/${i}`, message: `${data[key][i]} is outside ${range[0]} to ${range[1]}` }
  }
  if (data.compare) {
    if (!data.compare.temp) return { path: "/compare/station", message: "the second station is not resolved", code: "E-LESSON-DATA" }
    for (let i = 0; i < 12; i++) if (!inRange(N.parse(data.compare.temp[i]), TEMP_RANGE)) return { path: `/compare/temp/${i}`, message: "a compared temperature is outside -60 to 45" }
  }
  if (data.lat !== undefined && Math.abs(N.toNumber(N.parse(data.lat))) > 90) return { path: "/lat", message: "lat is a latitude between -90 and 90" }
  for (let i = 0; i < stateCount(data); i++) {
    const show = layersOf(effectiveState(data, i))
    const where = data.states ? `/states/${i}/show` : "/show"
    if (show.has("arid") && !(show.has("bars") && show.has("line"))) return { path: where, message: "arid needs bars and line in the same state" }
    if (show.has("range") && !show.has("line")) return { path: where, message: "range needs the line" }
    if (show.has("total") && !show.has("bars")) return { path: where, message: "total needs the bars" }
  }
  return null
}

function parts(eff) {
  const temp = numbers(eff.temp)
  const precip = numbers(eff.precip)
  return { temp, precip, s: stats(temp, precip), show: layersOf(eff) }
}

function build(data, ctx) {
  const eff = effectiveState(data, ctx.state)
  const { temp, precip, s, show } = parts(eff)
  const select = ctx.mode === "select"
  const f = ctx.fontPx
  const W = ctx.width
  const tN = temp.map(N.toNumber)
  const pN = precip.map(N.toNumber)
  const cmp = eff.compare?.temp ? numbers(eff.compare.temp).map(N.toNumber) : null
  // a select figure answers nothing: the computed layers stay out of it
  if (select) for (const k of ["arid", "range", "total"]) show.delete(k)

  // ---- the scale: degrees on the left, millimetres on the right (twice the degrees), zeros aligned
  // (a figure that never shows the rain is scaled to its temperatures alone)
  const everBars = [data, ...(data.states ?? [])].some((e) => layersOf({ ...data, ...e }).has("bars"))
  const allT = cmp ? [...tN, ...cmp] : tN
  const maxP = everBars ? Math.max(...pN) : 0
  const bottomU = Math.min(0, Math.floor(Math.min(...allT) / 10) * 10)
  const banded = maxP > BAND
  const topU = banded ? BAND / 2 : Math.max(20, Math.ceil(Math.max(Math.max(...allT), maxP / 2) / 10) * 10)
  const bandTop = banded ? Math.ceil(maxP / 100) * 100 : BAND
  const plotH = Math.round(Math.min(Math.max(14 * f, W * 0.42), 22 * f))
  const bandH = banded ? Math.round(plotH * 0.23) : 0
  const mainH = plotH - bandH
  const axisT = linear({ min: String(bottomU), max: String(topU), length: mainH, fontPx: f, measure: ctx.measure, orient: "y", nice: false })
  const unit = (t) => Number(t.value.replace(",", "."))
  const rightTicks = axisT.ticks.map((t) => ({ u: unit(t), text: formatValue(String(unit(t) * 2)) }))
  const widest = (labels) => Math.max(0, ...labels.map((t) => ctx.measure(t, f).w))
  // the margins hold the tick labels and the axis titles ("°C", "mm") that stand over them
  const mL = Math.ceil(widest([...axisT.ticks.map((t) => t.label), "°C"])) + 8
  const mR = Math.ceil(widest([...rightTicks.map((t) => t.text), formatValue(String(bandTop)), "mm"])) + 8
  const x0 = mL
  const x1 = W - mR
  const slot = (x1 - x0) / 12
  const top = ctx.lineH + Math.ceil(ctx.lineH / 2) + 6
  const yOf = (u) => top + bandH + ((topU - u) / (topU - bottomU)) * mainH // u in degrees; a mm value p sits at p / 2
  const yP = (p) => (p <= BAND ? yOf(p / 2) : top + bandH - ((p - BAND) / (bandTop - BAND)) * bandH)
  const yZero = yOf(0)
  const cx = (i) => x0 + (i + 0.5) * slot

  // axis titles: only the axes of the layers that are shown
  const showT = show.has("line")
  const showP = show.has("bars")
  if (showT) label(ctx, "°C", mL - 4, 0, { anchor: "end", cls: "dgc-axis-title" })
  if (showP) label(ctx, "mm", x1 + 4, 0, { anchor: "start", cls: "dgc-axis-title" })

  // plot background, the band above 100 mm, grid lines and the left axis
  shape(ctx, "rect", { x: x0, y: top, w: x1 - x0, h: plotH, r: 0, cls: "dgc-plot" })
  if (banded) {
    shape(ctx, "rect", { x: x0, y: top, w: x1 - x0, h: bandH, r: 0, cls: "dgc-band" })
    shape(ctx, "line", { x1: x0, y1: yOf(BAND / 2), x2: x1, y2: yOf(BAND / 2), cls: "dgc-junction" })
  }
  for (const t of axisT.ticks) {
    const y = yOf(unit(t))
    if (showT) label(ctx, t.label, mL - 4, y, { anchor: "end", valign: "middle", cls: "dgc-tick" })
    shape(ctx, "line", { x1: x0, y1: y, x2: x1, y2: y, cls: "dg-grid" })
  }
  // the right axis: the degrees ticks doubled, the junction (100) and the top of the band; a label that would touch another is left out
  if (showP) {
    const placed = []
    const put = (text, y) => {
      const h = ctx.measure(text, f).h
      if (placed.some((p) => Math.abs(p.y - y) < (p.h + h) / 2 + 4)) return
      placed.push({ y, h })
      label(ctx, text, x1 + 4, y, { anchor: "start", valign: "middle", cls: "dgc-tick" })
    }
    if (banded) {
      put(formatValue(String(bandTop)), yP(bandTop))
      put(formatValue(String(BAND)), yP(BAND))
    }
    for (const t of rightTicks) if (t.u >= 0 && t.u * 2 <= BAND) put(t.text, yOf(t.u))
  }
  shape(ctx, "line", { x1: x0, y1: yZero, x2: x1, y2: yZero, cls: "dg-axis" })

  const bw = Math.max(4, Math.min(slot * 0.62, 34))
  if (showP) {
    pN.forEach((p, i) => {
      if (p > 0) shape(ctx, "rect", { x: cx(i) - bw / 2, y: yP(p), w: bw, h: yZero - yP(p), r: 0, cls: "dgc-bar mk-precipitation", key: `bar${i}` })
    })
  }
  // the arid months: hatch between the bar and the line (the line is above the bar)
  if (show.has("arid")) {
    for (const m of s.arid) {
      const i = m - 1
      const yTop = Math.min(yOf(tN[i]), yZero)
      const yBot = Math.max(yP(pN[i]), yTop)
      if (yBot - yTop >= 1) shape(ctx, "rect", { x: cx(i) - slot / 2 + 1, y: yTop, w: slot - 2, h: yBot - yTop, r: 0, cls: "dgc-arid mk-arid", pattern: "hatch", key: `arid${i}` })
    }
  }
  // the range: guides from the two extremes to the left axis, and a bracket between them
  if (show.has("range")) {
    const yHi = yOf(N.toNumber(s.tmax))
    const yLo = yOf(N.toNumber(s.tmin))
    shape(ctx, "line", { x1: x0, y1: yHi, x2: cx(s.warmest - 1), y2: yHi, cls: "dgc-guide" })
    shape(ctx, "line", { x1: x0, y1: yLo, x2: cx(s.coldest - 1), y2: yLo, cls: "dgc-guide" })
    if (Math.abs(yLo - yHi) > 2) shape(ctx, "path", { d: `M${x0 + 7},${yHi} h-4 V${yLo} h4`, cls: "dgc-bracket st-temperature" })
  }
  // the temperature line with round dots, and the compared line (dashed, square dots)
  const lineOf = (values, cls, square) => {
    const pts = values.map((t, i) => [cx(i), yOf(t)])
    shape(ctx, "path", { d: `M${pts.map((p) => p.map((n) => n.toFixed(1)).join(",")).join(" L")}`, cls })
    for (const [x, y] of pts) {
      if (square) shape(ctx, "rect", { x: x - 4.5, y: y - 4.5, w: 9, h: 9, r: 0, cls: "dgc-dot-square mk-place" })
      else shape(ctx, "circle", { cx: x, cy: y, r: 4.5, cls: "dgc-dot mk-temperature" })
    }
  }
  if (showT) lineOf(tN, "dgc-line st-temperature", false)
  if (cmp && showT) lineOf(cmp, "dgc-line dgc-dashed st-place", true)
  if (show.has("range")) {
    for (const m of [s.warmest, s.coldest]) shape(ctx, "circle", { cx: cx(m - 1), cy: yOf(N.toNumber(m === s.warmest ? s.tmax : s.tmin)), r: 9, cls: "dgc-ring st-temperature" })
  }
  // the read cursor: a band over the month the student stepped to
  const asked = eff.read && ctx.mode === "student" ? Math.max(0, Math.min(12, Math.round(Number(ctx.controls?.month ?? 0)))) : 0
  const month = asked > 0 ? asked : null
  if (month) shape(ctx, "rect", { x: cx(month - 1) - slot / 2, y: top, w: slot, h: plotH, r: 0, cls: "dgc-cursor", key: "cursor" })
  // select targets: every month the same neutral column
  if (select) for (let i = 0; i < 12; i++) shape(ctx, "rect", { x: cx(i) - slot / 2, y: top, w: slot, h: plotH, r: 0, cls: "dgc-target", target: `t${i + 1}`, key: `target${i}` })

  // month letters (two staggered rows when the columns are narrower than the letters)
  const letterW = INITIALS.map((l) => ctx.measure(l, f).w)
  const stagger = letterW.some((w, i) => i > 0 && (w + letterW[i - 1]) / 2 + 6 > slot)
  let y = top + plotH + 4
  INITIALS.forEach((l, i) => label(ctx, l, cx(i), y + (stagger && i % 2 ? ctx.lineH : 0), { cls: "dgc-month", key: `month${i}` }))
  y += ctx.lineH * (stagger ? 2 : 1) + 6

  // legend: a swatch and a few words for each layer shown
  const items = []
  if (showP) items.push({ kind: "bars", text: "Pioggia (mm)" })
  if (showT) items.push({ kind: "line", text: "Temperatura (°C)" })
  if (cmp && showT) items.push({ kind: "cmp", text: `Temperatura: ${plain(eff.compare.place_it)}` })
  if (show.has("arid")) items.push({ kind: "arid", text: "Mese arido" })
  if (banded && showP) items.push({ kind: "band", text: `Sopra ${BAND} mm la scala è più piccola` })
  let rowX = 0
  let rowY = y
  let rowH = ctx.lineH
  for (const it of items) {
    const maxW = W - 30
    const m = ctx.measure(it.text, f, maxW)
    const w = 26 + Math.min(m.w, maxW) + 14
    if (rowX > 0 && rowX + w > W) {
      rowX = 0
      rowY += rowH + 4
      rowH = ctx.lineH
    }
    const sy = rowY + ctx.lineH / 2
    if (it.kind === "bars") shape(ctx, "rect", { x: rowX + 2, y: sy - 6, w: 16, h: 12, r: 0, cls: "mk-precipitation" })
    else if (it.kind === "line") {
      shape(ctx, "line", { x1: rowX, y1: sy, x2: rowX + 20, y2: sy, cls: "dgc-line st-temperature" })
      shape(ctx, "circle", { cx: rowX + 10, cy: sy, r: 4.5, cls: "dgc-dot mk-temperature" })
    } else if (it.kind === "cmp") {
      shape(ctx, "line", { x1: rowX, y1: sy, x2: rowX + 20, y2: sy, cls: "dgc-line dgc-dashed st-place" })
      shape(ctx, "rect", { x: rowX + 5.5, y: sy - 4.5, w: 9, h: 9, r: 0, cls: "dgc-dot-square mk-place" })
    } else if (it.kind === "arid") shape(ctx, "rect", { x: rowX + 2, y: sy - 6, w: 16, h: 12, r: 0, cls: "dgc-arid mk-arid", pattern: "hatch" })
    else shape(ctx, "rect", { x: rowX + 2, y: sy - 6, w: 16, h: 12, r: 0, cls: "dgc-band" })
    const l = label(ctx, it.text, rowX + 26, rowY, { anchor: "start", maxW, cls: "dgc-legend" })
    rowH = Math.max(rowH, l.h)
    rowX += w
  }
  y = rowY + (items.length ? rowH + 8 : 0)

  // computed lines
  const facts = []
  if (show.has("range")) {
    facts.push(`Il mese più caldo è ${MONTHS[s.warmest - 1]}: ${num(s.tmax)}\u00a0°C. Il più freddo è ${MONTHS[s.coldest - 1]}: ${num(s.tmin)}\u00a0°C.`)
    facts.push(`Escursione termica annua: ${num(s.range)}\u00a0°C.`)
  }
  if (show.has("total")) facts.push(`In un anno cadono ${num(s.total)}\u00a0mm di pioggia.`)
  for (const text of facts) y += label(ctx, text, 4, y, { anchor: "start", maxW: W - 8, cls: "dgc-fact" }).h + 4
  const live = month ? readout(eff, month, show, s) : undefined
  if (live) y += label(ctx, live, 4, y, { anchor: "start", maxW: W - 8, cls: "dgc-readout" }).h + 4

  // the numbers, for "Vedi i numeri" and for print (P2): only the layers that are shown
  const series = []
  if (showP) series.push({ label_it: "Pioggia (mm)", values: eff.precip })
  if (showT) series.push({ label_it: "Temperatura (°C)", values: eff.temp })
  if (cmp && showT) series.push({ label_it: `Temperatura: ${plain(eff.compare.place_it)}`, values: eff.compare.temp })
  const values = select ? undefined : valueTable(series, ABBR)
  return finish(ctx, y + 4, { states: stateCount(data), state: ctx.state, values, live, source: eff.source_it })
}

// the sentence the live region reads when the cursor stands on a month: only what the shown layers show
function readout(eff, month, show, s) {
  const name = MONTHS[month - 1]
  const bits = []
  if (show.has("bars")) bits.push(`pioggia ${num(N.parse(eff.precip[month - 1]))} millimetri`)
  if (show.has("line")) bits.push(`temperatura ${num(N.parse(eff.temp[month - 1]))} gradi`)
  const arid = show.has("arid") && s.arid.includes(month) ? " È un mese arido." : ""
  return `${name[0].toUpperCase()}${name.slice(1)}: ${bits.join(", ")}.${arid}`
}

// ---- the controls: the read cursor steps through the months (a stepper with - and +) ------------------------------------------------------------

export function controls(data) {
  const names = ["Nessuno", ...MONTHS.map((m) => `${m[0].toUpperCase()}${m.slice(1)}`)]
  return data?.read ? [{ id: "month", kind: "stepper", range: ["0", "12"], step: "1", value: 0, label_it: "Mese", values: names }] : []
}

// ---- select targets: the twelve months, in reading order -------------------------------------------------------------------------------------

export function targets(data, set) {
  if (set !== "months") return []
  const scene = layout(data, { width: 390, fontPx: 18, subject: "geography", state: 0, mode: "select" })
  if (scene.error) return []
  return scene.shapes.filter((sh) => sh.target).map((sh, i) => ({ key: sh.target, bbox: { x: sh.x, y: sh.y, w: sh.w, h: sh.h }, neutral_it: `Il mese di ${MONTHS[i]}` }))
}

// ---- what it prints (L4): the numbers of the shown layers and the computed lines, as an author writes them ----------------------------------------

export function printed(data, state = 0) {
  const eff = effectiveState(data, state)
  const { temp, precip, s, show } = parts(eff)
  const out = []
  if (show.has("line")) out.push(...temp)
  if (show.has("bars")) out.push(...precip)
  if (eff.compare?.temp) out.push(...numbers(eff.compare.temp))
  if (show.has("range")) out.push(s.range, s.tmax, s.tmin)
  if (show.has("total")) out.push(s.total)
  const seen = new Map()
  for (const x of out) seen.set(N.canonical(x), x)
  return [...seen.values()].sort(N.compare).map((x) => authorValue(x))
}

// ---- the description (the "Descrizione", screen readers, print) of what is visible -------------------------------------------------------------

function describeState(eff, index, total) {
  const { temp, precip, s, show } = parts(eff)
  const lat = eff.lat ? ` (latitudine ${formatValue(eff.lat).replace("−", "meno ")} gradi)` : ""
  const bits = [`Climogramma di ${plain(eff.place_it)}${lat}.`]
  if (show.has("bars")) {
    let wet = 0
    let dry = 0
    precip.forEach((p, i) => {
      if (N.compare(p, precip[wet]) > 0) wet = i
      if (N.compare(p, precip[dry]) < 0) dry = i
    })
    bits.push(`Le barre mostrano la pioggia di ogni mese, in millimetri. Il mese con più pioggia è ${MONTHS[wet]}: ${num(precip[wet])}. Quello con meno pioggia è ${MONTHS[dry]}: ${num(precip[dry])}.`)
  }
  if (show.has("line")) bits.push(`La linea mostra la temperatura di ogni mese, in gradi: da ${num(s.tmin)} a ${num(s.tmax)}.`)
  if (eff.compare?.temp && show.has("line")) bits.push(`La linea tratteggiata è la temperatura di ${plain(eff.compare.place_it)}.`)
  if (show.has("arid")) bits.push(s.arid.length ? `Mesi aridi, con la barra sotto la linea: ${monthList(s.arid)}.` : "Nessun mese è arido: la barra sta sempre sopra la linea.")
  if (show.has("range")) bits.push(`Il mese più caldo è ${MONTHS[s.warmest - 1]} (${num(s.tmax)} gradi), il più freddo è ${MONTHS[s.coldest - 1]} (${num(s.tmin)} gradi). L'escursione termica annua è ${num(s.range)} gradi.`)
  if (show.has("total")) bits.push(`In un anno cadono ${num(s.total)} millimetri di pioggia.`)
  void temp
  return `${total > 1 ? `Passo ${index + 1}. ` : ""}${bits.join(" ")}`
}

export function describe(data, ctx = {}) {
  const n = stateCount(data)
  if (typeof ctx?.state === "number") return describeState(effectiveState(data, ctx.state), ctx.state, n)
  const out = []
  for (let i = 0; i < n; i++) out.push(describeState(effectiveState(data, i), i, n))
  return listIt([out.join(" ")])
}

export const layout = (data, opts) => run(data, opts, { schema, semantic, build })
