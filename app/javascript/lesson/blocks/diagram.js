// diagram and schema blocks: a figure drawn by lesson/diagrams. Under safe mode the alt text and the
// description replace the drawing.
import { el } from "lesson/dom"
import { describe } from "lesson/diagrams/registry"
import { mountDiagram } from "lesson/diagrams/draw"
import { renderInlineRich } from "lesson/text"

export function safeFigure(data, ctx) {
  const figure = el("figure", { class: "dg dg-safe" }, el("p", { class: "dg-fallback", text: data.alt_it }))
  if (data.caption_it) figure.appendChild(renderInlineRich(data.caption_it, el("figcaption", { class: "dg-caption" }), ctx))
  figure.appendChild(el("details", { class: "dg-desc", open: "" }, el("summary", { text: ctx.t.description }), el("p", { text: describe(data) })))
  return figure
}

// { node, api }: api is null in safe mode.
export function figureFor(data, ctx, options = {}) {
  if (ctx.safe) return { node: safeFigure(data, ctx), api: null }
  const api = mountDiagram(data, ctx, options)
  ctx.mount(api.mounted)
  ctx.track?.(api)
  return { node: api.element, api }
}

export function render(block, ctx, options = {}) {
  return el("div", { class: "block block-diagram" }, figureFor(block.diagram ?? block.schema, ctx, options).node)
}

// A diagram that is part of another block (a case, an exercise, an example).
export function embed(data, ctx, options = {}) {
  return render({ diagram: data }, ctx, options)
}
