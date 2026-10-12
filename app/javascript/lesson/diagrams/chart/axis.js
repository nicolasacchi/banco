// The chart axis engine (WAVE2 2.4; contract frozen in W2-0, built by T6): linear and log axes, bars from zero, ticks at the student's size
// (every other tick is dropped before any text shrinks, A3), a legend with patterns, a keyboard read cursor stepping by grid steps with the
// readout in a live region. climograph, seats, bar_model, chart and scale are all built on it; number_line also gets `log: true` (W2-3).
// Values are exact strings (lesson/num); pixels are the only floats.
import { notBuilt } from "lesson/lib/not_built"

// linear({ min, max, length, fontPx, measure, fromZero }) -> Axis
// log({ min, max, length, fontPx, measure }) -> Axis (ticks on powers of ten: "1 mm, 100 µm, 10 µm")
//   Axis: { scale(value) -> px, ticks: [{ value, at, label }], step, kind: "linear" | "log" }
export const linear = notBuilt("chart/axis.linear", "T6", "w2-1")
export const log = notBuilt("chart/axis.log", "T6", "w2-1")

// readCursor(axis, { min, max, stepValue }) -> { index, value, label, move(delta), end() } : the keyboard cursor and its readout
export const readCursor = notBuilt("chart/axis.readCursor", "T6", "w2-1")

// legend(series) -> [{ role, pattern, label_it }] : the legend list under a chart (patterns, never colour alone, A4)
export const legend = notBuilt("chart/axis.legend", "T6", "w2-1")

// valueTable(series, categories) -> { header, rows } : the value table printed under every chart of real data (P2, `print_table`)
export const valueTable = notBuilt("chart/axis.valueTable", "T6", "w2-1")
