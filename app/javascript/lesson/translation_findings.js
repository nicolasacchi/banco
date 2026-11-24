// The findings of the render check about the Italian translation of a bilingual lesson (D-402), all E-LESSON-RENDER. They read the page the way the student
// has it, so they only need the DOM (render_host.js calls them; a test calls them over a small stand-in for the document).
//   «translation missing»   a text the page says is in the target language (lang="en"|"es", put there by the four text functions of lesson/text.js and by the
//                           blocks that draw their own) that sits in no translation unit (data-translated), is not left out on purpose (data-tr-exempt) and is
//                           longer than three letters: a string that code built, or a field the author did not pair.
//   «translation empty»     a `.tr` node with nothing in it.
//   «translation overflow»  a translation, open, that leaves its card or the window (a translation never forces a width: the long Italian line wraps).
const NO_TRANSLATION_NEEDED = ".tr, svg, .katex, code, .code-span, script, style, template, [data-tr-exempt], [data-translated]"
const MAX_MISSING = 5
const MAX_OVERFLOW = 4
const CODE = "E-LESSON-RENDER"

const words = (node) => (node?.textContent || "").replace(/\s+/g, " ").trim().slice(0, 60)

export function translationMissing(card, out) {
  const walker = document.createTreeWalker(card, NodeFilter.SHOW_TEXT, {
    acceptNode: (node) => (node.parentElement?.closest(NO_TRANSLATION_NEEDED) ? NodeFilter.FILTER_REJECT : NodeFilter.FILTER_ACCEPT)
  })
  let missing = 0
  for (let node = walker.nextNode(); node && missing < MAX_MISSING; node = walker.nextNode()) {
    const letters = (node.nodeValue.match(/\p{L}/gu) ?? []).length
    if (letters <= 3) continue
    const lang = node.parentElement.closest("[lang]")?.getAttribute("lang")
    if (lang !== "en" && lang !== "es") continue
    missing += 1
    out.push({ code: CODE, message: `translation missing: "${node.nodeValue.replace(/\s+/g, " ").trim().slice(0, 60)}" is ${lang} text with no Italian translation`, where: words(node.parentElement) })
  }
}

export function translationEmpty(card, out) {
  for (const tr of card.querySelectorAll(".tr")) {
    if (tr.textContent.trim() === "" && !tr.querySelector("svg, img, .katex")) out.push({ code: CODE, message: "translation empty: a translation node has no text", where: words(tr.previousElementSibling ?? tr.parentElement) })
  }
}

export function translationOverflow(card, out) {
  const box = card.getBoundingClientRect()
  const left = Math.max(0, box.left) - 1
  const right = Math.min(window.innerWidth, box.right) + 1
  let found = 0
  for (const tr of card.querySelectorAll(".tr")) {
    if (tr.getClientRects().length === 0 || found >= MAX_OVERFLOW) continue // a closed one has no box
    const r = tr.getBoundingClientRect()
    if (tr.scrollWidth > tr.clientWidth + 3 || r.left < left || r.right > right) {
      found += 1
      out.push({ code: CODE, message: `translation overflow: a translation is ${Math.round(Math.max(tr.scrollWidth, r.width))} px wide in a ${Math.round(right - left)} px card`, where: words(tr) })
    }
  }
}
