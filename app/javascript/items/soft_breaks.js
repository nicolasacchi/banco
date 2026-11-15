// Soft break points in the long words of a table cell (D-335). A cell's column is as wide as its longest word (the cell breaks a word only when it
// has to, `overflow-wrap: break-word`), so a program line without spaces, «CInt(Console.ReadLine())», made its column wider than the card and half of it
// was behind a sideways scroll. A <wbr> after «.», «(» and «,» and before «=» and «&» inside a word of more than SOFT_MIN characters is an invisible break
// opportunity that the table's width respects: the line breaks at a dot, never inside a name. The text, its copy and the screen reader's reading are
// unchanged (a <wbr> holds no character).

export const SOFT_MIN = 12
const AFTER = /[.(,]/
const BEFORE = /[=&]/

// The pieces of one word, split where a soft break may go: «CInt(Console.ReadLine())» -> ["CInt(", "Console.", "ReadLine(", "))"]. A word of
// SOFT_MIN characters or fewer is one piece. Pure.
export function pieces(word) {
  if (word.length <= SOFT_MIN) return [word]
  const out = []
  let current = ""
  for (let i = 0; i < word.length; i++) {
    const ch = word[i]
    if (BEFORE.test(ch) && current !== "") {
      out.push(current)
      current = ""
    }
    current += ch
    if (AFTER.test(ch) && i < word.length - 1 && !BEFORE.test(word[i + 1])) {
      out.push(current)
      current = ""
    }
  }
  if (current !== "") out.push(current)
  return out
}

// Puts <wbr> into the long words of the text nodes under +root+ (a formula's own tree is left alone).
export function softBreaks(root) {
  const walker = document.createTreeWalker(root, NodeFilter.SHOW_TEXT, {
    acceptNode: (node) => (node.parentElement?.closest(".katex, .math, script, style") ? NodeFilter.FILTER_REJECT : NodeFilter.FILTER_ACCEPT)
  })
  const nodes = []
  for (let node = walker.nextNode(); node; node = walker.nextNode()) nodes.push(node)
  for (const node of nodes) {
    const parts = node.nodeValue.split(/(\s+)/)
    if (!parts.some((part) => part.length > SOFT_MIN)) continue
    const fragment = document.createDocumentFragment()
    for (const part of parts) {
      pieces(part).forEach((piece, i) => {
        if (i > 0) fragment.appendChild(document.createElement("wbr"))
        fragment.appendChild(document.createTextNode(piece))
      })
    }
    node.replaceWith(fragment)
  }
  return root
}
