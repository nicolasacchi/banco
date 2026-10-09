import { Controller } from "@hotwired/stimulus"

// A teacher page that comes back from a decision with a success flash tells the other tabs of the
// browser (an open dashboard among them) that something was decided.
export default class extends Controller {
  static values = { notify: Boolean }

  connect() {
    if (!this.notifyValue || !("BroadcastChannel" in window)) return
    const channel = new BroadcastChannel("banco")
    channel.postMessage({ type: "decided", at: Date.now() })
    channel.close()
  }
}
