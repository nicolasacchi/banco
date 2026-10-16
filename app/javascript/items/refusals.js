// Refused answers on the student's pages (D-298): after an answer the server calls unreadable, the send
// button is inert for a moment (a held or repeated Enter on the button sent the same text again and
// again), and when the same item is refused a second time its answer format is shown with the message.
// Pure logic, no DOM: the sitting and the practice controllers use it, and node tests it.
export const COOLDOWN_MS = 1500
export const SHOW_FORMAT_AT = 2

export class Refusals {
  constructor({ cooldownMs = COOLDOWN_MS } = {}) {
    this.cooldownMs = cooldownMs
    this.counts = new Map()
    this.until = 0
  }

  // One more refusal of this item at time `now` (ms); returns how many times it has been refused.
  record(itemKey, now) {
    const n = (this.counts.get(itemKey) || 0) + 1
    this.counts.set(itemKey, n)
    this.until = now + this.cooldownMs
    return n
  }

  cooling(now) {
    return now < this.until
  }

  // The format line goes up from the second refusal of the item and stays for that item.
  showFormat(itemKey) {
    return (this.counts.get(itemKey) || 0) >= SHOW_FORMAT_AT
  }
}
