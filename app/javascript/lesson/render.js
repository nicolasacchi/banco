// The student's lesson page (A10): the cover, one card at a time with the lesson map and the bottom bar,
// or all cards in one long column; print; settings; resume; the events that say a card was seen.
// renderLesson(root, body, config) returns { goTo, current, renderAll, setView, setReduceMotion, destroy }.
//   body    the projection the page receives (Lessons::StudentBody): no answer in it
//   config  { mode: "student" | "preview" | "render", expand, teacher, safe, topic, revisionId, urls, resume, view, reduceMotion,
//             labels (t), items (the item templates' texts), seen, unavailableTopics, full, savePreferences }
import { newId } from "items/outbox"
import { button, clear, el, icon } from "lesson/dom"
import { iconOf, renderCard, rolesUsed } from "lesson/cards"
import { sample } from "lesson/blocks/legend"
import { renderInlineRich, renderRich } from "lesson/text"
import { figureFor } from "lesson/blocks/diagram"

const csrf = () => document.querySelector("meta[name=csrf-token]")?.content || ""

async function postJson(url, body) {
  const response = await fetch(url, {
    method: "POST", redirect: "manual", credentials: "same-origin",
    headers: { "Content-Type": "application/json", Accept: "application/json", "X-CSRF-Token": csrf() },
    body: JSON.stringify(body ?? {})
  })
  if (!(response.headers.get("content-type") || "").includes("json")) return null
  if (response.status !== 200 && response.status !== 422) return null
  return response.json()
}

