// expression: the MathLive editor (E-04) with a rendered echo, or, for a student
// whose editor warm-up failed, a plain text box with the same echo (source "text").
//
// MathLive runs from the app origin only: fonts from /vendor/mathlive@0.111.0/fonts/,
// sounds off, the Italian decimal comma, `rad` for the square root, smartSuperscript
// on. With smartSuperscript a two-digit exponent cannot be typed, so items do not
// use one (E-EXPONENT-MULTIDIGIT). The server reads mf.value (LaTeX), never
// mf.expression.
import { el, handle, uid } from "items/dom"
import { renderMath } from "items/markup"

const VENDOR = "/vendor/mathlive@0.111.0"
const COMPUTE_ENGINE = "/vendor/compute-engine@0.146.0/compute-engine.js"

let loading = null

// Loads MathLive once and sets its static configuration. Never from a CDN: the
// Compute Engine that MathLive would fetch from esm.run is replaced by our copy.
export function loadMathlive() {
  loading ||= import("mathlive").then(async (module) => {
    const { MathfieldElement } = module
    MathfieldElement.fontsDirectory = `${VENDOR}/fonts/`
    MathfieldElement.soundsDirectory = null
    MathfieldElement.keypressSound = null
    MathfieldElement.plonkSound = null
    MathfieldElement.decimalSeparator = ","
    import(COMPUTE_ENGINE).then(({ ComputeEngine }) => {
      MathfieldElement.computeEngine = new ComputeEngine()
    }).catch(() => {})
    return module
  })
  return loading
}

export async function render(part, ctx) {
  return part.input === "text" ? textInput(ctx) : mathInput(ctx)
}

function echoBox(ctx) {
  const math = el("span", { class: "echo-math" })
  const box = el("div", { class: "echo", "aria-live": "polite" }, el("span", { class: "hint", text: `${ctx.t.expression_echo} ` }), math)
  return { box, show: (latex) => { math.textContent = ""; if (latex.trim() !== "") renderMath(latex, math) } }
}

async function mathInput(ctx) {
  await loadMathlive()
  const field = document.createElement("math-field")
  field.className = "math-input"
  field.setAttribute("aria-label", ctx.t.expression_label)
  const echo = echoBox(ctx)
  field.addEventListener("input", () => echo.show(field.value))
  const wrapper = el("div", { class: "answer" }, el("p", { class: "hint", text: ctx.t.expression_label }), field, echo.box)
  return handle(wrapper, {
    raw: () => field.value,
    isEmpty: () => field.value.trim() === "",
    source: "mathlive",
    focus: () => field.focus(),
    mounted: () => {
      // Needs the field in the document: the Italian configuration (E-04).
      field.mathVirtualKeyboardPolicy = "manual"
      field.smartSuperscript = true
      field.inlineShortcuts = { ...field.inlineShortcuts, rad: "\\sqrt{#?}" }
    }
  })
}

function textInput(ctx) {
  const id = uid("expr")
  const input = el("input", { id, type: "text", autocomplete: "off", autocapitalize: "off", spellcheck: "false", class: "answer-input wide" })
  const echo = echoBox(ctx)
  input.addEventListener("input", () => echo.show(input.value))
  const wrapper = el("div", { class: "answer" },
    el("label", { for: id, class: "hint", text: ctx.t.expression_label }),
    el("p", { class: "hint", text: ctx.t.expression_text_hint }), input, echo.box)
  return handle(wrapper, {
    raw: () => input.value.trim(),
    isEmpty: () => input.value.trim() === "",
    source: "text",
    focus: () => input.focus()
  })
}
