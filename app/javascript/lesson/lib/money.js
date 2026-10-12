// Money: Exact euro amounts (Rational), half-up cents, VAT per rate and invoice rows.
// Contract stub of W2-0 (WAVE2 1.10, batch w2-1, track T8): the signatures below are frozen; the bodies are the track's. The Ruby twin is
// lib/lessons/money.rb and both run test/fixtures/lesson2/money.json.
import { notBuilt } from "lesson/lib/not_built"

// name => signature
export const SIGNATURES = {
  "round_half_up": "roundHalfUp(amount)",
  "vat": "vat(net, rate)",
  "row": "row(qty, price)",
  "invoice": "invoice(spec)"
}

// An amount rounded to cents, half up.
export const roundHalfUp = notBuilt("money.roundHalfUp", "T8", "w2-1")
// The VAT of an amount at a rate in percent, rounded half up.
export const vat = notBuilt("money.vat", "T8", "w2-1")
// One invoice row: quantity times price.
export const row = notBuilt("money.row", "T8", "w2-1")
// All rows of an invoice from its data; ERROR_VARIANTS is the closed list of typical errors.
export const invoice = notBuilt("money.invoice", "T8", "w2-1")
