// Markup that reached the page as text (D-310): a span "[[es:hablar]]", "[[highlight:...]]" or a formula "$a^3$" printed as it was written,
// because the field was drawn as plain text. The render check (render_host.js) reads every text of a card with it. A formula counts only when
// what is between the dollars looks like TeX (a backslash, ^, _ or a brace): "costa $5 o $6" in an English sentence is money, not markup.
const SPAN = /\[\[[a-z]+(?:[_-][a-z]+)*(?:\|it)?:[^\]]*\]\]/
const FORMULA = /(?<!\\)\$([^$\n]{1,80})(?<!\\)\$/g

// The first piece of raw markup in a string, or null. Pure.
export function rawMarkup(text) {
  const s = String(text ?? "")
  const span = s.match(SPAN)
  if (span) return span[0]
  for (const m of s.matchAll(FORMULA)) if (/[\\^_{}]/.test(m[1])) return m[0]
  return null
}

// The first piece of raw markup in the text nodes under root, leaving out formulas already drawn (a KaTeX tree holds its TeX source in its
// MathML) and code (a code span shows its characters as they are): { text, where } or null.
export function rawMarkupIn(root) {
  const walker = document.createTreeWalker(root, NodeFilter.SHOW_TEXT, {
    acceptNode: (node) => (node.parentElement?.closest(".katex, code, .code-span, script, style, template") ? NodeFilter.FILTER_REJECT : NodeFilter.FILTER_ACCEPT)
  })
  for (let node = walker.nextNode(); node; node = walker.nextNode()) {
    const hit = rawMarkup(node.nodeValue)
    if (hit) return { text: hit, where: node.parentElement }
  }
  return null
}
