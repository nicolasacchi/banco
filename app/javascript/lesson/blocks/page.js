// page (release 2, D-281, SPEC B4): a free page, a sandboxed scene on its own origin. Inside the card the student sees the poster
// (the validation screenshot of its first state), the caption, the page's instructions and a button "Apri la parte interattiva (circa
// N KB)": nothing heavy loads until asked. On the click the iframe is inserted with the production attributes (sandbox
// "allow-scripts", no allow-same-origin, credentialless, no referrer); the bridge and the watchdog are lesson/free_page. A page that
// does not start is taken away and its poster and fallback text come back. Print shows the poster. Never counted for a skill state.
import { el, icon, button } from "lesson/dom"
import { renderInlineRich } from "lesson/text"
import { makeGuard, makeWatchdog, clampHeight, initMessage, BRIDGE } from "lesson/free_page"

export const type = "page"

const t = (ctx, key, values = {}) => Object.entries(values).reduce((s, [k, v]) => s.replace(`%{${k}}`, v), ctx.t.pages[key])

function poster(view) {
  if (view.poster) return el("img", { class: "free-page-poster", src: view.poster, alt: view.alt_it, loading: "lazy" })
  return el("p", { class: "free-page-poster free-page-noposter", role: "img", "aria-label": view.alt_it, text: view.alt_it })
}

export function render(block, ctx, loc = {}) {
  const view = block.view ?? {}
  const root = el("figure", { class: "block block-page free-page", "data-state": "idle", "data-page": block.page })
  const stage = el("div", { class: "free-page-stage", style: `aspect-ratio: ${String(view.aspect ?? "16:9").replace(":", " / ")}` }, poster(view))
  root.append(stage)
  const caption = block.caption_it ? renderInlineRich(block.caption_it, el("figcaption", { class: "free-page-caption" }), ctx) : null
  if (caption) root.append(caption)
  if (view.instructions_it) root.append(el("p", { class: "free-page-help" }, icon("hand", "free-page-ic"), el("span", { text: view.instructions_it })))
  const status = el("p", { class: "free-page-status", "aria-live": "polite" })
  const actions = el("div", { class: "free-page-actions" })
  root.append(actions, status)
  if (!view.src || ctx.safe) {
    root.dataset.state = "off"
    if (view.fallback_it) root.append(el("p", { class: "free-page-fallback", text: view.fallback_it }))
    return root
  }
  const open = button(t(ctx, "open", { kb: view.transfer_kb ?? "?" }), { class: "primary free-page-open" }, () => start())
  actions.append(open)

  let live = null
  function failMessage() {
    return [el("strong", { text: ctx.t.pages.failed }), el("span", { text: ` ${view.fallback_it ?? ""}` })]
  }

  function start() {
    if (live) return
    root.dataset.state = "loading"
    open.disabled = true
    status.textContent = ctx.t.pages.loading
    const iframe = el("iframe", {
      class: "free-page", title: block.caption_it ?? view.title_it, sandbox: "allow-scripts", referrerpolicy: "no-referrer", loading: "eager", allowfullscreen: ""
    })
    iframe.setAttribute("credentialless", "")
    iframe.style.height = `${view.min_height ?? 320}px`
    const guard = makeGuard()
    let opened = false
    const stop = (limit) => {
      live?.cleanup()
      live = null
      iframe.remove()
      root.dataset.state = "failed"
      open.disabled = false
      open.textContent = ctx.t.pages.again
      status.replaceChildren(...failMessage())
      ctx.pageEvent?.("page_failed", { ...loc, limit })
    }
    const dog = makeWatchdog({ onFail: stop })
    const post = (message) => iframe.contentWindow?.postMessage({ bridge: BRIDGE, ...message }, "*")
    const onMessage = (event) => {
      const verdict = guard.decide(event, iframe.contentWindow, performance.now())
      if (!verdict.ok) {
        if (verdict.reason !== "source") dog.rejected(guard.rejected)
        return
      }
      const m = verdict.message
      if (m.type === "ready") {
        if (opened) return
        opened = true
        dog.ready()
        const doc = document.documentElement
        post(initMessage({ seed: view.seed, theme: doc.dataset.theme, size: doc.dataset.size, reduced: ctx.reduced(), visible: true }))
        root.dataset.state = "running"
        status.textContent = ""
        stage.hidden = true
        iframe.style.height = `${clampHeight(m.height ?? view.min_height)}px`
        ctx.pageEvent?.("page_opened", { ...loc })
        actions.append(button(ctx.t.pages.fullscreen, { class: "free-page-full" }, () => iframe.requestFullscreen?.()))
      } else if (m.type === "resize") {
        iframe.style.height = `${clampHeight(m.height)}px`
      } else if (m.type === "event") {
        ctx.pageEvent?.("page_event", { ...loc, kind: m.kind, data: m.data ?? {} })
      }
    }
    window.addEventListener("message", onMessage)
    iframe.addEventListener("load", () => dog.loaded())
    const seen = typeof IntersectionObserver === "function"
      ? new IntersectionObserver((entries) => post({ type: "visibility", visible: entries.some((e) => e.isIntersecting) }), { threshold: 0.05 })
      : null
    const prefs = new MutationObserver(() => {
      const doc = document.documentElement
      post({ type: "prefs", theme: doc.dataset.theme === "dark" ? "dark" : "cream", size: doc.dataset.size, reduced_motion: ctx.reduced() })
    })
    prefs.observe(document.documentElement, { attributes: true, attributeFilter: ["data-theme", "data-size"] })
    live = { cleanup: () => { window.removeEventListener("message", onMessage); seen?.disconnect(); prefs.disconnect(); dog.stop() } }
    iframe.src = view.src
    stage.after(iframe)
    seen?.observe(iframe)
  }
  return root
}
