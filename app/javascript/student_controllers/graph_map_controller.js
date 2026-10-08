import { Controller } from "@hotwired/stimulus"

// The map of a skill graph (teacher, D-221). The server draws the SVG and one panel template per
// node; this controller only selects, filters and zooms. Without it every node is a plain link
// to its card in the list. Everything is done with classes and the viewBox: no inline style.
//
// Selecting a node marks it (gm-sel), the chain of what it needs (gm-up) and everything that builds on it
// (gm-down); the rest is dimmed by the wrapper's gm-has-selection class.
export default class extends Controller {
  static targets = ["svg", "panel", "empty", "detail", "search", "facet", "onlyInferred", "onlyPinned", "seconda", "count", "template"]
  static values = { mainWidth: Number, fullWidth: Number, mainHeight: Number, fullHeight: Number, shownOne: String, shownOther: String, shownNone: String }

  connect() {
    this.nodes = new Map()
    this.element.querySelectorAll(".gm-node").forEach((node) => this.nodes.set(node.dataset.key, node))
    this.edges = Array.from(this.element.querySelectorAll(".gm-edge[data-from]"))
    this.ups = new Map()
    this.downs = new Map()
    this.edges.forEach((edge) => {
      if (edge.classList.contains("gm-edge-warning")) return
      push(this.downs, edge.dataset.from, edge.dataset.to)
      push(this.ups, edge.dataset.to, edge.dataset.from)
    })
    this.templates = new Map(this.templateTargets.map((t) => [t.dataset.key, t]))
    this.selected = null
    this.scale = READABLE
    this.fit()
    this.element.classList.add("gm-ready")
    this.beforePrint = () => this.element.classList.remove("gm-has-selection")
    window.addEventListener("beforeprint", this.beforePrint)
    this.svgTarget.addEventListener("click", (event) => this.click(event))
    this.svgTarget.addEventListener("pointerdown", (event) => this.dragStart(event))
    this.svgTarget.addEventListener("pointermove", (event) => this.dragMove(event))
    this.svgTarget.addEventListener("pointerup", () => { this.drag = null })
    this.svgTarget.addEventListener("pointercancel", () => { this.drag = null })
    this.filter()
  }

  disconnect() {
    window.removeEventListener("beforeprint", this.beforePrint)
  }

  // ---- selection

  click(event) {
    if (this.dragged) { this.dragged = false; event.preventDefault(); return }
    const node = event.target.closest(".gm-node")
    if (!node) return
    event.preventDefault()
    this.select(node.dataset.key)
  }

  pick(event) {
    event.preventDefault()
    this.select(event.currentTarget.dataset.key)
  }

  select(key) {
    if (!this.nodes.has(key)) return
    this.clearMarks()
    this.selected = key
    const up = this.reach(key, this.ups)
    const down = this.reach(key, this.downs)
    this.nodes.get(key).classList.add("gm-sel")
    up.forEach((k) => this.nodes.get(k)?.classList.add("gm-up"))
    down.forEach((k) => this.nodes.get(k)?.classList.add("gm-down"))
    const chain = new Set([key, ...up, ...down])
    this.edges.forEach((edge) => {
      if (chain.has(edge.dataset.from) && chain.has(edge.dataset.to) && this.sameSide(edge, key, up, down)) edge.classList.add("gm-hot")
    })
    this.element.classList.add("gm-has-selection")
    this.showPanel(key)
    this.reveal(key)
  }

  // An edge belongs to the chain when both ends are on the up side (with the node) or both on the down side.
  sameSide(edge, key, up, down) {
    const upSide = new Set([key, ...up])
    const downSide = new Set([key, ...down])
    return (upSide.has(edge.dataset.from) && upSide.has(edge.dataset.to)) || (downSide.has(edge.dataset.from) && downSide.has(edge.dataset.to))
  }

  reach(start, graph) {
    const seen = new Set()
    const queue = [start]
    while (queue.length) {
      for (const next of graph.get(queue.pop()) || []) {
        if (!seen.has(next) && next !== start) { seen.add(next); queue.push(next) }
      }
    }
    return seen
  }

  clearMarks() {
    this.element.querySelectorAll(".gm-sel, .gm-up, .gm-down, .gm-hot").forEach((el) => el.classList.remove("gm-sel", "gm-up", "gm-down", "gm-hot"))
  }

  clear() {
    this.clearMarks()
    this.selected = null
    this.element.classList.remove("gm-has-selection")
    this.detailTarget.replaceChildren()
    this.emptyTarget.hidden = false
  }

  key(event) {
    if (event.key === "Escape") { this.clear() }
  }

  showPanel(key) {
    const template = this.templates.get(key)
    this.detailTarget.replaceChildren()
    if (template) this.detailTarget.append(template.content.cloneNode(true))
    this.emptyTarget.hidden = !!template
  }

