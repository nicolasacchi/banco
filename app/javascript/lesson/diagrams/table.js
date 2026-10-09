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
  return { width: ctx.width, height: 0, shapes: [], labels: [], states: 1, state: 0, table: { header: data.header, rows: data.rows } }
}

export function describe(data) {
  const rows = data.rows.map((r) => r.map((c, i) => `${plain(data.header[i])}: ${plain(c)}`).join("; "))
  return `Una tabella con le colonne ${data.header.map(plain).join(", ")}. ${rows.map((r, i) => `Riga ${i + 1}. ${r}.`).join(" ")}`
}

export { stateCount, words }
export const layout = (data, opts) => run(data, opts, { semantic, build })