export function renderLesson(root, body, config) {
  const t = config.labels
  const cards = body.cards
  const core = cards.filter((c) => c.level === "core")
  const extra = cards.filter((c) => c.level === "extra")
  const order = [...core, ...extra]
  const byN = new Map(cards.map((c) => [c.n, c]))
  const idToN = new Map(cards.map((c) => [c.id, c.n]))
  const seen = new Set(config.seen ?? [])
  const state = { n: 0, view: config.view === "scroll" ? "scroll" : "cards", reduce: !!config.reduceMotion, teacher: !!config.teacher }
  const motionQuery = typeof matchMedia === "function" ? matchMedia("(prefers-reduced-motion: reduce)") : null
  const printQuery = typeof matchMedia === "function" ? matchMedia("print") : null
  const trackers = new Set()
  const expand = !!config.expand
  let mounts = []

  const ctx = {
    subject: body.subject, t, items: config.items ?? {}, topic: config.topic, revisionId: config.revisionId,
    safe: !!config.safe, preview: config.mode === "preview", get teacher() { return state.teacher },
    // config.expand (the render check, R4): every "more" open, every mistake turned, every step shown, as in safe mode
    get openMore() { return state.teacher || ctx.safe || expand },
    get openAll() { return state.teacher || ctx.safe || expand },
    get showAll() { return ctx.safe || expand },
    unavailableTopics: config.unavailableTopics ?? [],
    cardNumber: (slug) => idToN.get(slug),
    fontPx: () => parseFloat(getComputedStyle(root).fontSize) || 20,
    reduced: () => state.reduce || !!motionQuery?.matches,
    mount: (fn) => mounts.push(fn),
    track: (api) => trackers.add(api),
    rich: (text) => el("div", { class: "rich" }, renderRich(text, ctx)),
    questions: config.mode === "student" && config.urls?.questions ? { url: config.urls.questions, labels: config.questionLabels } : null,
    full: config.full ? fullAccess(config.full) : null,
    postCheck: async (loc, payload) => {
      const base = config.urls.check
      const path = loc.ex ? `${base}/${loc.card}/${loc.block}/ex/${loc.ex}${loc.part ? `/${loc.part}` : ""}` : `${base}/${loc.card}/${loc.block}${loc.step ? `/${loc.step}` : ""}`
      return postJson(path, payload)
    },
    fetchSolution: async (n) => {
      try {
        const response = await fetch(`${config.urls.solution}/${n}/solution`, {
          method: "POST", redirect: "manual", credentials: "same-origin",
          headers: { "Content-Type": "application/json", Accept: "application/json", "X-CSRF-Token": csrf() }, body: "{}"
        })
        return response.status === 200 ? await response.json() : null
      } catch (_error) {
        return null
      }
    }
  }

  // ---- positions and texts ----
  const partTitle = (card) => (card.part ? body.parts?.find((p) => p.n === card.part)?.title_it : null)
  const positionOf = (card) => {
    if (card.level === "core") return { text: t.card_of.replace("%{n}", core.indexOf(card) + 1).replace("%{total}", core.length), core: true }
    return { text: t.extra_of.replace("%{n}", extra.indexOf(card) + 1).replace("%{total}", extra.length), core: false }
  }
  const kickerOf = (card) => {
    const pos = positionOf(card).text
    const bits = [pos]
    if (card.level === "core" && partTitle(card)) bits.push(partTitle(card))
    if (t.role_word[card.role] && card.level === "core") bits.push(t.role_word[card.role])
    return bits.join(" · ")
  }
  const sequence = [0, ...order.map((c) => c.n)]
  // the roles each card introduces: the legend chip is on that card only; the map lists all of them
  const introduced = new Map()
  const allRoles = []
  for (const c of order) {
    const fresh = rolesUsed(c).filter((r) => !allRoles.includes(r))
    fresh.forEach((r) => allRoles.push(r))
    introduced.set(c.n, fresh)
  }

  // ---- the frame ----
  root.classList.add("l2")
  root.dataset.subject = body.subject
  root.dataset.view = state.view
  root.dataset.motion = ctx.reduced() ? "reduced" : "full"
  clear(root)
  const live = el("div", { class: "sr-only", role: "status", "aria-live": "polite" })
  const topbar = el("header", { class: "l2-top" })
  const barSegments = el("div", { class: "l2-progress", "aria-hidden": "true" })
  const counter = el("p", { class: "l2-counter" })
  // an icon button: the label is visible on large screens, a tooltip (title) and the accessible name everywhere
  const ibtn = (name, label, cls, handler, extra = {}) => button(el("span", { class: "l2-ib" }, icon(name), el("span", { class: "l2-ibl", text: label })), { class: `l2-ibtn ${cls}`, title: label, "aria-label": label, ...extra }, handler)
  const mapButton = ibtn("map", t.map, "l2-mapbtn", () => openMap(), { "aria-haspopup": "dialog" })
  const settingsButton = ibtn("text-settings", t.settings, "l2-settingsbtn", () => openSettings(), { "aria-haspopup": "dialog" })
  const brand = el("span", { class: "l2-brand", "aria-hidden": "true" }, icon("scale"))
  const titles = el("div", { class: "l2-titles" },
    el("small", { text: `${t.kind[body.kind] ?? body.kind} ${t.of_subject} ${t.subject[body.subject] ?? body.subject}` }),
    el("strong", { text: body.title_it }))
  const chrome = hostChrome()
  const chip = chrome.notices.length
    ? el("span", { class: "l2-chip", role: "note", title: chrome.notices.map((n) => n.text).join(" "), "aria-label": chrome.notices.map((n) => n.text).join(" ") }, icon("info"), el("span", { text: chrome.notices.map((n) => n.short).join(" · ") }))
    : null
  const menuButton = chrome.links.length ? ibtn("menu", t.menu, "l2-menubtn", () => openMenu(), { "aria-haspopup": "dialog" }) : null
  const tools = el("div", { class: "l2-tools" }, mapButton, settingsButton)
  topbar.append(el("div", { class: "l2-top-in" }, brand, titles, counter, chip, tools, menuButton), barSegments)
  const shell = el("div", { class: "l2-shell" })
  const side = el("aside", { class: "l2-sidemap", "aria-label": t.map })
  const stage = el("main", { class: "l2-stage", id: "lesson-stage" })
  shell.append(side, stage)
  const prevBtn = button(el("span", {}, icon("prev"), document.createTextNode(` ${t.back}`)), { class: "button secondary l2-prev" }, () => step(-1))
  const nextBtn = button(el("span"), { class: "button l2-next" }, () => step(1))
  const barNav = el("nav", { class: "l2-bar", "aria-label": t.navigation }, prevBtn, el("span", { class: "l2-bar-count" }), nextBtn)
  const viewToggle = button("", { class: "button secondary small l2-view" }, () => setView(state.view === "cards" ? "scroll" : "cards", true))
  const mapDialog = el("dialog", { class: "l2-dialog l2-mapdialog", "aria-label": t.map })
  const menuDialog = el("dialog", { class: "l2-dialog l2-menudialog", "aria-label": t.menu })
  const settingsDialog = el("dialog", { class: "l2-dialog l2-settingsdialog", "aria-label": t.settings })
  root.append(live, topbar, shell, barNav, mapDialog, settingsDialog, menuDialog)

  // ---- cards: built once, kept ----
  const built = new Map()
  const build = (n) => {
    if (built.has(n)) return built.get(n)
    mounts = []
    const element = n === 0 ? coverNode() : renderCard(byN.get(n), ctx, { kicker: kickerOf(byN.get(n)), newRoles: introduced.get(n) ?? [] })
    if (n !== 0 && byN.get(n).role === "summary") element.appendChild(endBox())
    const entry = { element, mounts, mounted: false }
    built.set(n, entry)
    return entry
  }
  const attach = (entry) => {
    if (!entry.mounted) {
      entry.mounted = true
      for (const fn of entry.mounts) fn()
    } else relayoutIn(entry.element)
  }
  const relayoutIn = (element) => {
    for (const api of trackers) if (element.contains(api.element)) api.relayout()
  }

  // ---- the cover ----
  function coverNode() {
    const hero = body.hero ? figureFor(body.hero, ctx, { hero: true }) : null
    const resume = config.resume && byN.has(config.resume) ? config.resume : null
    const start = button(resume ? t.resume.replace("%{n}", labelNumber(byN.get(resume))) : t.start, { class: "button l2-start" }, () => goTo(resume ?? order[0].n, { focus: true }))
    const goals = el("ul", { class: "goals" }, ...(body.goals_it ?? []).map((g) => el("li", {}, icon("check", "goal-ic"), el("span", {}, renderRich(g, ctx)))))
    const list = partsList()
    const firstSentence = (text) => {
      const para = String(text ?? "").split(/\n\s*\n/)[0].replace(/\s+/g, " ").trim()
      const m = para.match(/^(.+?[.!?])(\s|$)/)
      return m ? m[1] : para
    }
    const lead = body.why_it ? renderInlineRich(firstSentence(body.why_it), el("p", { class: "cover-lead" }), ctx) : null
    const why = body.why_it && String(body.why_it).trim().length > firstSentence(body.why_it).length + 2
      ? el("details", { class: "why" }, el("summary", { text: `${t.more}: ${t.why_you_need}` }), el("div", { class: "why-body" }, renderRich(body.why_it, ctx)))
      : null
    const article = el("article", { class: "l2-cover", id: "scheda-0", "aria-labelledby": "scheda-0-title" },
      el("p", { class: "kicker", text: t.cover_kicker.replace("%{kind}", t.kind[body.kind] ?? body.kind).replace("%{subject}", t.subject[body.subject] ?? body.subject).replace("%{minutes}", body.minutes).replace("%{cards}", core.length) }),
      el("h1", { id: "scheda-0-title", tabindex: "-1", text: body.title_it }),
      lead,
      hero ? el("div", { class: "cover-hero block-diagram" }, hero.node) : null,
      el("h2", { class: "cover-h", text: t.goals }), goals,
      el("p", { class: "cover-start" }, start),
      why,
      el("details", { class: "cover-all" }, el("summary", { text: t.cards }), list))
    if (body.book_it) article.appendChild(el("div", { class: "cover-book" }, el("p", {}, el("strong", { text: `${t.on_book}: ` }), document.createTextNode(body.book_it.replace(/^["“]|["”]$/g, ""))), el("p", { class: "hint", text: t.book_note })))
    return article
  }
  const labelNumber = (card) => String(positionOf(card).core ? core.indexOf(card) + 1 : `A${extra.indexOf(card) + 1}`)

  function partsList() {
    const wrap = el("div", { class: "cover-parts" })
    const makeList = (list) => {
      const ol = el("ol", { class: "cover-cards" })
      for (const c of list) ol.appendChild(el("li", {}, button(el("span", { class: "map-line" }, icon(iconOf(c), "map-ic"), el("span", { text: c.title_it })), { class: "map-item" }, () => goTo(c.n, { focus: true }))))
      return ol
    }
    if (body.parts?.length) {
      for (const p of body.parts) {
        wrap.appendChild(el("h3", { class: "map-group", text: `${t.part} ${p.n} · ${p.title_it}` }))
        wrap.appendChild(makeList(core.filter((c) => c.part === p.n)))
      }
    } else wrap.appendChild(makeList(core))
    if (extra.length) {
      wrap.appendChild(el("h3", { class: "map-group", text: t.deeper }))
      wrap.appendChild(makeList(extra))
    }
    return wrap
  }

  function endBox() {
    const box = el("section", { class: "l2-end", "aria-label": t.end_title },
      el("h3", { text: t.end_title }),
      el("p", { text: t.end_text }),
      el("p", { class: "end-actions" },
        el("a", { class: "button", href: config.urls?.practice ?? "#", text: t.practice }),
        button(el("span", {}, icon("print"), document.createTextNode(` ${t.print_summary}`)), { class: "button secondary", "data-print-summary": "" }, () => printSummary()),
        button(el("span", {}, icon("restart"), document.createTextNode(` ${t.restart}`)), { class: "button secondary" }, () => goTo(0, { focus: true }))))
    return box
  }

  // ---- map ----
  function mapContent(close) {
    const wrap = el("nav", { class: "map", "aria-label": t.map })
    wrap.appendChild(el("h2", { class: "map-title", text: t.map }))
    const item = (c, label) => {
      const b = button(el("span", { class: "map-line" }, el("span", { class: "mn", "aria-hidden": "true", text: label }), icon(iconOf(c), "map-ic"), el("span", { class: "map-text", text: c.title_it }), icon("check", "mv")), { class: `map-item${seen.has(c.n) ? " seen" : ""}`, "data-n": c.n }, () => {
        goTo(c.n, { focus: true })
        close?.()
      })
      if (c.n === state.n) b.setAttribute("aria-current", "step")
      return el("li", {}, b)
    }
    const cover = button(el("span", { class: "map-line" }, icon("compass", "map-ic"), el("span", { class: "map-text", text: t.cover })), { class: "map-item", "data-n": 0 }, () => {
      goTo(0, { focus: true })
      close?.()
    })
    if (state.n === 0) cover.setAttribute("aria-current", "step")
    wrap.appendChild(el("ul", { class: "map-list" }, el("li", {}, cover)))
    const group = (title, list) => {
      wrap.appendChild(el("h3", { class: "map-group", text: title }))
      const ul = el("ul", { class: "map-list" })
      list.forEach((c) => ul.appendChild(item(c, labelNumber(c))))
      wrap.appendChild(ul)
    }
    if (body.parts?.length) for (const p of body.parts) group(`${t.part} ${p.n} · ${p.title_it}`, core.filter((c) => c.part === p.n))
    else group(t.cards, core)
    if (extra.length) group(t.deeper, extra)
    if (allRoles.length > 0) {
      wrap.appendChild(el("h3", { class: "map-group", text: t.legend_label }))
      const line = el("p", { class: "card-legend map-legend" })
      allRoles.forEach((r) => line.appendChild(sample(r, ctx)))
      wrap.appendChild(line)
    }
    return wrap
  }
  const refreshMap = () => {
    clear(side)
    side.appendChild(mapContent(null))
  }
  function openMap() {
    clear(mapDialog)
    const close = () => mapDialog.close()
    mapDialog.append(mapContent(close), button(t.close, { class: "button secondary", "data-close": "" }, close))
    mapDialog.showModal?.()
  }

  // ---- the page's own menu, notices and way back (the layout's, folded into one button inside a lesson) ----
  function hostChrome() {
    const out = { notices: [], links: [] }
    if (config.mode !== "student") return out
    const trial = document.getElementById("trial-notice")?.textContent.trim()
    const draft = document.getElementById("draft-notice")?.textContent.trim()
    if (trial) out.notices.push({ text: trial, short: t.chip_trial })
    if (draft) out.notices.push({ text: draft, short: t.chip_draft })
    const back = document.querySelector(".l2-back a")
    if (back) out.links.push({ href: back.getAttribute("href"), text: back.textContent.trim() })
    document.querySelectorAll("#student-menu a").forEach((a) => out.links.push({ href: a.getAttribute("href"), text: a.textContent.trim(), id: a.id }))
    return out
  }
  function openMenu() {
    clear(menuDialog)
    const list = el("ul", { class: "l2-menulist" })
    chrome.links.forEach((l) => list.appendChild(el("li", {}, el("a", { class: "button secondary", href: l.href, text: l.text }))))
    menuDialog.append(el("h2", { text: t.menu }), ...chrome.notices.map((n) => el("p", { class: "hint", text: n.text })), list, button(t.close, { class: "button", "data-close": "" }, () => menuDialog.close()))
    menuDialog.showModal?.()
  }

  // ---- settings ----
  function openSettings() {
    clear(settingsDialog)
    const scope = root.closest("[data-theme]") ?? document.documentElement
    const current = { theme: scope.dataset.theme || "cream", size: scope.dataset.size || "normal" }
    const radios = (name, options, value, onChange) => {
      const set = el("fieldset", { class: "options" }, el("legend", { text: t.settings_labels[name] }))
      for (const [val, label] of Object.entries(options)) {
        const input = el("input", { type: "radio", name: `s-${name}`, value: val, checked: val === value })
        input.addEventListener("change", () => onChange(val))
        set.appendChild(el("label", { class: "option" }, input, el("span", { text: label })))
      }
      return set
    }
    const motion = el("input", { type: "checkbox", checked: state.reduce })
    motion.addEventListener("change", () => setReduceMotion(motion.checked, true))
    settingsDialog.append(
      el("h2", { text: t.settings }),
      radios("theme", t.themes, current.theme, (v) => applyPreference({ theme: v })),
      radios("size", t.sizes, current.size, (v) => applyPreference({ size: v })),
      radios("view", t.views, state.view, (v) => setView(v, true)),
      el("label", { class: "option" }, motion, el("span", { text: t.reduce_motion })),
      button(t.close, { class: "button" }, () => settingsDialog.close()))
    settingsDialog.showModal?.()
  }
  function applyPreference(change) {
    const scope = root.closest("[data-theme]") ?? document.documentElement
    if (change.theme) scope.dataset.theme = change.theme
    if (change.size) scope.dataset.size = change.size
    for (const api of trackers) api.relayout()
    config.savePreferences?.(change)
  }
  function setReduceMotion(on, persist) {
    state.reduce = on
    root.dataset.motion = ctx.reduced() ? "reduced" : "full"
    if (persist) config.savePreferences?.({ reduce_motion: on })
  }

  // ---- navigation ----
  function announce(n) {
    const card = byN.get(n)
    live.textContent = n === 0 ? `${t.cover}: ${body.title_it}` : `${positionOf(card).text}: ${card.title_it}`
  }
  function refreshChrome() {
    const n = state.n
    const card = byN.get(n)
    counter.textContent = n === 0 ? t.cover : positionOf(card).text
    barNav.querySelector(".l2-bar-count").textContent = counter.textContent
    // the thin positional bar: one segment per core card, the current one marked (no percentage, no time)
    clear(barSegments)
    core.forEach((c) => barSegments.appendChild(el("span", { class: c.n === n ? "now" : seen.has(c.n) ? "seen" : "" })))
    const index = sequence.indexOf(n)
    prevBtn.hidden = index <= 0
    const nextN = sequence[index + 1]
    nextBtn.hidden = nextN === undefined
    if (nextN !== undefined) {
      const label = n === 0 ? t.start : t.next.replace("%{title}", byN.get(nextN).title_it)
      nextBtn.firstChild.replaceChildren(document.createTextNode(`${label} `), icon("next"))
    }
    root.dataset.card = String(n)
    refreshMap()
    if (location && config.mode === "student") {
      try {
        history.replaceState(null, "", `#scheda-${n}`)
      } catch (_error) { /* a sandboxed frame */ }
    }
  }
  function goTo(n, options = {}) {
    if (!byN.has(n) && n !== 0) n = 0
    state.n = n
    if (state.view === "scroll") {
      refreshChrome()
      ensureRendered(n)
      const target = stage.querySelector(`#scheda-${n}`)
      target?.scrollIntoView?.({ block: "start", behavior: ctx.reduced() ? "auto" : "smooth" })
    } else {
      clear(stage)
      const entry = build(n)
      stage.appendChild(entry.element)
      attach(entry)
      const nextN = sequence[sequence.indexOf(n) + 1]
      if (nextN !== undefined) queueMicrotask(() => build(nextN))
      refreshChrome()
    }
    announce(n)
    if (options.focus !== false) (stage.querySelector(`#scheda-${n} h1, #scheda-${n} h2`))?.focus?.({ preventScroll: false })
    scheduleSeen(n)
    window.scrollTo?.(0, 0)
  }
  const step = (d) => {
    const next = sequence[sequence.indexOf(state.n) + d]
    if (next !== undefined) goTo(next, { focus: true })
  }

  // ---- the long column ----
  const placeholders = new Map()
  let observer = null
  function renderScroll() {
    clear(stage)
    observer?.disconnect()
    placeholders.clear()
    observer = typeof IntersectionObserver === "function" ? new IntersectionObserver((entries) => {
      for (const e of entries) if (e.isIntersecting) fill(Number(e.target.dataset.n))
    }, { rootMargin: "900px 0px" }) : null
    for (const n of sequence) {
      const ph = el("div", { class: "l2-placeholder", "data-n": n, id: n === 0 ? undefined : undefined })
      ph.style.minHeight = n === 0 ? "20rem" : "16rem"
      placeholders.set(n, ph)
      stage.appendChild(ph)
      if (observer) observer.observe(ph)
    }
    if (!observer) for (const n of sequence) fill(n)
  }
  function fill(n) {
    const ph = placeholders.get(n)
    if (!ph || !ph.isConnected) return
    observer?.unobserve(ph)
    const entry = build(n)
    ph.replaceWith(entry.element)
    ph.dataset.done = "1"
    placeholders.delete(n)
    attach(entry)
  }
  function ensureRendered(n) {
    // render the target and its neighbours so that the jump lands on real content
    for (const m of [sequence[sequence.indexOf(n) - 1], n, sequence[sequence.indexOf(n) + 1]]) if (m !== undefined) fill(m)
  }
  function renderAll() {
    if (state.view !== "scroll") setView("scroll", false)
    for (const n of [...placeholders.keys()]) fill(n)
    for (const api of trackers) api.relayout()
  }
  function setView(view, persist) {
    if (view === state.view && stage.children.length > 0) return
    state.view = view
    root.dataset.view = view
    viewToggle.textContent = view === "cards" ? t.view_all : t.view_cards
    if (view === "scroll") {
      renderScroll()
      ensureRendered(state.n)
      refreshChrome()
      stage.querySelector(`.l2-placeholder`) // keep the reference alive for tests
    } else goTo(state.n, { focus: false })
    if (persist) config.savePreferences?.({ lesson_view: view })
  }

  // ---- print ----
  function printSummary() {
    const summary = core.find((c) => c.role === "summary")
    if (!summary) return
    if (state.view === "cards") goTo(summary.n, { focus: false })
    else {
      ensureRendered(summary.n)
    }
    root.dataset.print = "summary"
    const done = () => {
      delete root.dataset.print
      window.removeEventListener("afterprint", done)
    }
    window.addEventListener("afterprint", done)
    for (const api of trackers) api.relayout()
    setTimeout(() => window.print(), 50)
  }
  const printAll = () => {
    root.dataset.print = "all"
    const before = state.view
    renderAll()
    const done = () => {
      delete root.dataset.print
      if (before === "cards") setView("cards", false)
      window.removeEventListener("afterprint", done)
    }
    window.addEventListener("afterprint", done)
    setTimeout(() => window.print(), 50)
  }
  const onBeforePrint = () => {
    if (root.dataset.print) return
    root.dataset.print = "all"
    renderAll()
  }
  const onPrintChange = () => {
    for (const api of trackers) api.relayout()
  }
  window.addEventListener("beforeprint", onBeforePrint)
  printQuery?.addEventListener?.("change", onPrintChange)
  const printButton = ibtn("print", t.print, "l2-printbtn", () => printAll())
  tools.append(printButton)
  viewToggle.textContent = state.view === "cards" ? t.view_all : t.view_cards

  // ---- events: a card seen for 3 seconds ----
  let seenTimer = null
  const pending = []
  let flushTimer = null
  function scheduleSeen(n) {
    clearTimeout(seenTimer)
    if (config.mode !== "student" || ctx.safe) return
    seenTimer = setTimeout(() => {
      seen.add(n)
      refreshChrome()
      if (n === 0) return
      pending.push({ kind: "card_seen", card: n, client_event_id: newId() })
      clearTimeout(flushTimer)
      flushTimer = setTimeout(flush, 800)
    }, config.seenAfterMs ?? 3000)
  }
  async function flush() {
    if (pending.length === 0 || !config.urls?.events) return
    const batch = pending.splice(0, 20)
    try {
      const reply = await postJson(config.urls.events, { events: batch })
      if (!reply) pending.unshift(...batch)
    } catch (_error) {
      pending.unshift(...batch)
    }
  }

  // ---- keys ----
  const BLOCKING = "input, select, textarea, [contenteditable], details, summary, [role=radio], [role=radiogroup], [role=slider], [role=spinbutton], [role=tab], [role=tablist], [role=listbox], [role=option], [role=menu], [role=menuitem], [role=grid], iframe, dialog[open] *, [data-nokeys], [data-nokeys] *"
  const onKey = (event) => {
    if (event.key !== "ArrowLeft" && event.key !== "ArrowRight") return
    if (event.altKey || event.ctrlKey || event.metaKey || event.shiftKey || event.defaultPrevented) return
    if (state.view !== "cards") return
    const target = event.target
    if (target instanceof Element && target.closest(BLOCKING)) return
    const ok = target === document.body || target === document.documentElement || target === stage || target.closest?.(".l2-bar") || target.matches?.("h1, h2") || target.classList?.contains("l2-card") || target.classList?.contains("l2-cover")
    if (!ok) return
    event.preventDefault()
    step(event.key === "ArrowRight" ? 1 : -1)
  }
  document.addEventListener("keydown", onKey)
  stage.addEventListener("click", (event) => {
    const link = event.target.closest?.("a.lesson-link[data-card]")
    if (!link) return
    event.preventDefault()
    const n = idToN.get(link.dataset.card)
    if (n) goTo(n, { focus: true })
  })

  // ---- hash, then go ----
  const fromHash = () => {
    const m = (location.hash || "").match(/^#scheda-(\d+)$/)
    return m ? Number(m[1]) : null
  }
  const onHash = () => {
    const n = fromHash()
    if (n !== null && n !== state.n) goTo(n, { focus: true })
  }
  if (config.mode === "student") window.addEventListener("hashchange", onHash)
  const start = config.mode === "student" ? fromHash() : (config.startCard ?? null)
  if (state.view === "scroll") {
    renderScroll()
    state.n = start && byN.has(start) ? start : 0
    ensureRendered(state.n)
    refreshChrome()
    if (start) stage.querySelector(`#scheda-${state.n}`)?.scrollIntoView?.()
  } else goTo(start && byN.has(start) ? start : 0, { focus: false })
  announce(state.n)

  return {
    goTo, renderAll, setView, setReduceMotion,
    current: () => state.n,
    // the drawn figures (api.element, api.total, api.setState(i)): the render check steps through their states
    figures: () => [...trackers],
    view: () => state.view,
    setTeacher(on) {
      state.teacher = !!on
      built.clear()
      trackers.clear()
      if (state.view === "scroll") {
        renderScroll()
        ensureRendered(state.n)
      } else goTo(state.n, { focus: false })
    },
    relayout() {
      for (const api of trackers) api.relayout()
    },
    destroy() {
      document.removeEventListener("keydown", onKey)
      window.removeEventListener("hashchange", onHash)
      window.removeEventListener("beforeprint", onBeforePrint)
      printQuery?.removeEventListener?.("change", onPrintChange)
      observer?.disconnect()
      clearTimeout(seenTimer)
      clearTimeout(flushTimer)
      for (const api of trackers) api.destroy?.()
      clear(root)
    }
  }
}

// The teacher's full body (author form): the answer-side fields found by card, block, step or exercise.
function fullAccess(full) {
  const card = (n) => full.cards?.find((c) => c.n === n)
  const block = (c, b) => card(c)?.blocks?.find((x) => x.n === b)
  return {
    spec(loc) {
      const b = block(loc.card, loc.block)
      if (!b) return null
      if (loc.ex) {
        const ex = b.exercises?.find((e) => e.n === loc.ex)
        return ex ? (ex.checks ? ex.checks[(loc.part ?? 1) - 1] : ex.check) : null
      }
      if (loc.step) return b.steps?.[loc.step - 1]?.blank ?? null
      return b
    },
    exercise: (c, b, n) => block(c, b)?.exercises?.find((e) => e.n === n) ?? null
  }
}
