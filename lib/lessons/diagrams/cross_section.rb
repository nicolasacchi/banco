# frozen_string_literal: true

module Lessons
  module Diagrams
    # cross_section (T5, W2-1, D-275): a section of the ground, `points` [[x, altitude in m]] exact, features, belts of altitude, and with
    # `lapse` the temperature at each belt edge and under the altitude stepper, computed (base_temp - per_km * altitude / 1000). The
    # vertical exaggeration is computed from the data (the largest "nice" number that keeps the drawing about half as high as wide) and always
    # printed: "altezze esagerate 15 volte". Browser twin: lesson/diagrams/maps/cross_section.js. Select targets: `belts` (stored "alt:FROM:TO",
    # highest first).
    module CrossSection
      extend Contract

      GF = GeoFormat
      ASPECT = 0.5
      NICE = [ 1, 2, 3, 4, 5, 6, 8, 10, 12, 15, 20, 25, 30, 40, 50, 60, 80, 100, 120, 150, 200, 250, 300, 400, 500, 600, 800, 1000, 1500, 2000, 2500, 3000, 5000, 10_000 ].freeze
      ALT_RANGE = (-12_000..9000)
      KINDS = { "peak" => "cima", "city" => "città", "river" => "fiume", "sea" => "mare", "plain" => "pianura", "plateau" => "altopiano" }.freeze

      module_function

      def n(text) = Diagrams.num(text)

      # [[x Rational, alt Rational]] of the points; nil when one is not a number.
      def pts(data) = data["points"].to_a.map { |x, a| [ n(x), n(a) ] }

      def x_to(data) = n(data.dig("x", "to"))

      def x_metres(data) = (t = x_to(data)) && t * (data.dig("x", "unit") == "km" ? 1000 : 1)

      def top(data) = pts(data).map(&:last).compact.max

      def bottom(data) = [ pts(data).map(&:last).compact.min || 0, 0 ].min

      # The vertical exaggeration: a whole number from NICE, at least 1.
      def exaggeration(data)
        xm = x_metres(data)
        span = top(data) - bottom(data)
        return 1 unless xm&.positive? && span.positive?

        raw = ASPECT * xm / span
        NICE.select { |v| v <= raw }.max || 1
      end

      # The drawn height over the drawn width: exaggeration * span / x.
      def aspect(data) = (exaggeration(data) * (top(data) - bottom(data)) / x_metres(data)).to_f

      def exaggeration_text(data)
        e = exaggeration(data)
        e == 1 ? "altezze in scala" : "altezze esagerate #{e} volte"
      end

      def temp(data, alt)
        l = data["lapse"] or return nil
        n(l["base_temp"]) - n(l["per_km"]) * alt / 1000
      end

      def temp_str(data, alt) = (t = temp(data, alt)) && "#{GF.fmt1(t, trim: true)} °C"

      # The altitudes of the stepper: every 500 m up to 4000 m of height, every 1000 m above, from 0, and the top.
      def stepper_values(data)
        t = top(data)
        step = t <= 4000 ? 500 : 1000
        vals = (0..t.floor).step(step).to_a
        vals << t.to_i unless vals.include?(t.to_i)
        vals.select { |v| v >= 0 }.map { |v| Rational(v) }
      end

      def alt_of(data, controls)
        vals = stepper_values(data)
        want = controls && controls["alt"] ? Rational(controls["alt"].to_i) : Rational(0)
        vals.include?(want) ? want : (vals.min_by { |v| (v - want).abs } || Rational(0))
      end

      def effective(data, state)
        top = data.reject { |k, _| k == "states" }
        sts = data["states"].is_a?(Array) && data["states"].any? ? data["states"] : nil
        sts ? top.merge(sts[[ state, sts.size - 1 ].min]) : top
      end

      def static(data, c)
        xt = x_to(data)
        c.diagram("/x/to", "x goes from 0 to a positive length", rule: "x-to") unless xt&.positive?
        ps = pts(data)
        if ps.any? { |x, a| x.nil? || a.nil? }
          c.diagram("/points", "every point is [x, altitude] with exact numbers", rule: "points")
          return
        end
        xs = ps.map(&:first)
        c.diagram("/points", "the points go from the left edge (x = 0) to the right edge (x = #{data.dig('x', 'to')}), x always increasing", rule: "points-x") unless xs.first.zero? && xt && xs.last == xt && xs.each_cons(2).all? { |a, b| a < b }
        ps.each_with_index do |(_, a), i|
          c.diagram("/points/#{i}", "an altitude is between #{ALT_RANGE.begin} and #{ALT_RANGE.end} m", rule: "alt#{i}") unless ALT_RANGE.cover?(a)
        end
        c.diagram("/points", "the highest point must be above the lowest (a flat section has nothing to show)", rule: "flat") if top(data) <= bottom(data)
        if xt&.positive? && top(data) > bottom(data) && (top(data) - bottom(data)) / x_metres(data) > 1
          c.diagram("/points", "the section is too steep to draw to scale (more than 45 degrees on average): lengthen x or lower the peaks", rule: "steep")
        end
        data["features"].to_a.each_with_index do |f, i|
          at = "/features/#{i}"
          v = n(f["at"])
          c.diagram("#{at}/at", "a feature lies between 0 and #{data.dig('x', 'to')}", rule: "feature#{i}") unless v && xt && v >= 0 && v <= xt
          c.label("#{at}/label_it", f["label_it"])
        end
        l = data["lapse"]
        if l
          c.diagram("/lapse/per_km", "per_km is above 0 (degrees lost every 1000 m)", rule: "lapse") unless (p = n(l["per_km"])) && p.positive?
          c.diagram("/lapse/base_temp", "base_temp is a number", rule: "lapse-base") unless n(l["base_temp"])
        end
        c.diagram("/stepper", "the altitude stepper needs lapse (the temperature it reads)", rule: "stepper-lapse") if data["stepper"] && !l
        belts(data, c, "", data["belts"].to_a)
        data["states"].to_a.each_with_index { |s, i| belts(data, c, "/states/#{i}", s["belts"].to_a) if s.is_a?(Hash) && s.key?("belts") }
      end

      def belts(data, c, path, list)
        lo = bottom(data)
        hi = top(data)
        parsed = list.each_with_index.map do |b, i|
          at = "#{path}/belts/#{i}"
          a = n(b["from_alt"])
          z = n(b["to_alt"])
          c.diagram(at, "a belt goes from a lower to a higher altitude, inside the section (#{lo.to_i} to #{hi.to_i} m)", rule: "belt#{at}") unless a && z && a < z && a >= lo && z <= hi
          c.role("#{at}/role", b["role"]) if b["role"]
          c.label("#{at}/label_it", b["label_it"])
          [ a, z ]
        end
        valid = parsed.select { |a, z| a && z }
        valid.sort.each_cons(2) do |(_, z1), (a2, _)|
          c.diagram("#{path}/belts", "two belts overlap", rule: "belt-overlap#{path}") if a2 < z1
        end
      end

      def state(_eff, _c, _path) = nil

      def belts_of(data, eff) = eff["belts"].to_a.reject { |b| n(b["from_alt"]).nil? }

      def describe(data, state: 0, controls: nil, mode: "student")
        eff = effective(data, state)
        u = data.dig("x", "unit")
        return "Una sezione del terreno lunga #{GF.fmt(x_to(data))} #{u}, con #{eff['belts'].to_a.size} fasce da toccare. #{exaggeration_text(data)}." if mode == "select"

        out = [ "Sezione del terreno, lunga #{GF.fmt(x_to(data))} #{u}. La quota va da #{GF.fmt(bottom(data))} a #{GF.fmt(top(data))} m. #{GF.capital(exaggeration_text(data))}." ]
        data["features"].to_a.each { |f| out << "#{GF.capital(f['label_it'])}, a #{GF.fmt(n(f['at']))} #{u}." }
        eff["belts"].to_a.each do |b|
          a = n(b["from_alt"])
          z = n(b["to_alt"])
          t = data["lapse"] ? " (da #{temp_str(data, a)} a #{temp_str(data, z)})" : ""
          out << "Fascia #{b['label_it']}: da #{GF.fmt(a)} a #{GF.fmt(z)} m#{t}."
        end
        if data["lapse"]
          out << "Con la quota la temperatura scende di #{GF.fmt(n(data['lapse']['per_km']))} °C ogni 1000 m."
          out << "A #{GF.fmt(alt_of(data, controls))} m: #{temp_str(data, alt_of(data, controls))}." if data["stepper"]
        end
        out << "#{eff['op_it']}." if eff["op_it"]
        out.join(" ")
      end

      def printed(data, state = 0)
        eff = effective(data, state)
        out = [ describe(data, state: state), exaggeration_text(data) ]
        out.concat(data["features"].to_a.map { |f| f["label_it"] })
        eff["belts"].to_a.each do |b|
          out << b["label_it"]
          next unless data["lapse"]

          out << temp_str(data, n(b["from_alt"])) << temp_str(data, n(b["to_alt"]))
        end
        out << eff["op_it"] if eff["op_it"]
        out << data["caption_it"] if data["caption_it"]
        out.compact.uniq
      end

      # What the altitude stepper can show: each altitude and the temperature at it.
      def reachable(data)
        return [] unless data["stepper"] && data["lapse"]

        out = stepper_values(data).flat_map { |a| [ "#{GF.fmt(a)} m", temp_str(data, a) ] }.uniq
        out.size > Contract::REACHABLE_CAP ? :over_cap : out
      end

      def served(data, mode: :student, **)
        return StudentBody.diagram(data) unless mode.to_sym == :select

        eff = effective(data, 0)
        out = data.slice("type", "alt_it", "caption_it", "size", "x", "points")
        # the schema wants a label: every belt gets the same neutral word, which the select figure never draws
        out["belts"] = eff["belts"].to_a.map { |b| b.slice("from_alt", "to_alt").merge("label_it" => "fascia") }
        out
      end

      # The belts, highest first: [{ "id" => "alt:FROM:TO", "from" => Rational }].
      def ordered(data)
        eff = effective(data, 0)
        eff["belts"].to_a.map { |b| { "id" => "alt:#{b['from_alt']}:#{b['to_alt']}", "from" => n(b["from_alt"]) } }.sort_by { |b| [ -b["from"], b["id"] ] }
      end

      def targets(data, set)
        raise ArgumentError, "cross_section has only the target set belts (got #{set.inspect})" unless set.to_s == "belts"

        ordered(data).map { |b| b["id"] }
      end

      def neutral(data, _set = "belts")
        k = ordered(data).size
        (1..k).map { |i| "fascia #{i} di #{k}, contando dall'alto" }
      end
    end
  end
end
