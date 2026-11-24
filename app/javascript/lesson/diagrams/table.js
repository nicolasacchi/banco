// table (A8): drawn as an HTML table by draw.js (the Scene carries the cells; nothing is positioned).
import { plain, stateCount, words } from "lesson/diagrams/common"
import { run } from "lesson/diagrams/run"

export const states = () => 1

export function semantic(data) {
  for (let i = 0; i < data.rows.length; i++) {
    if (data.rows[i].length !== data.header.length) return { path: `/rows/${i}`, message: "every row has as many cells as the header", code: "E-LESSON-BLOCK" }
  }
  return null
}

function build(data, ctx) {
  // a bilingual lesson's table (D-402) brings its Italian cells (header_it, rows_it), which tableNode draws under the target text
  const italian = data.header_it ? { header_it: data.header_it, rows_it: data.rows_it } : {}
  const material = data.translate_material === false ? { translate_material: false } : {} // forms with no Italian (D-402): tableNode draws no translation for them
  return { width: ctx.width, height: 0, shapes: [], labels: [], states: 1, state: 0, table: { header: data.header, rows: data.rows, ...italian, ...material } }
}

export function describe(data) {
  const rows = data.rows.map((r) => r.map((c, i) => `${plain(data.header[i])}: ${plain(c)}`).join("; "))
  return `Una tabella con le colonne ${data.header.map(plain).join(", ")}. ${rows.map((r, i) => `Riga ${i + 1}. ${r}.`).join(" ")}`
}

export { stateCount, words }
export const layout = (data, opts) => run(data, opts, { semantic, build })
