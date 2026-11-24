// The Italian translation of the english and spanish courses (D-402): one state machine for the practice pages and the lessons.
//
// The contract (CSS in app/assets/stylesheets/translation.css; the server only has to put the attributes on):
//   .tr[lang=it][data-nospeech]     a translation node, placed right after the target text it translates, never inside a <button>.
//                                    «Ascolta» skips it (data-nospeech) and it is hidden unless its scope is open.
//   [data-translation="on|off"]     a scope: a lesson card, a block, a practice exercise, a sitting's item box, a list page. The nearest one
//                                    around a node wins, so a block's own attribute beats its card's.
//   html[data-translation="always"] the student's preference («Sempre visibile»): every scope is open, the buttons are not drawn.
//   [data-tr-scope="card|block|item|page"]  marks an element that a button can open or close (`data-translation` is its state; `page` is a topic list page).
//   button.tr-toggle[aria-pressed]  a button inside its scope: the nearest [data-tr-scope] around it is the scope it flips. Built by
//                                    toggleButton(); the card or exercise button opens or closes every block inside it, even one added later.
//   data-tr-url                     on the scope or any ancestor: where opening posts `translation_opened` (the view gives S's own address and
//                                    leaves it out for the teacher and the preview, which write nothing). data-tr-surface (lesson, practice, topics),
//                                    data-tr-topic, data-tr-card, data-tr-block and data-tr-serve (the serve id) on the scope or an ancestor are the context.
//
//   POST {data-tr-url}  Content-Type: application/json, X-CSRF-Token from <meta name="csrf-token">
//   { "surface": "lesson", "scope": "card", "topic": "lezione.english.can-and-should", "card": 1 }
//   Missing context is left out, not null. Sent when a scope is OPENED, once per target (the whole body) in a page's life; never on close,
//   never when «Sempre visibile» is on, never twice. Informational only: no counter, no aid, a failure is ignored.
//
// Plain DOM calls only (createElement, get/set/removeAttribute, parentNode, children), so a test can run it over a small stand-in document.

const STATE = "data-translation"
const SCOPE = "data-tr-scope"
const URL = "data-tr-url"
const CONTEXT = { surface: "data-tr-surface", topic: "data-tr-topic", card: "data-tr-card", block: "data-tr-block", serve_id: "data-tr-serve" }
const NUMBERS = new Set(["card", "block", "serve_id"])

const sent = new Set()

const children = (node) => Array.from(node.children ?? [])

// The nearest element from `node` up (itself included) that has the attribute, or null.
function closestWith(node, attr) {
  for (let at = node; at; at = at.parentNode) if (at.getAttribute && at.getAttribute(attr) !== null) return at
  return null
}

// "on", "off" or "always": what is in force for `node`. The preference wins over every scope; no scope at all is off.
export function state(node) {
  if (globalThis.document?.documentElement?.getAttribute(STATE) === "always") return "always"
  return closestWith(node, STATE)?.getAttribute(STATE) === "on" ? "on" : "off"
}

export const isOpen = (node) => state(node) !== "off"

// The scope a button flips: the nearest [data-tr-scope] above it.
export const scopeOf = (button) => closestWith(button.parentNode, SCOPE)

// Opens or closes `scope` and everything inside it: blocks that were opened or closed one by one go back to following their scope.
export function setScope(scope, open) {
  const clear = (node) => children(node).forEach((child) => { child.removeAttribute(STATE); clear(child) })
  clear(scope)
  scope.setAttribute(STATE, open ? "on" : "off")
  refresh(scope)
}

// Brings aria-pressed of every toggle in `root` (and `root` itself) in line with what its scope shows now.
export function refresh(root) {
  const walk = (node) => {
    if (/(^|\s)tr-toggle(\s|$)/.test(node.getAttribute("class") ?? "")) {
      const scope = scopeOf(node)
      if (scope) node.setAttribute("aria-pressed", String(isOpen(scope)))
    }
    children(node).forEach(walk)
  }
  walk(root)
}

