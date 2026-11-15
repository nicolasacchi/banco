// A mark that stands right after a formula (a full stop, a comma, «?», a closing bracket or quote) or right before it (an opening bracket
// or quote) must never be left alone at the start or the end of a line (D-335). The reader's inline nodes are rewritten so that the
// formula and the mark run next to it share one {t: "nowrap", children} node, which the renderers draw as <span class="nowrap"> (white-space:
// nowrap). Pure: the parsed tree is not changed, only the array it is read from; plainText and the voice (speech.js walks the DOM and
// already takes a mark back to its word) read the same words as before.
const CLOSING = /^[.,;:!?)\]»”’"'…]+/
const OPENING = /[(\[«“‘„]+$/

export function glueFormulas(nodes) {
  if (!nodes.some((node) => node.t === "math")) return nodes
  const out = []
  for (let i = 0; i < nodes.length; i++) {
    const node = nodes[i]
    if (node.t !== "math") { out.push(node); continue }
    const group = []
    const prev = out[out.length - 1]
    if (prev?.t === "text") {
      const open = prev.v.match(OPENING)?.[0]
      if (open) {
        const before = prev.v.slice(0, prev.v.length - open.length)
        if (before) out[out.length - 1] = { t: "text", v: before }
        else out.pop()
        group.push({ t: "text", v: open })
      }
    }
    group.push(node)
    let rest = null // the text after the closing marks, kept as it was
    const next = nodes[i + 1]
    if (next?.t === "text") {
      const close = next.v.match(CLOSING)?.[0]
      if (close) {
        group.push({ t: "text", v: close })
        const after = next.v.slice(close.length)
        i += 1
        if (after) rest = { t: "text", v: after }
      }
    }
    out.push(group.length === 1 ? node : { t: "nowrap", children: group })
    if (rest) out.push(rest)
  }
  return out
}
