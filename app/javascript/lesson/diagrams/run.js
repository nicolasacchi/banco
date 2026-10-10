// The common frame of every layout(): check the data against the schema Ruby uses, check the roles against
// the subject's palette, then the type's semantic rules, then build. It never throws: bad data gives
// { error: { path, message, code } } (A7), and the figure shows alt_it and the description instead.
import palette from "lesson/palette"
import schema from "lesson/diagram_schema"
import { validate } from "lesson/schema"
import { fail, makeContext, roleNames, walkRoles, words } from "lesson/diagrams/common"

// The served form adds a computed `tilt` that the schema (agent data) does not know. It is accepted only
// where the server puts it: when x_value is not served (it is replaced by tilt) or show_value shows it.
function withoutServed(data) {
  if (data.x_value !== undefined && !data.show_value) return data
  const copy = { ...data }
  delete copy.tilt
  if (Array.isArray(copy.states)) copy.states = copy.states.map((s) => (s && typeof s === "object" ? (({ tilt, ...rest }) => rest)(s) : s))
  return copy
}

export function run(data, opts, mod) {
  try {
    if (!data || typeof data !== "object") return fail("", "no data", "E-LESSON-DIAGRAM")
    const bad = validate(schema, withoutServed(data))
    if (bad) return fail(bad.path, bad.message, "E-LESSON-DIAGRAM")
    const altWords = words(data.alt_it)
    if (altWords < 5 || altWords > 50) return fail("/alt_it", "alt_it has 5 to 50 words", "E-LESSON-ALT")
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
