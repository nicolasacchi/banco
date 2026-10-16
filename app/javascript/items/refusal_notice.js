// The block shown right above the input after an item is refused twice (D-298): the message of the
// refusal and the item's answer format, in evidence. It is a polite live region and takes no focus.
import { el } from "items/dom"
import { renderInline } from "items/markup"

// handle: the item's handle from renderItem; the block goes before its first answer box and stays
// until the item is replaced. Calling it again updates the message in the same block.
export function showRefusalNotice(handle, { message, format }) {
  let block = handle.element.querySelector(".refusal-notice")
  if (!block) {
    block = el("div", { class: "refusal-notice", "aria-live": "polite" })
    const answer = handle.element.matches(".answer") ? handle.element : handle.element.querySelector(".answer")
    if (answer?.parentNode) answer.parentNode.insertBefore(block, answer)
    else handle.element.prepend(block)
  }
  block.textContent = ""
  block.appendChild(el("p", { class: "refusal-message", text: message }))
  if (format) block.appendChild(renderInline(format, el("p", { class: "refusal-format" })))
  return block
}
