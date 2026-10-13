// The rows of the table: what each browser must do or must not do (SPEC B10.8). "must" is what the lesson page depends on.
// A "blocked" row is good: the sandbox and the CSP held. The WebRTC row only reports what the kit's stub does: the CSP does not
// cover WebRTC (a residual accepted in D-261), so a second realm would be needed to see the browser itself.
export const ROWS = [
  { id: "module", label: "Il modulo si carica dall'origine delle pagine", must: "works" },
  { id: "kit", label: "Il kit risponde (banco.init)", must: "works" },
  { id: "three", label: "three si carica con la mappa dei moduli", must: "works" },
  { id: "webgl", label: "Un contesto WebGL si apre", must: "works-or-fallback" },
  { id: "texture", label: "La texture PNG si carica", must: "works" },
  { id: "font", label: "Il font Atkinson Hyperlegible si carica", must: "works" },
  { id: "bridge", label: "Il ponte con la lezione risponde", must: "works" },
  { id: "fetch_own", label: "fetch verso la propria origine", must: "blocked" },
  { id: "fetch_app", label: "fetch verso l'app", must: "blocked" },
  { id: "cookie", label: "document.cookie", must: "blocked" },
  { id: "top", label: "top.location", must: "blocked" },
  { id: "frame", label: "Un secondo frame (altro mondo)", must: "blocked" },
  { id: "rtc", label: "RTCPeerConnection (il kit la sostituisce)", must: "blocked" },
  { id: "prefetch", label: "link rel=prefetch", must: "blocked" },
  { id: "storage", label: "localStorage", must: "blocked" }
]

// 1 character per row, in order: w works, b blocked, x failed to work, n not blocked. 15 characters: well under 1 KB.
export function encode(results) {
  return ROWS.map((row) => results[row.id] ?? "x").join("")
}

export function verdict(row, result) {
  if (row.must === "blocked") return result === "b" ? "ok" : "da controllare"
  if (row.must === "works-or-fallback") return result === "w" || result === "f" ? "ok" : "da controllare"
  return result === "w" ? "ok" : "da controllare"
}
