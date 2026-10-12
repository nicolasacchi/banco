# frozen_string_literal: true

module Lessons
  # Money: Exact euro amounts (Rational), half-up cents, VAT per rate and invoice rows.
  # Contract stub of W2-0 (WAVE2 1.10, batch w2-1, track T8): the signatures below are frozen; the bodies are the track's. The JS twin is
  # app/javascript/lesson/lib/money.js and both run test/fixtures/lesson2/money.json (like Lessons::Num and lesson/num.js).
  module Money
    NotBuilt = Class.new(NotImplementedError)
    # name => signature (Ruby)
    SIGNATURES = {
      "round_half_up" => "round_half_up(amount)",
      "vat" => "vat(net, rate)",
      "row" => "row(qty, price)",
      "invoice" => "invoice(spec)"
    }.freeze

    module_function

    # An amount rounded to cents, half up.
    def round_half_up(amount)
      raise NotBuilt, "Lessons::Money.round_half_up is not built yet (T8, w2-1)"
    end

    # The VAT of an amount at a rate in percent, rounded half up.
    def vat(net, rate)
      raise NotBuilt, "Lessons::Money.vat is not built yet (T8, w2-1)"
    end

    # One invoice row: quantity times price.
    def row(qty, price)
      raise NotBuilt, "Lessons::Money.row is not built yet (T8, w2-1)"
    end

    # All rows of an invoice from its data; ERROR_VARIANTS is the closed list of typical errors.
    def invoice(spec)
      raise NotBuilt, "Lessons::Money.invoice is not built yet (T8, w2-1)"
    end
  end
end
