// A mark that stands right after a formula (a full stop, a comma, «?», a closing bracket or quote) or right before it (an opening bracket
// or quote) must never be left alone at the start or the end of a line (D-335). The reader's inline nodes are rewritten so that the
// formula and the mark run next to it share one {t: "nowrap", children} node, which the renderers draw as <span class="nowrap"> (white-space:
// nowrap; a leading-hyphen word piece and an IPA transcription are one too, see hyphenPieces). Pure: the parsed tree is not changed, only the array it is read from; plainText and the voice (speech.js walks the DOM and
// already takes a mark back to its word) read the same words as before.
const CLOSING = /^[.,;:!?)\]»”’"'…]+/
const OPENING = /[(\[«“‘„]+$/

// A word piece that starts with a hyphen and goes on with letters ("-ing", "-o", "-áis", "-emos-la") is never split after its hyphen at the end of a line
// (D-402): it is one {t: "nowrap"} node of its own, as a formula with its mark is, so the page draws one span with the characters as written (copying them
// gives the same text, which a non-breaking hyphen would not). It starts a word: at the start of the text, after a space or after an opening mark;
// text that follows another node with no space ("[[es:habl]]-ando") is the rest of a word, never a piece.
// An IPA transcription (a slash, no space or slash inside, a slash: «/ˈhɒs.pɪ.təl/») is one too: the stress marks ˈ and ˌ allow a break before them, which left «/» alone at the
// end of a line. «and/or» and «km/h» have one slash, «a / b» has spaces: neither is one.
const PIECE = /(^|[\s(\[«“‘„"'])(-\p{L}[\p{L}\p{M}]*(?:-\p{L}[\p{L}\p{M}]*)*|\/[^\s/]{1,40}\/)/gu

export function hyphenPieces(nodes) {
  const mayHold = (node) => node.t === "text" && (node.v.includes("-") || node.v.includes("/"))
  if (!nodes.some(mayHold)) return nodes
  const out = []
  nodes.forEach((node, i) => {
    if (!mayHold(node)) { out.push(node); return }
    const startsWord = i === 0
    let last = 0
    for (const m of node.v.matchAll(PIECE)) {
      if (m[1] === "" && m.index === 0 && !startsWord) continue
      const from = m.index + m[1].length
      if (from > last) out.push({ t: "text", v: node.v.slice(last, from) })
      out.push({ t: "nowrap", children: [{ t: "text", v: m[2] }] })
      last = from + m[2].length
    }
    if (last === 0) out.push(node)
    else if (last < node.v.length) out.push({ t: "text", v: node.v.slice(last) })
  })
  return out
}

export function glueFormulas(input) {
  const nodes = hyphenPieces(input)
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
