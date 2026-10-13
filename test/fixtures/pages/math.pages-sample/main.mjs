import { banco } from "banco"
import { meet } from "./maths.mjs"

const { reducedMotion } = await banco.init()
const root = document.getElementById("app")

const canvas = document.createElement("canvas")
canvas.width = 480
canvas.height = 240
canvas.setAttribute("role", "img")
canvas.setAttribute("aria-label", "Due rette in un piano. Il cursore cambia la pendenza della prima e il punto d'incontro si sposta.")
const g = canvas.getContext("2d")

const row = document.createElement("div")
row.className = "banco-row"
const label = document.createElement("label")
label.setAttribute("for", "slope")
label.textContent = "Pendenza della prima retta"
const slider = document.createElement("input")
slider.id = "slope"
slider.type = "range"
slider.min = "-3"
slider.max = "3"
slider.step = "0.5"
slider.value = String(Math.round((banco.random() * 4 - 2) * 2) / 2)
const readout = document.createElement("span")
readout.className = "banco-readout"
readout.setAttribute("aria-live", "polite")
const reset = document.createElement("button")
reset.type = "button"
reset.textContent = "Ricomincia"
row.append(label, slider, readout, reset)
root.append(canvas, row)

const style = getComputedStyle(document.body)
const colors = () => ({ fg: style.color, bg: style.backgroundColor })

function draw() {
  const a = Number(slider.value)
  const point = meet(a, 0.5, -0.5, 1)
  const { fg, bg } = colors()
  g.fillStyle = bg
  g.fillRect(0, 0, 480, 240)
  g.strokeStyle = fg
  g.lineWidth = 2
  const line = (m, q) => {
    g.beginPath()
    g.moveTo(0, 120 - (m * -6 + q) * 20)
    g.lineTo(480, 120 - (m * 6 + q) * 20)
    g.stroke()
  }
  line(a, 0.5)
  line(-0.5, 1)
  if (point) {
    g.fillStyle = fg
    g.beginPath()
    g.arc(240 + point.x * 20, 120 - point.y * 20, 6, 0, 6.2832)
    g.fill()
  }
  readout.textContent = point ? `Si incontrano in (${point.x.toFixed(1)}; ${point.y.toFixed(1)})` : "Le rette sono parallele"
}

slider.addEventListener("input", () => {
  draw()
  banco.event("interacted", { slope: Number(slider.value) })
})
reset.addEventListener("click", () => {
  slider.value = "0"
  draw()
  banco.event("interacted", { reset: true })
})
draw()
banco.ready()
if (!reducedMotion) banco.onVisibility(() => draw())
