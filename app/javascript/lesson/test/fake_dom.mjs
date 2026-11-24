// A small stand-in for the document, enough to draw a lesson card in node: elements with attributes, classes, children and text, the selectors the
// translation code asks for (compound selectors made of a tag, classes and [attributes], a descendant combinator, a comma list), closest, and the
// events a button needs. A test does `import { install } from "./fake_dom.mjs"` and calls install() before it draws.
// Not a browser: no layout, no CSS, so what is hidden by a stylesheet (a closed `.tr`) is checked through its attributes, not its display.

export class Text {
  constructor(value) { this.nodeType = 3; this.nodeValue = String(value); this.parentNode = null }
  get textContent() { return this.nodeValue }
  set textContent(value) { this.nodeValue = String(value) }
  get parentElement() { return this.parentNode }
}

const parseSelector = (selector) => selector.split(",").map((part) => part.trim().split(/\s+/).map((compound) => {
  const parsed = { tag: null, classes: [], attrs: [] }
  const re = /^([a-zA-Z][a-zA-Z0-9-]*)|\.([a-zA-Z0-9_-]+)|\[([a-zA-Z0-9_-]+)(?:([~^$*]?=)"?([^\]"]*)"?)?\]/y
  let m
  re.lastIndex = 0
  while (re.lastIndex < compound.length && (m = re.exec(compound))) {
    if (m[1]) parsed.tag = m[1].toLowerCase()
    else if (m[2]) parsed.classes.push(m[2])
    else parsed.attrs.push({ name: m[3], op: m[4] ?? null, value: m[5] ?? null })
  }
  return parsed
}))

