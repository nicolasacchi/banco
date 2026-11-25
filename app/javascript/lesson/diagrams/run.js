// The common frame of every layout(): check the data against the schema Ruby uses, check the roles against
// the subject's palette, then the type's semantic rules, then build. It never throws: bad data gives
// { error: { path, message, code } } (A7), and the figure shows alt_it and the description instead.
import palette from "lesson/palette"
import schema from "lesson/diagram_schema"
import { validate } from "lesson/schema"
import { fail, makeContext, roleNames, walkRoles, words } from "lesson/diagrams/common"

// The served form adds a computed `tilt` that the schema (agent data) does not know. It is accepted only
// where the server puts it: when x_value is not served (it is replaced by tilt) or show_value shows it.
// A figure of a bilingual lesson (D-402) also carries its own translation table `tr` (Lessons::Bilingual.fold), which is the page's, never the figure's data;
// and a `table` figure its Italian cells `header_it` / `rows_it` (R2, which tableNode draws): the schema Ruby uses for every subject does not know them.
function withoutServed(data) {
  const copy = { ...data }
  delete copy.tr
  if (data.type === "table") {
    delete copy.header_it
    delete copy.rows_it
    delete copy.translate_material
  }
  if (data.type === "concept_map") delete copy.translate_material // form material (D-402): the schema Ruby uses for every subject does not know it
  if (data.x_value !== undefined && !data.show_value) return copy
  delete copy.tilt
  if (Array.isArray(copy.states)) copy.states = copy.states.map((s) => (s && typeof s === "object" ? (({ tilt, ...rest }) => rest)(s) : s))
  return copy
}

// The fields drawn or read as plain text (the alt, the notes and the questions of a figure, in any language): a quoted word is written in «…», never in [[lang:..]]
// markup, which would show as it is. The first breach {path, message, code}, or null (the twin of Lessons::Diagrams.plain_text).
const PLAIN_TEXT_KEY = /^(?:alt|note|question)_(?:it|en|es)$/
export function plainTextBreach(node, path = "") {
  if (Array.isArray(node)) {
    for (const [i, item] of node.entries()) {
      const found = plainTextBreach(item, `${path}/${i}`)
      if (found) return found
    }
  } else if (node && typeof node === "object") {
    for (const [key, value] of Object.entries(node)) {
      if (typeof value === "string" && PLAIN_TEXT_KEY.test(key) && value.includes("[[")) {
        return { path: `${path}/${key}`, message: `${key} is plain text: use «…» for a quoted word, not [[..]] markup`, code: key.startsWith("alt") ? "E-LESSON-ALT" : "E-LESSON-DIAGRAM" }
      }
      const found = plainTextBreach(value, `${path}/${key}`)
      if (found) return found
    }
  }
  return null
}

export function run(data, opts, mod) {
  try {
    if (!data || typeof data !== "object") return fail("", "no data", "E-LESSON-DIAGRAM")
    const bad = validate(mod.schema ?? schema, withoutServed(data))
    if (bad) return fail(bad.path, bad.message, "E-LESSON-DIAGRAM")
    const altWords = words(data.alt_it)
    if (altWords < 5 || altWords > 50) return fail("/alt_it", "alt_it has 5 to 50 words", "E-LESSON-ALT")
    const plain = plainTextBreach(data)
    if (plain) return fail(plain.path, plain.message, plain.code)
    const subject = opts?.subject ?? "math"
    const known = roleNames(palette, subject)
    for (const { path, role } of walkRoles(data)) {
      if (!known.has(role)) return fail(path, `the role ${role} is not in the palette of ${subject}`, "E-LESSON-ROLE")
    }
    const ctx = makeContext(data, { ...opts, palette })
    const sem = mod.semantic?.(data, ctx)
    if (sem) return fail(sem.path, sem.message, sem.code ?? "E-LESSON-DIAGRAM")
    return mod.build(data, ctx)
  } catch (error) {
    return fail("", `the layout failed: ${error.message}`, "E-DIAGRAM-LAYOUT")
  }
}
