// The lines of "Come si risponde" (D-216) by the component of the item on screen. Pure: no DOM,
// so node tests read it. The texts live in config/locales/it.yml (t.help).

const COMPONENTS = ["number", "fraction", "expression", "choice", "ordering", "matching", "normalized_text", "short_answer"]

function linesFor(component, part, help) {
  const lines = [...(help[component] || [])]
  if (component === "normalized_text" && part.accents) lines.push(...(help.normalized_text_accents || []))
  if (component === "number" && part.unit) lines.push(...(help.number_unit || []))
  if (component === "fraction" && part.mixed) lines.push(...(help.fraction_mixed || []))
  if (component === "matching" && part.reuse_right) lines.push(...(help.matching_reuse || []))
  return lines
}

// [{ heading, lines }]: a testlet has its own lines, then the lines of each component its sub items use.
export function helpSections(item, t) {
  const help = t.help || {}
  if (item.component === "testlet") {
    const seen = new Set()
    const sections = [{ heading: null, lines: [...(help.testlet || [])] }]
    for (const sub of item.sub_items || []) {
      if (!COMPONENTS.includes(sub.component) || seen.has(sub.component)) continue
      seen.add(sub.component)
      sections.push({ heading: (help.component_names || {})[sub.component], lines: linesFor(sub.component, sub, help) })
    }
    sections.push({ heading: null, lines: [...(help.common || [])] })
    return sections
  }
  return [{ heading: null, lines: [...linesFor(item.component, item, help), ...(help.common || [])] }]
}

