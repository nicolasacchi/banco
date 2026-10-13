// The browser matrix page (SPEC B10.8): exercises, inside the real iframe of the real page, what the lesson depends on and what
// must stay blocked, and reports a table. It is stored by the operator's console (bin/rails banco:pages_selftest), never submitted by an agent:
// it deliberately uses the APIs the page rules refuse.
import { banco } from "banco"
import * as THREE from "three"
import { ROWS, encode, verdict } from "./rows.mjs"

const results = {}
const root = document.getElementById("app")
const note = (id, value) => { results[id] = value }

const init = await banco.init()
note("kit", typeof init.seed === "number" ? "w" : "x")
note("module", "w")
note("three", typeof THREE.WebGLRenderer === "function" ? "w" : "x")

const violations = []
document.addEventListener("securitypolicyviolation", (e) => violations.push(e.violatedDirective))

// the scene: a cube with a PNG texture, if WebGL is there
const holder = document.createElement("div")
holder.style.cssText = "height:200px;display:flex;justify-content:center"
root.append(holder)
const canvas = document.createElement("canvas")
canvas.setAttribute("role", "img")
canvas.setAttribute("aria-label", "Un cubo a quadri che gira.")
holder.append(canvas)
let renderer = null
try {
  if (banco.webgl()) renderer = new THREE.WebGLRenderer({ canvas, antialias: false })
} catch (_e) { renderer = null }
note("webgl", renderer ? "w" : "f")

const texture = await new Promise((resolve) => {
  new THREE.TextureLoader().load("assets/checker.png", (t) => resolve(t), undefined, () => resolve(null))
})
note("texture", texture && texture.image && texture.image.width === 16 ? "w" : "x")

if (renderer) {
  renderer.setSize(300, 200, false)
  const scene = new THREE.Scene()
  const camera = new THREE.PerspectiveCamera(50, 1.5, 0.1, 10)
  camera.position.z = 2.4
  const cube = new THREE.Mesh(new THREE.BoxGeometry(1, 1, 1), new THREE.MeshBasicMaterial({ map: texture }))
  scene.add(cube)
  const draw = (t) => { cube.rotation.y = init.reducedMotion ? 0.6 : t / 1500; cube.rotation.x = 0.4; renderer.render(scene, camera); return !init.reducedMotion }
  banco.loop(draw)
}

// the font of the kit
try {
  await document.fonts.load('16px "Atkinson Hyperlegible"')
  note("font", document.fonts.check('16px "Atkinson Hyperlegible"') ? "w" : "x")
} catch (_e) { note("font", "x") }

// what must be blocked
const blocked = async (id, attempt) => {
  try {
    const out = await attempt()
    note(id, out === "blocked" ? "b" : "n")
  } catch (_e) {
    note(id, "b")
  }
}
await blocked("fetch_own", async () => { await fetch("/kit/banco-page@1.0/page.css"); return "went" })
await blocked("fetch_app", async () => { await fetch("https://banco.scc.im/up", { mode: "no-cors" }); return "went" })
await blocked("cookie", async () => { document.cookie = "x=1"; return document.cookie === "" ? "blocked" : "went" })
await blocked("top", async () => { return String(top.location.href).length > 0 ? "went" : "blocked" })
await blocked("storage", async () => { localStorage.setItem("x", "1"); return "went" })
await blocked("frame", async () => {
  const f = document.createElement("iframe")
  f.setAttribute("srcdoc", "<p>x</p>")
  const before = violations.length
  document.body.append(f)
  await new Promise((resolve) => setTimeout(resolve, 300))
  const ok = violations.length > before
  f.remove()
  return ok ? "blocked" : "went"
})
await blocked("rtc", async () => { new RTCPeerConnection(); return "went" })
await blocked("prefetch", async () => {
  const before = violations.length
  const link = document.createElement("link")
  link.rel = "prefetch"
  link.href = "https://example.org/x"
  document.head.append(link)
  await new Promise((resolve) => setTimeout(resolve, 400))
  return violations.length > before ? "blocked" : "went"
})
note("bridge", "w")

// the table
const table = document.createElement("table")
table.style.cssText = "width:100%;border-collapse:collapse;font-size:0.9rem"
const head = table.createTHead().insertRow()
for (const text of ["Prova", "Atteso", "Risultato", "Esito"]) {
  const th = document.createElement("th")
  th.textContent = text
  th.style.cssText = "text-align:left;border-bottom:2px solid var(--line);padding:0.2rem 0.4rem"
  head.append(th)
}
const WORDS = { w: "funziona", b: "bloccato", n: "NON bloccato", x: "non funziona", f: "senza 3D (testo)" }
const EXPECT = { works: "funziona", blocked: "bloccato", "works-or-fallback": "funziona o testo" }
for (const row of ROWS) {
  const tr = table.insertRow()
  const out = verdict(row, results[row.id] ?? "x")
  for (const text of [row.label, EXPECT[row.must], WORDS[results[row.id] ?? "x"], out]) {
    const td = tr.insertCell()
    td.textContent = text
    td.style.cssText = "border-bottom:1px solid var(--line);padding:0.2rem 0.4rem"
  }
  tr.dataset.row = row.id
  tr.dataset.verdict = out
}
table.setAttribute("aria-label", "Esito delle prove del browser")
root.append(table)
banco.ready()
banco.event("done", { rows: encode(results), ua: "n" })
