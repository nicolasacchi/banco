// Equations as the lesson draws them (the equazioni prototype): the unknown in its colour, the numbers in theirs,
// and in a displayed equation the two members as tiles, either side of the "=". The author writes plain TeX; this
// adds the \role{...}{...} wrappers that KaTeX turns into classes (roles unknown, known, left, right). What the author
// already wrapped in \role stays as it is. Pure: strings in, strings out.

const UNKNOWNS = new Set(["x", "y", "z"])
const ARROWS = new Set(["to", "rightarrow", "Rightarrow", "longrightarrow", "Longrightarrow"])
const VERBATIM = new Set(["role", "text", "mathrm", "operatorname", "htmlClass", "textbf"])
const isLetter = (c) => /[A-Za-z]/.test(c ?? "")

function group(tex, i) {
  // the {...} that starts at i: returns the index after its closing brace
  let depth = 0
  for (let k = i; k < tex.length; k++) {
    if (tex[k] === "\\") k += 1
    else if (tex[k] === "{") depth += 1
    else if (tex[k] === "}") {
      depth -= 1
      if (depth === 0) return k + 1
    }
  }
  return tex.length
}

// The unknown (x, y, z) and the numbers get their roles. \role{..}{..}, \text{..} and the like are copied as they are.
export function colourTokens(tex) {
  let out = ""
  let i = 0
  const copyAtom = () => {
    // one atom (a character or a {group}) copied as it is: exponents and indices are not coloured
    if (tex[i] === "{") {
      const end = group(tex, i)
      out += tex.slice(i, end)
      i = end
    } else if (tex[i] === "\\") {
      let j = i + 1
      while (isLetter(tex[j])) j += 1
      if (j === i + 1) j += 1
      out += tex.slice(i, j)
      i = j
    } else if (i < tex.length) {
      out += tex[i]
      i += 1
    }
  }
  while (i < tex.length) {
    const c = tex[i]
    if (c === "\\") {
      let j = i + 1
      while (isLetter(tex[j])) j += 1
      const name = tex.slice(i + 1, j)
      if (j === i + 1) {
        out += tex.slice(i, i + 2)
        i += 2
      } else if (VERBATIM.has(name)) {
        let end = j
        while (tex[end] === "{") end = group(tex, end)
        out += tex.slice(i, end)
        i = end
      } else {
        out += tex.slice(i, j)
        i = j
      }
    } else if (c === "^" || c === "_") {
      out += c
      i += 1
      while (tex[i] === " ") {
        out += " "
        i += 1
      }
      copyAtom()
    } else if (UNKNOWNS.has(c) && !isLetter(tex[i - 1]) && !isLetter(tex[i + 1])) {
      out += `\\role{unknown}{${c}}`
      i += 1
    } else if (/[0-9]/.test(c)) {
      const m = tex.slice(i).match(/^\d+(?:[.,]\d+)?/)
      out += `\\role{known}{${m[0]}}`
      i += m[0].length
    } else {
      out += c
      i += 1
    }
  }
  return out
}

// Top-level pieces of a formula: [{ text }, { arrow: "\\to" }, ...]; an "=" at depth 0 splits a piece in two members.
function split(tex) {
  const parts = []
  let depth = 0
  let start = 0
  let eq = -1
  const closePiece = (end) => {
    const text = tex.slice(start, end)
    parts.push(eq >= 0 ? { left: tex.slice(start, eq), right: tex.slice(eq + 1, end) } : { text })
    eq = -1
  }
  for (let i = 0; i < tex.length; i++) {
    const c = tex[i]
    if (c === "\\") {
      let j = i + 1
      while (isLetter(tex[j])) j += 1
      const name = tex.slice(i + 1, j)
      if (depth === 0 && ARROWS.has(name)) {
        closePiece(i)
        parts.push({ arrow: tex.slice(i, j) })
        start = j
      }
      i = Math.max(i + 1, j - 1)
    } else if (c === "{" || c === "(") depth += 1
    else if (c === "}" || c === ")") depth -= 1
    else if (c === "=" && depth === 0) eq = eq === -1 ? i : -2
  }
  closePiece(tex.length)
  return parts
}

// The tex of a displayed equation. Without exactly one "=" per piece, only the colours are added.
export function displayTex(tex) {
  if (/\\role\{(left|right)\}/.test(tex)) return colourTokens(tex)
  const parts = split(tex)
  const equations = parts.filter((p) => p.left !== undefined).length
  if (equations === 0) return colourTokens(tex)
  return parts.map((p) => {
    if (p.arrow) return `\\;${p.arrow}\\;`
    if (p.left === undefined) return colourTokens(p.text)
    if (p.left.trim() === "" || p.right.trim() === "") return colourTokens(`${p.left}=${p.right}`)
    return `\\role{left}{${colourTokens(p.left.trim())}}\\,=\\,\\role{right}{${colourTokens(p.right.trim())}}`
  }).join("")
}

// The same, in pieces: each equation on its own and each arrow on its own, so that a long chain can break between them.
// Returns [{ tex }, { arrow: "\\to" }, ...]; a formula without an arrow is one piece.
export function displayPieces(tex) {
  if (/\\role\{(left|right)\}/.test(tex)) return [{ tex: colourTokens(tex) }]
  const parts = split(tex)
  if (!parts.some((p) => p.arrow)) return [{ tex: displayTex(tex) }]
  return parts.map((p) => {
    if (p.arrow) return { arrow: p.arrow }
    if (p.left === undefined) return { tex: colourTokens(p.text) }
    if (p.left.trim() === "" || p.right.trim() === "") return { tex: colourTokens(`${p.left}=${p.right}`) }
    return { tex: `\\role{left}{${colourTokens(p.left.trim())}}\\,=\\,\\role{right}{${colourTokens(p.right.trim())}}` }
  }).filter((p) => p.arrow || p.tex.trim() !== "")
}
