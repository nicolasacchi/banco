# frozen_string_literal: true

module Lessons
  # Money: exact euro amounts (Rational), half-up cents, VAT per rate and the rows of an invoice (WAVE2 1.10, batch w2-1, track T8).
  # An amount is written the Italian way ("2,50", "1240", "7,5") and comes back as euros with two decimals and a comma ("2000,00"); the
  # thousands dot is drawn by the page (display), never by the functions. Nothing here uses a float. The JS twin is
  # app/javascript/lesson/lib/money.js; both run test/fixtures/lesson2/money.json (like Lessons::Num and lesson/num.js).
  #
  # The invoice (business.md 2.1). The goods are the lines (quantity times price, rounded to the cent); the discounts are successive, each
  # on the amount already discounted and rounded to the cent; the costs that are not documented (the seller's own) enter the imponibile,
  # the documented ones (advanced in the buyer's name) stay outside it and are added after the VAT; the VAT of each rate is on the
  # imponibile of that rate, rounded half up; the interest (when given) is on the net goods and is added after the documented costs
  # (whether it enters the imponibile is an open book convention, so the library does not assume it). An invoice with two VAT rates cannot
  # have a cost that is not documented (no rule says which rate it takes): Money refuses it.
  module Money
    NotBuilt = Class.new(NotImplementedError)
    Refused = Class.new(ArgumentError)
    # name => signature (Ruby)
    SIGNATURES = {
      "round_half_up" => "round_half_up(amount)",
      "vat" => "vat(net, rate)",
      "row" => "row(qty, price)",
      "invoice" => "invoice(spec)"
    }.freeze
    # The rows of an invoice in the order the page draws them.
    ROWS = %w[gross discounts net costs_in base vat costs_out interest total].freeze
    # The closed list of typical errors an invoice can be drawn with (the codes of the graph's skill).
    ERROR_VARIANTS = %w[
      taxable_base_on_gross vat_on_gross_added_to_net documented_costs_taxed undocumented_costs_untaxed undocumented_costs_omitted
      successive_discounts_added two_rates_single_rate two_rates_combined vat_added_as_amount
    ].freeze
    # The VAT rates of the programme.
    RATES = %w[22 10 5 4].freeze
    OUTSIDE_BASE = %w[undocumented_costs_untaxed undocumented_costs_omitted].freeze

    module_function

    # An amount rounded to cents, half up: "2,505" is "2,51".
    def round_half_up(amount) = format(cents(number(amount)))

    # The VAT of an amount at a rate in percent, rounded half up.
    def vat(net, rate) = format(cents(number(net) * number(rate) / 100))

    # One invoice row: quantity times price, rounded to the cent.
    def row(qty, price) = format(cents(number(qty) * number(price)))

    # All rows of an invoice from its data (the document diagram's fields):
    # {"lines" => [the amount of each line], "rows" => {row id => amount}}. With spec["error"] (one of ERROR_VARIANTS) the rows are those
    # that typical error computes. Refused when the invoice cannot be computed.
    def invoice(spec)
      c = compute(spec)
      { "lines" => c[:lines].map { |v| format(v) }, "rows" => ROWS.to_h { |id| [ id, format(c[:rows].fetch(id)) ] } }
    end

    # The same invoice without its error (what it would say if it were right).
    def correct(spec) = invoice(spec.reject { |k, _| k == "error" })

    # A Rational from an Italian number; Refused when it is not one.
    def number(text)
      return text if text.is_a?(Rational)

      Num.parse(text.to_s) or raise Refused, "#{text.inspect} is not an amount"
    end

    # A Rational rounded to whole cents, half up (away from zero), still in euros.
    def cents(value)
      scaled = value * 100
      whole = (scaled.abs + Rational(1, 2)).floor
      Rational(scaled.negative? ? -whole : whole, 100)
    end

    # "2000,00": euros, two decimals, a comma.
    def format(value)
      c = (value * 100).round
      "#{'-' if c.negative?}#{c.abs / 100},#{(c.abs % 100).to_s.rjust(2, '0')}"
    end

    # "1.240,50": the thousands dot of the page.
    def display(text)
      sign, whole, frac = text.match(/\A(-?)(\d+),(\d+)\z/).captures
      "#{sign}#{whole.reverse.scan(/\d{1,3}/).join('.').reverse},#{frac}"
    end

    # ---- the invoice ------------------------------------------------------------------------------------

    def compute(spec)
      lines = Array(spec["lines"])
      raise Refused, "an invoice has goods lines" if lines.empty?

      amounts = lines.map { |l| cents(number(l["qty"]) * number(l["price"])) }
      rates = lines.map { |l| number(l["vat"]) }.uniq
      gross_by_rate = rates.to_h { |r| [ r, Rational(0) ] }
      lines.each_with_index { |l, i| gross_by_rate[number(l["vat"])] += amounts[i] }
      percents = Array(spec["discounts"]).map { |d| number(d) }
      costs = Array(spec["costs"])
      costs_in = costs.reject { |k| k["documented"] }.sum(Rational(0)) { |k| cents(number(k["amount"])) }
      costs_out = costs.select { |k| k["documented"] }.sum(Rational(0)) { |k| cents(number(k["amount"])) }
      raise Refused, "with two VAT rates a cost that is not documented has no rate" if rates.size > 1 && costs_in.positive?

      net_by_rate = gross_by_rate.transform_values { |g| percents.reduce(g) { |run, pct| run - cents(run * pct / 100) } }
      parts = { rates: rates, percents: percents, gross_by_rate: gross_by_rate, net_by_rate: net_by_rate,
                costs_in: costs_in, costs_out: costs_out, interest: spec["interest"] }
      { lines: amounts, rows: rows_of(parts, spec["error"]) }
    end

    # The rows (Rational), with the typical error applied when one is named.
    def rows_of(p, error)
      raise Refused, "#{error.inspect} is not an invoice error" if error && !ERROR_VARIANTS.include?(error)

      first = p[:rates].first
      single = p[:rates].size == 1
      raise Refused, "#{error} needs one VAT rate" if error == "documented_costs_taxed" && !single
      raise Refused, "#{error} needs two VAT rates" if %w[two_rates_single_rate two_rates_combined].include?(error) && single

      net_by_rate = error == "successive_discounts_added" ? successive_added(p) : p[:net_by_rate]
      gross = p[:gross_by_rate].values.sum(Rational(0))
      net = net_by_rate.values.sum(Rational(0))
      base_by_rate = (error == "taxable_base_on_gross" ? p[:gross_by_rate] : net_by_rate).dup
      base_by_rate[first] += p[:costs_in] if single && !OUTSIDE_BASE.include?(error)
      base_by_rate[first] += p[:costs_out] if error == "documented_costs_taxed"
      base = base_by_rate.values.sum(Rational(0))
      vat = vat_of(base_by_rate, base, p, error)
      vat_row = error == "vat_added_as_amount" ? base + vat : vat
      costs_in = error == "undocumented_costs_omitted" ? Rational(0) : p[:costs_in]
      costs_out = error == "documented_costs_taxed" ? Rational(0) : p[:costs_out]
      interest = interest_of(net, p[:interest])
      after_vat = error == "undocumented_costs_untaxed" ? p[:costs_in] : Rational(0)
      total = base + vat_row + after_vat + costs_out + interest
      { "gross" => gross, "discounts" => gross - net, "net" => net, "costs_in" => costs_in, "base" => base, "vat" => vat_row,
        "costs_out" => costs_out, "interest" => interest, "total" => total }
    end

    # The VAT of the imponibile, by rate; the errors that change the rate or the base change it here.
    def vat_of(base_by_rate, base, p, error)
      case error
      when "vat_on_gross_added_to_net" then p[:gross_by_rate].sum(Rational(0)) { |rate, g| cents(g * rate / 100) }
      when "two_rates_single_rate" then cents(base * p[:rates].first / 100)
      when "two_rates_combined" then cents(base * p[:rates].sum(Rational(0)) / 100)
      else base_by_rate.sum(Rational(0)) { |rate, b| cents(b * rate / 100) }
      end
    end

    # The discounts added into one percentage and taken once (the typical error), on each rate's goods.
    def successive_added(p)
      total = p[:percents].sum(Rational(0))
      p[:gross_by_rate].transform_values { |g| g - cents(g * total / 100) }
    end

    def interest_of(net, spec)
      return Rational(0) unless spec

      cents(net * number(spec["rate"]) / 100 * Rational(spec["days"].to_i, (spec["year"] || 360).to_i))
    end
  end
end