  // ---- filters

  filter() {
    const text = normalize(this.hasSearchTarget ? this.searchTarget.value : "")
    const facets = new Set(this.facetTargets.filter((box) => box.checked).map((box) => box.dataset.value))
    const onlyInferred = this.hasOnlyInferredTarget && this.onlyInferredTarget.checked
    const onlyPinned = this.hasOnlyPinnedTarget && this.onlyPinnedTarget.checked
    const hidden = new Set()
    let shown = 0
    this.nodes.forEach((node, key) => {
      if (!node.classList.contains("gm-skill")) return
      const d = node.dataset
      const ok = facets.has(d.facet) && (!text || normalize(d.search).includes(text)) &&
        (!onlyInferred || d.inferred === "true") && (!onlyPinned || Number(d.pinned) > 0)
      node.classList.toggle("gm-hidden", !ok)
      if (ok) shown += 1; else hidden.add(key)
    })
    // Stubs and second-year lines stay while at least one skill they touch is shown.
    this.nodes.forEach((node, key) => {
      if (node.classList.contains("gm-skill")) return
      const touching = this.edges.filter((e) => e.dataset.from === key || e.dataset.to === key)
      const others = touching.map((e) => (e.dataset.from === key ? e.dataset.to : e.dataset.from))
      const off = others.length > 0 && others.every((k) => hidden.has(k))
      node.classList.toggle("gm-hidden", off)
      if (off) hidden.add(key)
    })
    this.edges.forEach((edge) => edge.classList.toggle("gm-hidden", hidden.has(edge.dataset.from) || hidden.has(edge.dataset.to)))
    if (this.hasCountTarget) {
      this.countTarget.textContent = shown === 0 ? this.shownNoneValue : (shown === 1 ? this.shownOneValue : this.shownOtherValue.replace("{n}", shown))
    }
    if (this.selected && hidden.has(this.selected)) this.clear()
  }

  toggleSeconda() {
    this.element.classList.toggle("gm-show-seconda", this.secondaTarget.checked)
    if (!this.secondaTarget.checked && this.selected?.startsWith("seconda:")) this.clear()
    this.draw(this.scale)
  }

  // ---- zoom and pan: the viewBox is the whole map; the zoom is the size the svg is drawn at, and the box around it scrolls.

  get width() {
    return this.element.classList.contains("gm-show-seconda") ? this.fullWidthValue : this.mainWidthValue
  }

  get tall() {
    return this.element.classList.contains("gm-show-seconda") ? this.fullHeightValue : this.mainHeightValue
  }

  get box() {
    return this.svgTarget.parentElement
  }

  // Readable first: the whole map when it fits at 90% of its natural size, else 90% and a scroll.
  fit() {
    const whole = this.box.clientWidth / this.width
    this.draw(whole >= READABLE ? whole : READABLE)
    this.box.scrollLeft = 0
  }

  overview() {
    this.draw(Math.min(this.box.clientWidth / this.width, 1))
    this.box.scrollLeft = 0
  }

  zoomIn() { this.zoomBy(1.25) }
  zoomOut() { this.zoomBy(0.8) }

  zoomBy(factor) {
    const box = this.box
    const before = this.scale
    const centre = (box.scrollLeft + box.clientWidth / 2) / before
    const next = Math.min(Math.max(before * factor, 0.2), 2.5)
    this.draw(next)
    box.scrollLeft = centre * next - box.clientWidth / 2
  }

  draw(scale) {
    this.scale = scale
    const svg = this.svgTarget
    svg.setAttribute("viewBox", `0 0 ${this.width} ${this.tall}`)
    svg.setAttribute("width", Math.round(this.width * scale))
    svg.setAttribute("height", Math.round(this.tall * scale))
  }

  // Keep the selected node in view.
  reveal(key) {
    const box = this.box
    const rect = this.nodes.get(key).querySelector("rect")
    const x = Number(rect.getAttribute("x")) * this.scale
    const w = Number(rect.getAttribute("width")) * this.scale
    if (x < box.scrollLeft || x + w > box.scrollLeft + box.clientWidth) box.scrollLeft = x + w / 2 - box.clientWidth / 2
  }

  dragStart(event) {
    if (event.target.closest(".gm-node") || event.button > 0) return
    this.drag = { x: event.clientX, left: this.box.scrollLeft }
    this.dragged = false
  }

  dragMove(event) {
    if (!this.drag) return
    const dx = event.clientX - this.drag.x
    if (Math.abs(dx) > 3) this.dragged = true
    this.box.scrollLeft = this.drag.left - dx
  }
}

const READABLE = 0.9

function push(map, key, value) {
  if (!map.has(key)) map.set(key, [])
  map.get(key).push(value)
}

function normalize(text) {
  return String(text || "").normalize("NFD").replace(/[̀-ͯ]/g, "").toLowerCase().trim()
}
