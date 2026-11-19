// A figure measures its labels in the DOM, so what it draws depends on the face the text is measured in. A web font is fetched when text first wears
// it: a figure that measures before the face is there measures the fallback face (a few per cent narrower or wider), and the layout it chooses can
// be another one (D-383: the same Do While drawn as a centred tree in one render and as the indented layout in the next, 3 % of text width apart).
// The lesson's render host waits for the faces before it draws; the student's page cannot wait, so every figure asks to be told when the faces load:
// `again` is called when a load batch finishes (and once when the faces were still loading at the call), and the figure forgets what it measured
// and lays out again. Returns the function that stops listening.
export function onFontsLoaded(again, fonts = globalThis.document?.fonts) {
  if (!fonts || typeof fonts.addEventListener !== "function") return () => {}
  let live = true
  const handler = () => { if (live) again() }
  fonts.addEventListener("loadingdone", handler)
  if (fonts.status === "loading") fonts.ready?.then(handler)
  return () => {
    live = false
    fonts.removeEventListener("loadingdone", handler)
  }
}
