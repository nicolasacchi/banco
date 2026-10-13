// banco-page kit 1.0: boot. Runs before the page's main.mjs (module scripts run in document order, B3).
// It forwards errors, rejected promises, CSP violations and console errors to the parent, and replaces the
// APIs a page has no reason to use and that CSP does not cover with stubs that throw (B6). The stubs are a
// tripwire for honest mistakes, not a boundary: the boundary is the sandbox and the CSP of the shell.
const BRIDGE = "banco-page/1"

function send(message) {
  try {
    window.parent.postMessage({ bridge: BRIDGE, type: "error", message: String(message).slice(0, 300) }, "*")
  } catch (_e) { /* nothing to tell */ }
}

window.addEventListener("error", (e) => send(`uncaught: ${e.message || "error"} (${(e.filename || "").split("/").pop()}:${e.lineno || 0})`))
window.addEventListener("unhandledrejection", (e) => send(`uncaught: unhandled rejection: ${e.reason && e.reason.message ? e.reason.message : e.reason}`))
document.addEventListener("securitypolicyviolation", (e) => send(`csp: ${e.violatedDirective} blocked ${e.blockedURI || "inline"}`))

const consoleError = console.error.bind(console)
console.error = (...args) => {
  send(`console: ${args.map((a) => (a && a.message) || String(a)).join(" ")}`)
  consoleError(...args)
}

function stub(name) {
  return function bancoStub() {
    send(`api: ${name} is not available to a page`)
    throw new Error(`${name} is not available to a page`)
  }
}

for (const name of ["RTCPeerConnection", "webkitRTCPeerConnection", "RTCDataChannel", "Notification", "PaymentRequest", "BroadcastChannel"]) {
  try {
    Object.defineProperty(window, name, { value: stub(name), configurable: false, writable: false })
  } catch (_e) { /* a browser that does not allow it: the scan and the review still look */ }
}
try { Object.defineProperty(window, "open", { value: stub("open"), configurable: false, writable: false }) } catch (_e) { /* as above */ }
try { navigator.sendBeacon = stub("navigator.sendBeacon") } catch (_e) { /* as above */ }
try {
  Object.defineProperty(navigator, "serviceWorker", { get: () => { send("api: navigator.serviceWorker is not available to a page"); throw new Error("navigator.serviceWorker is not available to a page") }, configurable: false })
} catch (_e) { /* as above */ }
