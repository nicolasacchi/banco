// The restricted markup of agent text (X-02). Agent text is plain text: no HTML.
// Four things are recognised and nothing else:
//
//   **bold**            a keyword
//   $latex$             a formula, rendered by KaTeX with trust: false (\$ is a dollar)
//   blank line          a new paragraph
//   1. 2. 3. lines      a numbered list (every line of the block starts with "n. ")
//
// parse() returns plain data, so it runs under Node in the tests; markup.js turns
// the data into DOM nodes with textContent, never innerHTML.

const LIST_LINE = /^\s*\d+[.)]\s+(.*)$/

export function parse(text) {
  const source = String(text ?? "").replace(/\r\n?/g, "\n").trim()
  if (source === "") return []
  return source.split(/\n\s*\n/).map((block) => {
    const lines = block.split("\n").filter((line) => line.trim() !== "")
    if (lines.length > 0 && lines.every((line) => LIST_LINE.test(line))) {
      return { type: "ol", items: lines.map((line) => inline(line.match(LIST_LINE)[1])) }
    }
    return { type: "p", children: inline(lines.map((line) => line.trim()).join(" ")) }
  })
}

// Inline nodes: {t: "text", v}, {t: "bold", children}, {t: "math", v}.
export function inline(text) {
  const nodes = []
  let buffer = ""
  const flush = () => {
    if (buffer !== "") nodes.push({ t: "text", v: buffer })
    buffer = ""
  }
  let i = 0
  while (i < text.length) {
    const ch = text[i]
    if (ch === "\\" && text[i + 1] === "$") {
      buffer += "$"
      i += 2
    } else if (ch === "$") {
      const end = closing(text, i + 1)
      if (end > i + 1) {
        flush()
        nodes.push({ t: "math", v: text.slice(i + 1, end).replace(/\\\$/g, "$") })
        i = end + 1
      } else {
        buffer += ch
        i += 1
      }
    } else if (ch === "*" && text[i + 1] === "*") {
      const end = text.indexOf("**", i + 2)
      if (end > i + 2) {
        flush()
        nodes.push({ t: "bold", children: inline(text.slice(i + 2, end)) })
        i = end + 2
      } else {
        buffer += "**"
        i += 2
      }
    } else {
      buffer += ch
      i += 1
    }
  }
  flush()
  return nodes
}

// Index of the next unescaped "$" at or after +from+, or -1.
function closing(text, from) {
  for (let i = from; i < text.length; i++) {
    if (text[i] === "\\") i += 1
    else if (text[i] === "$") return i
  }
  return -1
}
