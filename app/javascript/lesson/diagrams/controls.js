// The controls a diagram type declares with controls(data) (contract v2, WAVE2 1.2), built as native elements: a group of chips
// (buttons with aria-pressed; `multi` lets several be on at once). The values live in state.controls[id] and go to layout() in
// ctx.controls; the type draws from them and never touches the DOM. Other kinds (stepper, slider, toggle, runner) are added by the
// tracks that need them, one case each.
import { button, el } from "lesson/dom"
import { renderInlineRich } from "lesson/text"

export function buildControls(list, host, { state, ctx, redraw }) {
  for (const control of list) {
    if (control.kind !== "chips") continue
    const group = el("div", { class: "dg-chips", role: "group", "aria-label": control.label_it })
    const heading = el("span", { class: "dg-chips-label", text: control.label_it })
    const chips = control.values.map((v) => {
      const chip = button("", { class: "dg-chipbtn", "aria-pressed": "false" }, () => {
        const now = new Set(state.controls[control.id] ?? [])
        if (!control.multi) now.clear()
        if (now.has(v.value)) now.delete(v.value)
        else now.add(v.value)
        state.controls[control.id] = [...now]
        for (const other of chips) other.setAttribute("aria-pressed", String(now.has(other.dataset.value)))
        redraw()
      })
      chip.dataset.value = v.value
      renderInlineRich(v.label_it, chip, ctx)
      return chip
    })
    group.append(heading, ...chips)
    if (control.hint_it) group.append(el("span", { class: "dg-chips-hint", text: control.hint_it }))
    host.appendChild(group)
  }
}
