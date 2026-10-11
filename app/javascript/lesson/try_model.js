// The number "x = N" tried in the boxes of balances, as one value with its listeners. A card with several balances has ONE
// model (the cases' shared stepper); a lone balance has its own. A compact balance (a row of the cases) has no stepper or
// readout of its own: it only listens, so no second copy of the number can disagree with the one on screen.
export function tryModel(range, listeners = []) {
  const from = Number(range.from)
  const to = Number(range.to)
  const model = {
    from,
    to,
    value: from,
    set(n) {
      model.value = Math.max(from, Math.min(to, n))
      listeners.forEach((fn) => fn(model.value))
      return model.value
    },
    atMin: () => model.value <= from,
    atMax: () => model.value >= to
  }
  return model
}
