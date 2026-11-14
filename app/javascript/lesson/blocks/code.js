// code (D-329): a whole program in a monospaced box, for S to copy and try on the Mac. The box keeps every space and every newline, never wraps
// (a long line scrolls sideways, and the box can be reached with the keyboard), and has a "Copia" button that copies `text` exactly. After the box:
// "Scrivi:" with the lines S types, in order, and "Sullo schermo vedi:" with the output the program gives. No highlighting: the palette of
// computer science has no colour left for the keywords, and the words of a program are not told apart by colour here. The block is never graded
// and holds no answer, so it is served whole (Lessons::StudentBody). The text goes in as a text node: nothing in it is read as markup or HTML.
import { button, el } from "lesson/dom"
import { insideControl, renderInlineRich, renderRich } from "lesson/text"

export const type = "code"

// How long "Copiato" stays on the button, in milliseconds.
export const COPIED_MS = 2500

// The lines of a program or a screen as the box shows them: split on newlines, the newline a text ends with is not a line of its own.
export function lineList(text) {
  const lines = String(text ?? "").split("\n")
  if (lines.length > 1 && lines[lines.length - 1] === "") lines.pop()
  return lines
}

// What the box shows: the lines joined again, exactly as written (indentation and empty lines kept).
export const shownText = (text) => lineList(text).join("\n")

// What "Copia" puts on the clipboard: the text of the block, untouched.
export const copyText = (block) => block.text

const fill = (template, n) => String(template).replace("%{n}", n)

// A box of preformatted text that scrolls sideways. It is a region with a name and can take focus, so that a keyboard can scroll it.
function listing(cls, text, label, speech) {
  const attrs = { class: cls, role: "region", tabindex: "0", "aria-label": label, translate: "no", spellcheck: "false" }
  if (speech) attrs["data-speech-text"] = speech
  return el("pre", attrs, el("code", { text: shownText(text) }))
}

// The program is selected, so that S can press Cmd and C when the clipboard is not given to the page.
function selectAll(node) {
  try {
    const range = document.createRange()
    range.selectNodeContents(node)
    const selection = window.getSelection()
    selection.removeAllRanges()
    selection.addRange(range)
  } catch (_error) {
    // nothing to select with: the message still says what to do
  }
}

export function render(block, ctx) {
  const t = ctx.t.code
  const n = lineList(block.text).length
  const inside = insideControl(ctx)
  const root = el("figure", { class: "block block-code", "data-lang": block.lang })

  const head = el("div", { class: "code-head" })
  head.appendChild(block.title_it
    ? renderInlineRich(block.title_it, el("p", { class: "code-title" }), inside)
    : el("p", { class: "code-title" }, el("strong", { text: t.program })))
  const status = el("span", { class: "code-status", role: "status", "aria-live": "polite", "data-nospeech": "" })
  const copy = button(t.copy, { class: "button secondary small code-copy", "aria-label": t.copy_aria })
  let timer = null
  copy.addEventListener("click", async () => {
    clearTimeout(timer)
    let done = false
    try {
      await navigator.clipboard.writeText(copyText(block))
      done = true
    } catch (_error) {
      done = false
    }
    if (done) {
      copy.textContent = t.copied
      copy.classList.add("is-copied")
      status.textContent = t.copied
    } else {
      selectAll(program)
      status.textContent = t.copy_failed
    }
    timer = setTimeout(() => {
      copy.textContent = t.copy
      copy.classList.remove("is-copied")
      status.textContent = ""
    }, COPIED_MS)
  })
  head.append(copy, status)
  root.appendChild(head)

  const program = listing("code-box", block.text, fill(t.region, n), fill(t.speech, n))
  root.appendChild(program)

  if (block.input_it?.length) {
    const typed = el("ol", { class: "code-typed" })
    for (const line of block.input_it) typed.appendChild(el("li", {}, el("kbd", { class: "code-key", text: line })))
    root.appendChild(el("div", { class: "code-io code-input", "data-nospeech": "" },
      el("p", { class: "code-label" }, el("strong", { text: t.type })),
      typed,
      el("p", { class: "code-hint", text: t.type_hint })))
  }
  if (block.output) {
    root.appendChild(el("div", { class: "code-io code-output", "data-nospeech": "" },
      el("p", { class: "code-label" }, el("strong", { text: t.screen })),
      listing("code-screen", block.output, fill(t.screen_region, lineList(block.output).length))))
  }
  if (block.note_it) root.appendChild(el("div", { class: "code-note" }, renderRich(block.note_it, ctx)))
  return root
}
