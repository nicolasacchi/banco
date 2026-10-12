// Money: exact euro amounts, half-up cents, VAT per rate and the rows of an invoice (WAVE2 1.10, batch w2-1, track T8).
// The twin of Lessons::Money (lib/lessons/money.rb): both run test/fixtures/lesson2/money.json. An amount is written the Italian way
// ("2,50", "1240") and comes back as euros with two decimals and a comma ("2000,00"); display() adds the thousands dot for the page.
// BigInt rationals from lesson/num; no float anywhere.
import * as N from "lesson/num"

// name => signature
export const SIGNATURES = {
  "round_half_up": "roundHalfUp(amount)",
  "vat": "vat(net, rate)",
  "row": "row(qty, price)",
  "invoice": "invoice(spec)"
}

export class Refused extends Error {}

// The rows of an invoice in the order the page draws them.
export const ROWS = ["gross", "discounts", "net", "costs_in", "base", "vat", "costs_out", "interest", "total"]
// The closed list of typical errors an invoice can be drawn with.
export const ERROR_VARIANTS = [
  "taxable_base_on_gross", "vat_on_gross_added_to_net", "documented_costs_taxed", "undocumented_costs_untaxed", "undocumented_costs_omitted",
  "successive_discounts_added", "two_rates_single_rate", "two_rates_combined", "vat_added_as_amount"
]
export const RATES = ["22", "10", "5", "4"]
const OUTSIDE_BASE = ["undocumented_costs_untaxed", "undocumented_costs_omitted"]

const ZERO = N.int(0)
const sum = (list) => list.reduce((a, b) => N.add(a, b), ZERO)

function number(text) {
  if (text && typeof text === "object" && "n" in text) return text
  const x = N.parse(String(text))
  if (!x) throw new Refused(`${JSON.stringify(text)} is not an amount`)
  return x
}

// Rounded to whole cents, half up (away from zero), still in euros.
export function cents(value) {
  const scaled = N.mul(value, N.int(100))
  const abs = scaled.n < 0n ? N.neg(scaled) : scaled
  const whole = N.make((abs.n * 2n + abs.d) / (2n * abs.d)) // floor(abs + 1/2)
  return N.make(scaled.n < 0n ? -whole.n : whole.n, 100n)
}

// "2000,00": euros, two decimals, a comma.
export function format(value) {
  const c = N.mul(value, N.int(100))
  const whole = c.n / c.d // the value is a multiple of a cent: exact
  const abs = whole < 0n ? -whole : whole
  return `${whole < 0n ? "-" : ""}${abs / 100n},${(abs % 100n).toString().padStart(2, "0")}`
}

// "1.240,50": the thousands dot of the page.
export function display(text) {
  const m = String(text).match(/^(-?)(\d+),(\d+)$/)
  if (!m) return String(text)
  return `${m[1]}${m[2].replace(/\B(?=(\d{3})+(?!\d))/g, ".")},${m[3]}`
}

export const roundHalfUp = (amount) => format(cents(number(amount)))
export const vat = (net, rate) => format(cents(N.div(N.mul(number(net), number(rate)), N.int(100))))
export const row = (qty, price) => format(cents(N.mul(number(qty), number(price))))

const pct = (value, rate) => cents(N.div(N.mul(value, rate), N.int(100)))

function compute(spec) {
  const lines = spec.lines ?? []
  if (lines.length === 0) throw new Refused("an invoice has goods lines")
  const amounts = lines.map((l) => cents(N.mul(number(l.qty), number(l.price))))
  const rates = []
  for (const l of lines) {
    const r = number(l.vat)
    if (!rates.some((x) => N.eq(x, r))) rates.push(r)
  }
  const gross = rates.map(() => ZERO)
  lines.forEach((l, i) => {
    const at = rates.findIndex((r) => N.eq(r, number(l.vat)))
    gross[at] = N.add(gross[at], amounts[i])
  })
  const percents = (spec.discounts ?? []).map(number)
  const costs = spec.costs ?? []
  const costsIn = sum(costs.filter((k) => !k.documented).map((k) => cents(number(k.amount))))
  const costsOut = sum(costs.filter((k) => k.documented).map((k) => cents(number(k.amount))))
  if (rates.length > 1 && costsIn.n > 0n) throw new Refused("with two VAT rates a cost that is not documented has no rate")
  const net = gross.map((g) => percents.reduce((run, p) => N.sub(run, pct(run, p)), g))
  return { lines: amounts, rows: rowsOf({ rates, percents, gross, net, costsIn, costsOut, interest: spec.interest }, spec.error) }
}

function rowsOf(p, error) {
  if (error && !ERROR_VARIANTS.includes(error)) throw new Refused(`${JSON.stringify(error)} is not an invoice error`)
  const single = p.rates.length === 1
  if (error === "documented_costs_taxed" && !single) throw new Refused(`${error} needs one VAT rate`)
  if ((error === "two_rates_single_rate" || error === "two_rates_combined") && single) throw new Refused(`${error} needs two VAT rates`)
  const net = error === "successive_discounts_added" ? p.gross.map((g) => N.sub(g, pct(g, sum(p.percents)))) : p.net
  const grossTotal = sum(p.gross)
  const netTotal = sum(net)
  const bases = (error === "taxable_base_on_gross" ? p.gross : net).slice()
  if (single && !OUTSIDE_BASE.includes(error)) bases[0] = N.add(bases[0], p.costsIn)
  if (error === "documented_costs_taxed") bases[0] = N.add(bases[0], p.costsOut)
  const base = sum(bases)
  let vatRow
  if (error === "vat_on_gross_added_to_net") vatRow = sum(p.gross.map((g, i) => pct(g, p.rates[i])))
  else if (error === "two_rates_single_rate") vatRow = pct(base, p.rates[0])
  else if (error === "two_rates_combined") vatRow = pct(base, sum(p.rates))
  else vatRow = sum(bases.map((b, i) => pct(b, p.rates[i])))
  const shownVat = error === "vat_added_as_amount" ? N.add(base, vatRow) : vatRow
  const costsIn = error === "undocumented_costs_omitted" ? ZERO : p.costsIn
  const costsOut = error === "documented_costs_taxed" ? ZERO : p.costsOut
  const interest = p.interest ? cents(N.mul(N.div(N.mul(netTotal, number(p.interest.rate)), N.int(100)), N.make(BigInt(p.interest.days ?? 0), BigInt(p.interest.year ?? 360)))) : ZERO
  const afterVat = error === "undocumented_costs_untaxed" ? p.costsIn : ZERO
  const total = sum([base, shownVat, afterVat, costsOut, interest])
  return { gross: grossTotal, discounts: N.sub(grossTotal, netTotal), net: netTotal, costs_in: costsIn, base, vat: shownVat, costs_out: costsOut, interest, total }
}

// All rows of an invoice from its data: { lines: [amounts], rows: { id: amount } }. spec.error (one of ERROR_VARIANTS) draws the rows that
// typical error computes. Throws Refused when the invoice cannot be computed.
export function invoice(spec) {
  const c = compute(spec)
  return { lines: c.lines.map(format), rows: Object.fromEntries(ROWS.map((id) => [id, format(c.rows[id])])) }
}

// The same invoice without its error.
export function correct(spec) {
  const { error: _error, ...rest } = spec
  return invoice(rest)
}