export class Element {
  constructor(tag) {
    this.nodeType = 1
    this.tagName = String(tag).toUpperCase()
    this.tag = String(tag).toLowerCase()
    this.attrs = new Map()
    this.childNodes = []
    this.parentNode = null
    this.listeners = {}
    this.disabled = false
  }
  get children() { return this.childNodes.filter((c) => c.nodeType === 1) }
  get childElementCount() { return this.children.length }
  get firstChild() { return this.childNodes[0] ?? null }
  get lastChild() { return this.childNodes.at(-1) ?? null }
  get previousElementSibling() {
    const siblings = this.parentNode?.children ?? []
    return siblings[siblings.indexOf(this) - 1] ?? null
  }
  get isConnected() { return true }
  get namespaceURI() { return "http://www.w3.org/1999/xhtml" }
  set className(value) { this.setAttribute("class", value) }
  get className() { return this.getAttribute("class") ?? "" }
  get classList() {
    const names = () => new Set(this.className.split(/\s+/).filter(Boolean))
    return {
      add: (c) => this.setAttribute("class", [...names().add(c)].join(" ")),
      remove: (c) => { const s = names(); s.delete(c); this.setAttribute("class", [...s].join(" ")) },
      toggle: (c, on) => { const s = names(); if (on ?? !s.has(c)) s.add(c); else s.delete(c); this.setAttribute("class", [...s].join(" ")) },
      contains: (c) => names().has(c)
    }
  }
  get dataset() {
    const node = this
    return new Proxy({}, {
      get: (_t, key) => node.getAttribute(`data-${String(key).replace(/[A-Z]/g, (c) => `-${c.toLowerCase()}`)}`) ?? undefined,
      set: (_t, key, value) => { node.setAttribute(`data-${String(key).replace(/[A-Z]/g, (c) => `-${c.toLowerCase()}`)}`, value); return true }
    })
  }
  get hidden() { return this.attrs.has("hidden") }
  set hidden(value) { if (value) this.attrs.set("hidden", ""); else this.attrs.delete("hidden") }
  setAttribute(name, value) { this.attrs.set(name, String(value)) }
  getAttribute(name) { return this.attrs.has(name) ? this.attrs.get(name) : null }
  hasAttribute(name) { return this.attrs.has(name) }
  removeAttribute(name) { this.attrs.delete(name) }
  get textContent() { return this.childNodes.map((c) => c.textContent).join("") }
  set textContent(value) { this.childNodes = []; if (value !== "") this.appendChild(new Text(value)) }
  appendChild(child) {
    // a label stand-in that answers with its own name (a function that says its name) is text, as a string would be
    if (typeof child === "function") child = new Text(String(child))
    if (child instanceof Fragment) { for (const c of [...child.childNodes]) this.appendChild(c); child.childNodes = []; return child }
    child.parentNode?.removeChild?.(child)
    child.parentNode = this
    this.childNodes.push(child)
    return child
  }
  append(...nodes) { for (const node of nodes) this.appendChild(typeof node === "string" ? new Text(node) : node) }
  removeChild(child) { this.childNodes = this.childNodes.filter((c) => c !== child); child.parentNode = null; return child }
  insertBefore(child, before) {
    if (!before) return this.appendChild(child)
    if (child instanceof Fragment) { for (const c of [...child.childNodes]) this.insertBefore(c, before); child.childNodes = []; return child }
    child.parentNode?.removeChild?.(child)
    child.parentNode = this
    this.childNodes.splice(this.childNodes.indexOf(before), 0, child)
    return child
  }
  after(...nodes) { const at = this.parentNode.childNodes.indexOf(this); for (const n of nodes) { this.parentNode.childNodes.splice(at + 1, 0, n); n.parentNode = this.parentNode } }
  replaceChildren(...nodes) { this.childNodes = []; this.append(...nodes) }
  remove() { this.parentNode?.removeChild(this) }
  contains(node) { for (let at = node; at; at = at.parentNode) if (at === this) return true; return false }
  addEventListener(name, fn) { (this.listeners[name] ??= []).push(fn) }
  removeEventListener() {}
  click() { if (!this.disabled) for (const fn of this.listeners.click ?? []) fn({ target: this, preventDefault() {} }) }
  focus() {}
  // no layout here: a test says what a node's box is (`rect`, `scrollWidth`, `clientWidth`, `noBox` for display: none)
  getClientRects() { return this.noBox ? [] : [{}] }
  getBoundingClientRect() { return this.rect ?? { left: 0, right: 0, width: 0, top: 0, bottom: 0 } }
  get scrollWidth() { return this.scrollW ?? this.clientWidth }
  get clientWidth() { return this.clientW ?? 100 }
  matches(selector) { return parseSelector(selector).some((chain) => this.#matchesChain(chain)) }
  #matchesCompound(c) {
    if (c.tag && c.tag !== this.tag) return false
    const names = new Set(this.className.split(/\s+/))
    if (!c.classes.every((n) => names.has(n))) return false
    return c.attrs.every(({ name, op, value }) => {
      const have = this.getAttribute(name)
      if (have === null) return false
      if (op === null) return true
      if (op === "=") return have === value
      if (op === "~=") return have.split(/\s+/).includes(value)
      if (op === "^=") return have.startsWith(value)
      if (op === "$=") return have.endsWith(value)
      return have.includes(value)
    })
  }
  #matchesChain(chain) {
    if (!this.#matchesCompound(chain.at(-1))) return false
    let at = this.parentNode
    for (let i = chain.length - 2; i >= 0; i--) {
      while (at && !(at.nodeType === 1 && at.#matchesCompound(chain[i]))) at = at.parentNode
      if (!at) return false
      at = at.parentNode
    }
    return true
  }
  closest(selector) {
    for (let at = this; at && at.nodeType === 1; at = at.parentNode) if (at.matches(selector)) return at
    return null
  }
  querySelectorAll(selector) {
    const out = []
    const walk = (node) => { for (const c of node.children) { if (c.matches(selector)) out.push(c); walk(c) } }
    walk(this)
    return out
  }
  querySelector(selector) { return this.querySelectorAll(selector)[0] ?? null }
  all(pred = () => true) { const out = []; const walk = (n) => { for (const c of n.children) { if (pred(c)) out.push(c); walk(c) } }; walk(this); return out }
  // every text run under the node, with its parent
  runs() { const out = []; const walk = (n) => { for (const c of n.childNodes) { if (c.nodeType === 3) out.push(c); else walk(c) } }; walk(this); return out }
}

export class Fragment extends Element {
  constructor() { super("#fragment"); this.nodeType = 11 }
}

const meta = { content: "token" }

export function install() {
  const html = new Element("html")
  globalThis.document = {
    documentElement: html,
    body: new Element("body"),
    createElement: (tag) => new Element(tag),
    createElementNS: (_ns, tag) => new Element(tag),
    createDocumentFragment: () => new Fragment(),
    createTextNode: (text) => new Text(text),
    createTreeWalker: (root, _what, { acceptNode } = {}) => {
      const runs = []
      const walk = (node) => { for (const c of node.childNodes) { if (c.nodeType === 3) runs.push(c); else walk(c) } }
      walk(root)
      const accepted = runs.filter((r) => (acceptNode ? acceptNode(r) === 1 : true))
      let i = 0
      return { nextNode: () => accepted[i++] ?? null }
    },
    querySelector: (selector) => (selector === "meta[name=csrf-token]" ? meta : null),
    addEventListener() {},
    removeEventListener() {}
  }
  globalThis.window = { addEventListener() {}, removeEventListener() {}, innerWidth: 390 }
  globalThis.NodeFilter = { SHOW_TEXT: 4, FILTER_ACCEPT: 1, FILTER_REJECT: 2, FILTER_SKIP: 3 }
  return html
}

export function uninstall() {
  delete globalThis.document
  delete globalThis.window
  delete globalThis.NodeFilter
}
