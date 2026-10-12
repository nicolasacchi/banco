# frozen_string_literal: true

module Lessons
  module Diagrams
    # document (WAVE2 2.7, track T8): one type, a registry of kinds, each a template of fixed zones our code draws. W2-1 builds the frame and the
    # `invoice` kind (the other kinds are W2-2 drafts the registry holds back). The rows of an invoice are computed by Lessons::Money, never
    # written by the agent; the figure is drawn as the typical error computes it when `error` names one.
    #
    # The checks here are those the schema cannot make: at least one goods line, the VAT rates of the programme, quantities and prices that are
    # amounts, discounts under 100, rows, marks and hidden rows that are rows, a cascade without hidden rows (its bars would show the value),
    # a date that exists, an error that really changes the total, and every euro amount in alt_it or caption_it being a row the drawing computes
    # (E-LESSON-ALT), so neither the drawing nor its text can lie, and no hidden row's amount being written in the text.
    module Document
      extend Contract

      KINDS_BUILT = %w[invoice].freeze
      ROWS = Money::ROWS
      ZONES = %w[seller buyer number date lines costs].freeze
      AMOUNT = /\d{1,3}(?:\.\d{3})*,\d{2}|\d+,\d{2}/

      module_function

      # ---- the checks ---------------------------------------------------------------------------------------

      def static(data, c)
        return unless invoice?(data)

        caps(data, c)
        lines(data, c)
        c.diagram("/view", "a cascade has no hidden rows: its bars would show the value", rule: "cascade-hide") if data["view"] == "cascade" && hidden_anywhere(data).any?
        head(data, c)
        interest(data, c)
        error(data, c)
        alt_amounts(data, c)
      end

      def state(eff, c, path)
        return unless invoice?(eff)

        %w[rows hide mark].each do |key|
          Array(eff[key]).each_with_index do |id, i|
            c.diagram("#{path}/#{key}/#{i}", "#{id} is not a row of an invoice (#{ROWS.join(', ')})", rule: "row-#{key}#{path}-#{i}") unless ROWS.include?(id)
          end
        end
      end

      def invoice?(data) = data["kind"] == "invoice"

      def caps(data, c)
        max = Validation::Rules.get(:lesson2, :types, :document)
        c.diagram("/lines", "an invoice has at most #{max['lines']} lines", rule: "lines-cap") if Array(data["lines"]).size > max["lines"]
        c.diagram("/discounts", "an invoice has at most #{max['discounts']} discounts", rule: "discounts-cap") if Array(data["discounts"]).size > max["discounts"]
        c.diagram("/costs", "an invoice has at most #{max['costs']} costs", rule: "costs-cap") if Array(data["costs"]).size > max["costs"]
      end

      def lines(data, c)
        lines = Array(data["lines"])
        c.diagram("/lines", "an invoice has at least one goods line", rule: "lines-empty") if lines.empty?
        lines.each_with_index do |l, i|
          c.diagram("/lines/#{i}/vat", "the VAT rate #{l['vat']} is not one of the programme (#{Money::RATES.join(', ')})", rule: "rate-#{i}") unless Money::RATES.include?(l["vat"])
          positive(l["qty"], "/lines/#{i}/qty", c, "a quantity")
          positive(l["price"], "/lines/#{i}/price", c, "a price")
          c.label("/lines/#{i}/text_it", l["text_it"])
        end
        Array(data["discounts"]).each_with_index do |d, i|
          v = Num.parse(d)
          c.diagram("/discounts/#{i}", "a discount is a percentage over 0 and under 100", rule: "discount-#{i}") unless v && v.positive? && v < 100
        end
        Array(data["costs"]).each_with_index do |k, i|
          v = Num.parse(k["amount"])
          c.diagram("/costs/#{i}/amount", "a cost is an amount over 0", rule: "cost-#{i}") unless v && v.positive?
          c.label("/costs/#{i}/text_it", k["text_it"])
        end
        rates = lines.map { |l| l["vat"] }.uniq
        if rates.size > 1 && Array(data["costs"]).any? { |k| !k["documented"] }
          c.diagram("/costs", "with two VAT rates a cost that is not documented has no rate: mark it documented, or use one rate", rule: "costs-two-rates")
        end
      end

      def positive(text, path, c, what)
        v = Num.parse(text)
        c.diagram(path, "#{what} is a number over 0", rule: path) unless v && v.positive?
      end

      def head(data, c)
        date = data.dig("head", "date")
        return unless date

        Date.iso8601(date)
      rescue Date::Error
        c.diagram("/head/date", "#{date} is not a date that exists", rule: "date")
      end

      def interest(data, c)
        i = data["interest"] or return
        v = Num.parse(i["rate"])
        c.diagram("/interest/rate", "the interest rate is a percentage over 0", rule: "interest-rate") unless v && v.positive?
      end

      # An error that Money cannot compute, or that changes nothing, is refused.
      def error(data, c)
        spec = data.slice("lines", "discounts", "costs", "interest")
        return if c.findings.any? { |f| f.path.start_with?("/lines", "/discounts", "/costs", "/interest") }

        right = Money.invoice(spec)
        return unless data["error"]

        c.diagram("/error", "#{data['error']} is not an invoice error (#{Money::ERROR_VARIANTS.join(', ')})", rule: "error-name") unless Money::ERROR_VARIANTS.include?(data["error"])
        wrong = Money.invoice(spec.merge("error" => data["error"]))
        c.diagram("/error", "#{data['error']} changes nothing on this invoice: pick a mistake the invoice can make", rule: "error-same") if wrong["rows"] == right["rows"]
      rescue Money::Refused => e
        c.diagram("/error", e.message, rule: "money")
      end

      # Every euro amount of alt_it and caption_it is a row or a line the figure computes, or an amount written in the data (a price, a cost).
      def alt_amounts(data, c)
        computed = computed_amounts(data) or return
        hidden = hidden_values(data)
        %w[alt_it caption_it].each do |key|
          data[key].to_s.scan(AMOUNT).each do |text|
            plain = text.delete(".")
            if hidden.include?(plain)
              c.add("E-LESSON-ALT", "/#{key}", "#{text} is the amount of a hidden row: the text must not say it", rule: "alt-hidden-#{key}-#{plain}")
            elsif !computed.include?(plain)
              c.add("E-LESSON-ALT", "/#{key}", "#{text} is not an amount of the invoice (the rows are computed by our code: write only amounts the figure draws)", rule: "alt-amount-#{key}-#{plain}")
            end
          end
        end
      end

      def computed_amounts(data)
        spec = data.slice("lines", "discounts", "costs", "interest", "error")
        out = Money.invoice(spec)
        set = out["rows"].values + out["lines"]
        set += Array(data["lines"]).flat_map { |l| [ l["price"] ] }.select { |p| p.to_s.include?(",") }
        set += Array(data["costs"]).map { |k| k["amount"] }
        set.map { |s| s.to_s.delete(".") }.to_set
      rescue Money::Refused
        nil
      end

      # The amounts of the rows hidden in the top level or in any state.
      def hidden_values(data)
        rows = Money.invoice(data.slice("lines", "discounts", "costs", "interest", "error"))["rows"]
        hidden_anywhere(data).filter_map { |id| rows[id] }.map { |s| s.delete(".") }.to_set
      rescue Money::Refused
        Set.new
      end

      def hidden_anywhere(data) = (Array(data["hide"]) + Array(data["states"]).flat_map { |s| Array(s["hide"]) }).uniq

      # The rows a state draws: its own list, else the rows that matter for this invoice (WAVE2 2.7).
      def shown_rows(eff)
        return eff["rows"] if eff["rows"]

        costs = Array(eff["costs"])
        ROWS.select do |id|
          case id
          when "discounts" then Array(eff["discounts"]).any?
          when "costs_in" then costs.any? { |k| !k["documented"] }
          when "costs_out" then costs.any? { |k| k["documented"] }
          when "interest" then eff["interest"] ? true : false
          else true
          end
        end
      end

      # ---- served, targets, printed ----------------------------------------------------------------------------

      # The whitelist projection (L1, L2): the drawing's fields. The rows are derived (our code computes them in the browser from these
      # inputs); nothing here is a solution field, and hidden rows are only a list of names.
      def served(data, mode: :student)
        Lessons::StudentBody.diagram_generic(data)
      end

      # The stored ids of select set +set+ in reading order (the order lesson/diagrams/docs/document.js targets() returns): the zones the
      # sheet has, or the rows it draws in its first state.
      def targets(data, set)
        eff = Diagrams.effective_states(data).first || data
        case set.to_s
        when "zones" then zones(eff)
        when "rows" then shown_rows(eff)
        else raise ArgumentError, "document has no select set #{set.inspect} (zones, rows)"
        end
      end

      def zones(eff)
        head = eff["head"] || {}
        out = []
        out << "seller" if head["seller_it"]
        out << "buyer" if head["buyer_it"]
        out << "number" if head["number"]
        out << "date" if head["date"]
        out << "lines"
        out << "costs" if Array(eff["costs"]).any?
        out
      end

      # Every string the state prints (L4): the title, the head, the lines with their computed amounts, the rows that are not hidden.
      def printed(data, state)
        eff = Diagrams.effective_states(data)[state.to_i] || data
        out = [ data["alt_it"], data["caption_it"], eff["op_it"] ].compact
        head = eff["head"] || {}
        out += head.values_at("seller_it", "buyer_it", "number", "date").compact
        spec = eff.slice("lines", "discounts", "costs", "interest", "error")
        result = Money.invoice(spec)
        Array(eff["lines"]).each_with_index { |l, i| out += [ l["text_it"], l["qty"], l["price"], l["vat"], result["lines"][i] ] }
        Array(eff["costs"]).each { |k| out += [ k["text_it"], k["amount"] ] }
        hidden = Array(eff["hide"])
        shown_rows(eff).each { |id| out << result["rows"][id] unless hidden.include?(id) }
        out.compact.map(&:to_s)
      end

      def reachable(_data) = []

      def verify_functions
        { "money.row" => ->(args) { Money.row(args["qty"], args["price"]) } }
      end
    end
  end
end
