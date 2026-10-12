// The pure state of the two sequence inputs (WAVE2 2.11): tiles (a line the student builds from a bank, distractors included) and ordering
// (every item is in the list from the start and the student moves them). No DOM here: tiles.js, ordering.js and the `oral` outline (T8)
// draw it. Ids are the shown ids the server gave (e1..eN); the response of the check is the list of ids in the line, in order.

// tiles: { line: [ids], bank: [ids not in the line, in the served order] }
export function createTiles(ids) {
  const all = [...ids]
  let line = []
  const api = {
    all: () => [...all],
    line: () => [...line],
    bank: () => all.filter((id) => !line.includes(id)),
    has: (id) => line.includes(id),
    // a tile of the bank goes to the end of the line; a tile already there stays (no tile is used twice)
    place(id) {
      if (all.includes(id) && !line.includes(id)) line = [...line, id]
      return api
    },
    // a tile of the line goes back to the bank
    remove(id) {
      line = line.filter((x) => x !== id)
      return api
    },
    // a tile of the line moves one position (-1 left, +1 right); at an end it stays
    move(id, delta) {
      const from = line.indexOf(id)
      const to = from + delta
      if (from < 0 || to < 0 || to >= line.length) return api
      const next = [...line]
      next.splice(from, 1)
      next.splice(to, 0, id)
      line = next
      return api
    },
    clear() {
      line = []
      return api
    }
  }
  return api
}

// ordering: the list starts in the served order
export function createOrdering(ids) {
  let order = [...ids]
  const api = {
    order: () => [...order],
    move(id, delta) {
      const from = order.indexOf(id)
      const to = from + delta
      if (from < 0 || to < 0 || to >= order.length) return api
      const next = [...order]
      next.splice(from, 1)
      next.splice(to, 0, id)
      order = next
      return api
    }
  }
  return api
}