// The body of the app event for `scope`: the kind of scope and the context found on it and its ancestors, no empty member.
export function payload(scope) {
  const body = {}
  for (const [name, attr] of Object.entries(CONTEXT)) {
    if (name === "topic") body.scope = scope.getAttribute(SCOPE)
    const value = closestWith(scope, attr)?.getAttribute(attr)
    if (value === undefined || value === null || value === "") continue
    body[name] = NUMBERS.has(name) && /^\d+$/.test(value) ? Number(value) : value
  }
  return body
}

// Posts the app event once per target. Returns the promise, or null when nothing is sent (no address: the teacher and the preview; a target
// already reported). A failure is swallowed: the event is informational.
export function report(scope, { fetchImpl = (...args) => globalThis.fetch(...args) } = {}) {
  const url = closestWith(scope, URL)?.getAttribute(URL)
  if (!url) return null
  const body = JSON.stringify(payload(scope))
  if (sent.has(body)) return null
  sent.add(body)
  const token = globalThis.document?.querySelector?.("meta[name=csrf-token]")?.content ?? ""
  return Promise.resolve(fetchImpl(url, {
    method: "POST", credentials: "same-origin", keepalive: true,
    headers: { "Content-Type": "application/json", Accept: "application/json", "X-CSRF-Token": token },
    body
  })).catch(() => {})
}

// What a click on a toggle does: flips the scope, reports an opening. Returns whether the scope is open now (null: no scope, or «Sempre visibile»).
export function toggle(button, options = {}) {
  const scope = scopeOf(button)
  if (!scope || state(scope) === "always") return null
  const open = !isOpen(scope)
  setScope(scope, open)
  if (open) report(scope, options)
  return open
}

// A translation node: <tag class="tr" lang="it" data-nospeech>. `content` is a string (set as text) or a node the caller drew (rich text).
export function node(content, { tag = "p" } = {}) {
  const element = document.createElement(tag)
  element.setAttribute("class", "tr")
  element.setAttribute("lang", "it")
  element.setAttribute("data-nospeech", "")
  if (typeof content === "string") element.textContent = content
  else if (content) element.appendChild(content)
  return element
}

// A toggle button. `text` is the visible label of a scope button («Traduzione»); a unit button has an `icon` node and an `ariaLabel`
// («Mostra la traduzione: <first words>», see unitLabel). Call refresh(scope) once it is in the page: aria-pressed starts false.
export function toggleButton({ text = null, ariaLabel = null, icon = null, unit = false, fetchImpl = null } = {}) {
  const button = document.createElement("button")
  button.setAttribute("type", "button")
  button.setAttribute("class", unit ? "tr-toggle tr-toggle-unit" : "tr-toggle")
  button.setAttribute("aria-pressed", "false")
  if (ariaLabel) button.setAttribute("aria-label", ariaLabel)
  if (icon) button.appendChild(icon)
  if (text) {
    const label = document.createElement("span")
    label.textContent = text
    button.appendChild(label)
  }
  button.addEventListener("click", () => toggle(button, fetchImpl ? { fetchImpl } : {}))
  return button
}

// The first words of a text for a unit button's name: markup out (**bold**, [[span:words]], `code`), at most `count` words, an ellipsis when cut.
export function firstWords(text, count = 6) {
  const plain = String(text).replace(/\[\[[^:\]|]*(?:\|[a-z]+)?:(.*?)\]\]/g, "$1").replace(/[*_`]/g, "").replace(/\s+/g, " ").trim()
  const words = plain.split(" ")
  return words.length > count ? `${words.slice(0, count).join(" ")}…` : plain
}

// «Mostra la traduzione: %{words}» with the first words of `text`.
export const unitLabel = (template, text) => template.replace("%{words}", firstWords(text))
