// "Commenta" (D-304): the pure parts of the comment mode, importable by node. Where a comment was written is an
// anchor: the data-comment-anchor segments of the element and of its ancestors, top-down, joined by "/"
// ("card:3/block:2/option:1"); the ids the server checks (lesson revision, practice serve, served event) come from
// data-comment-* attributes on the element or an ancestor. The server believes none of it before looking it up
// for this student (Comments::Intake). Nodes are read through getAttribute, parentElement and id only.

export const REASONS = ["not_understood", "error", "not_working", "like", "other"]
export const TEXT_MAX = 500
export const SELECTED_MAX = 300
export const MAX_SEGMENTS = 8
export const REF_ATTRIBUTES = {
  lesson_revision_id: "data-comment-lesson-revision-id",
  serve_id: "data-comment-serve-id",
  served_event_id: "data-comment-served-event-id"
}

const SEGMENT = /^[a-z][a-z_]{0,23}(?::[A-Za-z0-9_.-]{1,40})?$/
const ID_VALUE = /^[A-Za-z][A-Za-z0-9_-]{0,39}$/

export const validSegment = (text) => typeof text === "string" && SEGMENT.test(text)

// The anchor path of a node, up to (not above) root. Elements without data-comment-anchor are skipped; when no
// element of the chain has one, the nearest ancestor with a plain id stands in ("id:entry-test"). null when
// nothing names the place (the whole page).
export function anchorPath(node, root = null) {
  const segments = []
  let fallback = null
  for (let n = node; n && n !== root; n = n.parentElement) {
    const segment = n.getAttribute?.("data-comment-anchor")
    if (validSegment(segment)) segments.unshift(segment)
    else if (!fallback && ID_VALUE.test(n.id || "")) fallback = `id:${n.id}`
  }
  const picked = segments.length > 0 ? segments.slice(0, MAX_SEGMENTS) : fallback ? [fallback] : []
  return picked.length > 0 ? picked.join("/") : null
}

// The ids a node (or an ancestor) carries; for the whole page (no node) the first element of the document that
// carries one, which is the item on screen in a sitting or in practice.
export function refsOf(node, doc = null) {
  const refs = {}
  for (const [name, attribute] of Object.entries(REF_ATTRIBUTES)) {
    let value = null
    for (let n = node; n && value === null; n = n.parentElement) value = n.getAttribute?.(attribute) ?? null
    if (value === null && doc?.querySelector) value = doc.querySelector(`[${attribute}]`)?.getAttribute(attribute) ?? null
    if (value !== null && /^[1-9]\d{0,17}$/.test(value)) refs[name] = Number(value)
  }
  return refs
}

export const clip = (text, max) => String(text ?? "").replace(/\s+/g, " ").trim().slice(0, max)

// The payload of a comment, or { error } when it cannot be sent.
export function buildComment({ id, reason, text, selected, anchor, refs, pagePath, viewport, theme, size }) {
  if (!REASONS.includes(reason)) return { error: "reason" }
  const body = clip(text, TEXT_MAX + 1)
  if (body.length > TEXT_MAX) return { error: "text" }
  return {
    client_comment_id: id, reason, text_it: body || null, selected_text: clip(selected, SELECTED_MAX) || null,
    anchor: anchor || null, refs: refs || {}, page_path: pagePath,
    viewport_width: viewport?.width ?? null, viewport_height: viewport?.height ?? null, theme: theme || null, text_size: size || null
  }
}

// The things of a page a student can pick, for the list in the box (keyboard and screen reader): the anchored
// elements with a short name, in document order, whole page first.
export function listTargets(doc, wholePageLabel) {
  const out = [{ node: null, label: wholePageLabel, anchor: null }]
  for (const node of doc.querySelectorAll("[data-comment-anchor]")) {
    const label = clip(node.getAttribute("data-comment-label") || node.textContent, 50)
    out.push({ node, label: label || node.getAttribute("data-comment-anchor"), anchor: anchorPath(node, null) })
  }
  return out
}
