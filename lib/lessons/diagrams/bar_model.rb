# frozen_string_literal: true

module Lessons
  module Diagrams
    # The bar model (T6, WAVE2 2.4): one proportional-bar module with three views. `parts` is R8's bar model (bars of parts, one total, a
    # hidden part is a solution field); `percent` is business's double number line (euro above, percent below, one scale, values computed
    # exactly); `fraction` is reserved (W2-3). The browser twin is app/javascript/lesson/diagrams/chart/bar_model.js; both run
    # test/fixtures/lesson2/bar_model.json.
    module BarModel
      extend Contract

      PERCENT_ONLY = %w[base anchor unit marks hide chain].freeze

      class << self
        def static(data, c)
          case data["view"]
          when "parts"
            forbid(data, c, PERCENT_ONLY + %w[fractions aligned], "the percent and fraction views")
            c.diagram("/bars", "the parts view draws bars", rule: "bars") if data["bars"].nil?
          when "percent"
            forbid(data, c, %w[bars total fractions aligned], "the parts and fraction views")
            if data["base"].nil? == data["anchor"].nil?
              c.diagram("/base", "the percent view has exactly one of base (the value of 100 %) and anchor (one known point)", rule: "base-anchor")
            end
            base = Diagrams.num(data["base"]) if data["base"]
            c.diagram("/base", "base is above 0", rule: "base-positive") if base && !base.positive?
            if (a = data["anchor"])
              pct = Diagrams.num(a["pct"])
              val = Diagrams.num(a["value"])
              c.diagram("/anchor", "anchor.pct is above 0 and anchor.value is above 0", rule: "anchor-positive") unless pct&.positive? && val&.positive?
            end
          end
        end

        def forbid(data, c, keys, where)
          keys.each { |k| c.diagram("/#{k}", "#{k} belongs to #{where}, not to the #{data['view']} view", rule: "forbid-#{k}") if data.key?(k) }
        end

        def state(eff, c, path)
          eff["view"] == "percent" ? percent_state(eff, c, path) : parts_state(eff, c, path)
        end

        def parts_state(eff, c, path)
          total = eff.dig("total", "value") && Diagrams.num(eff.dig("total", "value"))
          c.label("#{path}/total/label_it", eff.dig("total", "label_it")) if eff["total"]
          eff["bars"].to_a.each_with_index do |bar, i|
            at = "#{path}/bars/#{i}"
            c.label("#{at}/label_it", bar["label_it"])
            sum = 0r
            hidden = bar["parts"].to_a.count { |p| p["hidden"] }
            c.diagram("#{at}/parts", "a bar hides at most one part (its value is the rest of the total)", rule: "hidden-many#{at}") if hidden > 1
            c.diagram("#{at}/parts", "a hidden part needs the total: its width is the total less the parts that show", rule: "hidden-total#{at}") if hidden.positive? && total.nil?
            bar["parts"].to_a.each_with_index do |part, j|
              pat = "#{at}/parts/#{j}"
              v = Diagrams.num(part["value"])
              c.diagram("#{pat}/value", "a part is above 0", rule: "part-positive#{pat}") unless v&.positive?
              sum += v if v
              c.role("#{pat}/role", part["role"]) if part["role"]
              c.label("#{pat}/label_it", part["label_it"])
            end
            c.diagram("#{at}/parts", "the parts add up to #{ChartSupport.fmt(sum)}, the total is #{eff['total']['value']}", rule: "sum#{at}") if total && sum != total
          end
        end

        def percent_state(eff, c, path)
          marks = eff["marks"].to_a
          pcts = marks.map { |m| Diagrams.num(m["pct"]) }
          marks.each_with_index do |m, i|
            at = "#{path}/marks/#{i}"
            p = pcts[i]
            c.diagram("#{at}/pct", "a mark lies between 0 and 300 percent", rule: "mark-range#{at}") unless p && p >= 0 && p <= 300
            c.role("#{at}/role", m["role"]) if m["role"]
            c.label("#{at}/label_it", m["label_it"])
          end
          c.diagram("#{path}/marks", "two marks sit at the same percent", rule: "mark-dup#{path}") if pcts.compact.uniq.size != pcts.compact.size
          known = pcts.compact + [ 100r ] + eff["chain"].to_a.filter_map { |s| Diagrams.num(s["pct"]) }
          Array(eff["hide"]).each_with_index do |h, i|
            n = Diagrams.num(h)
            c.diagram("#{path}/hide/#{i}", "#{h} hides no mark: it must be 100, the pct of a mark or the pct of a chain step", rule: "hide#{path}/#{i}") unless n && known.include?(n)
            if eff["anchor"] && n == Diagrams.num(eff.dig("anchor", "pct"))
              c.diagram("#{path}/hide/#{i}", "the anchor is the known point: it cannot be hidden", rule: "hide-anchor#{path}")
            end
          end
          eff["chain"].to_a.each_with_index do |step, i|
            p = Diagrams.num(step["pct"])
            c.diagram("#{path}/chain/#{i}", "a chain step is above 0 and at most 300 percent", rule: "chain#{path}/#{i}") unless p&.positive? && p <= 300
          end
        end

        # ---- the computed values (the twin of chart/bar_model.js percentValues) --------------------------------------------

        # The value of 100 %: base, or the anchor's value scaled back.
        def hundred(eff)
          return Diagrams.num(eff["base"]) if eff["base"]

          a = eff["anchor"] or return nil
          Diagrams.num(a["value"]) * 100 / Diagrams.num(a["pct"])
        end

        def money(x, unit) = unit == "euro" ? ChartSupport.fmt(x, 2) : (ChartSupport.places_of(x) > 2 ? ChartSupport.fmt(x, 2) : ChartSupport.fmt(x))

        # { "values" => { "100" => "1860,00", "22" => nil, ... }, "chain_values" => [{ "from" =>, "to" => }] } with nil for a hidden value.
        def percent_values(eff)
          base = hundred(eff) or return {}
          hide = Array(eff["hide"]).filter_map { |h| Diagrams.num(h) }
          unit = eff["unit"] || "euro"
          shown = ([ 100r ] + eff["marks"].to_a.filter_map { |m| Diagrams.num(m["pct"]) } + (eff["anchor"] ? [ Diagrams.num(eff.dig("anchor", "pct")) ] : [])).uniq.sort
          values = shown.to_h { |p| [ ChartSupport.fmt(p), hide.include?(p) ? nil : money(base * p / 100, unit) ] }
          out = { "values" => values }
          chain = eff["chain"].to_a
          unless chain.empty?
            from = base
            cut = hide.include?(100r)
            out["chain_values"] = chain.map do |step|
              p = Diagrams.num(step["pct"])
              to = from * p / 100
              row = { "from" => cut ? nil : money(from, unit) }
              cut ||= hide.include?(p)
              row["to"] = cut ? nil : money(to, unit)
              from = to
              row
            end
          end
          out
        end

        # ---- served, targets, printed ---------------------------------------------------------------------------------------

        def hide_parts(bars) = bars.to_a.map { |b| b.merge("parts" => b["parts"].map { |p| p["hidden"] ? p.merge("value" => nil) : p }) }

        def served(data, mode: :student)
          merged = Diagrams.merge_states(data)
          out = Lessons::StudentBody.diagram_generic(data)
          if mode == :student || mode == :select
            out["bars"] = hide_parts(out["bars"]) if out["bars"]
            out["base"] = nil if out["base"] && Array(data["hide"]).any? { |h| Diagrams.num(h) == 100r }
            out.delete("base") if out.key?("base") && out["base"].nil?
          end
          out.merge!(percent_values(merged.except("states"))) if merged["view"] == "percent"
          if out["states"]
            out["states"] = out["states"].each_with_index.map do |s, i|
              eff = merged["states"][i]
              s = s.merge("bars" => hide_parts(s["bars"])) if s["bars"]
              eff["view"] == "percent" ? s.merge(percent_values(eff)) : s
            end
          end
          out.compact
        end

        def effective(data, state)
          eff = Diagrams.effective_states(data)
          eff.empty? ? data : eff.fetch([ state.to_i, eff.size - 1 ].min)
        end

        def sorted_marks(eff) = eff["marks"].to_a.each_with_index.sort_by { |m, i| [ Diagrams.num(m["pct"]), i ] }.map(&:first)

        def targets(data, set)
          eff = effective(data, 0)
          case set.to_s
          when "parts" then eff["bars"].to_a.each_with_index.flat_map { |b, i| b["parts"].each_index.map { |j| "b#{i + 1}p#{j + 1}" } }
          when "marks" then sorted_marks(eff).each_index.map { |k| "m#{k + 1}" }
          else raise ArgumentError, "bar_model has no select set #{set.inspect}"
          end
        end

        # Every number the state prints, hidden ones excluded: the visible parts and the total, or the percents and their values.
        def printed(data, state)
          eff = effective(data, state)
          out = []
          if eff["view"] == "percent"
            pv = percent_values(eff)
            out.concat(pv.fetch("values", {}).flat_map { |p, v| [ p, v ] })
            out.concat(pv.fetch("chain_values", []).flat_map { |r| [ r["from"], r["to"] ] })
            out.concat(eff["chain"].to_a.map { |s| s["pct"] })
          else
            out.concat(eff["bars"].to_a.flat_map { |b| b["parts"].reject { |p| p["hidden"] }.map { |p| p["value"] } })
            out << eff.dig("total", "value")
          end
          ChartSupport.numbers(out.compact.map { |s| s.to_s.delete(".") })
        end
      end
    end
  end
end
