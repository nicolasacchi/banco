# frozen_string_literal: true

module Lessons
  module Diagrams
    # timeline (WAVE2 2.2, T4a): one time axis, two scales. `years` is history's line of dated events (signed years, a.C. next to d.C. with
    # no year 0, periods, events, lanes, spans whose duration Chrono computes, centuries, zoom as states); `tense` is the order of English
    # and Spanish tenses around "adesso" (points, ranges, habits, plans). The browser twin is lesson/diagrams/time/timeline.js; both run
    # test/fixtures/diagrams/types/timeline.json. The words are those of config/locales/lesson_time.it.yml (key `scene`).
    module Timeline
      extend Contract

      YEAR_KEYS = %w[from to every centuries lanes periods events spans measure].freeze
      TENSE_KEYS = %w[window marks].freeze
      LANG_OF = { "text_en" => "english", "text_es" => "spanish" }.freeze

      class << self
        def caps = Validation::Rules.get(:lesson2, :types, :timeline)

        def text(key, **vars)
          I18n.t("lesson_time.scene.#{key}", **vars)
        end

        # ---- years ------------------------------------------------------------------------------------

        def year_label(year)
          y = Chrono.year(year)
          "#{y.abs} #{text(y.negative? ? 'era_bc' : 'era_ad')}"
        end

        def event_year_label(event) = event["approx"] ? "#{text('about')} #{year_label(event['at'])}" : year_label(event["at"])

        def duration_text(n)
          n = n.abs
          "#{n} #{text(n == 1 ? 'year_one' : 'year_many')}"
        end

        # The ticks of a step: the years that are multiples of +every+ inside from..to, never the year 0.
        def ticks(from, to, every)
          a = Chrono.year(from)
          b = Chrono.year(to)
          first = (a.to_f / every).ceil * every
          (first..b).step(every).reject(&:zero?).select { |y| y >= a }
        end

        # The centuries the line passes through, in order: the boundaries lie half a year before 100 k on the axis of Chrono.position.
        def centuries(from, to)
          t0 = Chrono.position(from)
          t1 = Chrono.position(to)
          (((t0 + 0.5) / 100).floor).upto(((t1 + 0.5) / 100).floor).filter_map do |k|
            lo = [ 100 * k - 0.5, t0 ].max
            hi = [ 100 * (k + 1) - 0.5, t1 ].min
            next if hi <= lo

            p = lo.ceil
            Chrono.century(p >= 0 ? p + 1 : p)
          end
        end

        def effective(data, state)
          eff = Diagrams.effective_states(data)
          eff.empty? ? data : eff.fetch([ state, eff.size - 1 ].min)
        end

        def static(data, c)
          years = data["scale"] == "years"
          other = years ? TENSE_KEYS : YEAR_KEYS
          other.each { |k| c.diagram("/#{k}", "a #{data['scale']} timeline has no #{k}", rule: "scale-#{k}") if data.key?(k) }
          Array(data["states"]).each_with_index do |s, i|
            (years ? TENSE_KEYS : %w[from to periods events spans]).each { |k| c.diagram("/states/#{i}/#{k}", "a #{data['scale']} timeline has no #{k}", rule: "scale-state-#{i}-#{k}") if s.key?(k) }
          end
          return unless years

          ids = Array(data["lanes"]).map { |l| l["id"] }
          c.diagram("/lanes", "two lanes have the same id", rule: "lane-ids") if ids.uniq.size != ids.size
          c.diagram("/measure", "measure needs at least two events", rule: "measure") if data["measure"] && ([ data ] + Diagrams.effective_states(data)).map { |e| Array(e["events"]).size }.max.to_i < 2
          if data["every"]
            ([ data ] + Diagrams.effective_states(data)).each do |e|
              next unless e["from"] && e["to"] && Chrono.duration(e["from"], e["to"]).positive?

              n = ticks(e["from"], e["to"], data["every"]).size
              c.diagram("/every", "a step of #{data['every']} years gives #{n} ticks (at most #{caps['ticks']})", rule: "ticks") if n > caps["ticks"]
            end
          end
        end

        def state(eff, c, path)
          eff["scale"] == "years" ? years_state(eff, c, path) : tense_state(eff, c, path)
        end

        def years_state(eff, c, path)
          from = eff["from"]
          to = eff["to"]
          return unless from && to

          unless Chrono.duration(from, to).positive?
            c.diagram("#{path}/to", "the range goes from an earlier year to a later one", rule: "range#{path}")
            return
          end
          lanes = Array(eff["lanes"]).map { |l| l["id"] }
          events = Array(eff["events"])
          ids = events.map { |e| e["id"] }
          c.map("#{path}/events", "event ids must be unique", rule: "event-ids#{path}") if ids.uniq.size != ids.size
          events.each_with_index do |e, i|
            at = "#{path}/events/#{i}"
            c.diagram("#{at}/at", "the event is outside the years of the line", rule: "event-in#{path}/#{i}") unless inside?(e["at"], from, to)
            words = Diagrams.label_words(e["label_it"])
            c.diagram("#{at}/label_it", "an event label has #{words} words (at most #{caps['label_words']})", rule: "event-words#{path}/#{i}") if words > caps["label_words"]
            nw = Diagrams.label_words(e["note_it"])
            c.diagram("#{at}/note_it", "a note has #{nw} words (at most #{caps['note_words']})", rule: "note-words#{path}/#{i}") if nw > caps["note_words"]
            c.role("#{at}/role", e["role"]) if e["role"]
            if lanes.empty?
              c.diagram("#{at}/lane", "the event names a lane but the line has none", rule: "lane-none#{path}/#{i}") if e["lane"]
            elsif e["lane"].nil?
              c.diagram("#{at}/lane", "with lanes, every event names its lane", rule: "lane-missing#{path}/#{i}")
            elsif !lanes.include?(e["lane"])
              c.map("#{at}/lane", "the event names a lane that does not exist", rule: "lane-unknown#{path}/#{i}")
            end
          end
          Array(eff["periods"]).each_with_index do |p, i|
            at = "#{path}/periods/#{i}"
            if Chrono.duration(p["from"], p["to"]) <= 0
              c.diagram("#{at}/to", "a period goes from an earlier year to a later one", rule: "period-order#{path}/#{i}")
            elsif Chrono.duration(p["to"], from).positive? || Chrono.duration(to, p["from"]).positive?
              c.diagram("#{at}", "the period is entirely outside the years of the line", rule: "period-in#{path}/#{i}")
            end
            c.role("#{at}/role", p["role"]) if p["role"]
            c.label("#{at}/label_it", p["label_it"])
          end
          Array(eff["lanes"]).each_with_index { |l, i| c.label("#{path}/lanes/#{i}/label_it", l["label_it"]) }
          seen = []
          Array(eff["spans"]).each_with_index do |s, i|
            at = "#{path}/spans/#{i}"
            a = events.find { |e| e["id"] == s["from"] }
            b = events.find { |e| e["id"] == s["to"] }
            unless a && b
              c.map(at, "the span names an event that is not in this state", rule: "span-event#{path}/#{i}")
              next
            end
            c.diagram("#{at}/to", "a span goes from an earlier event to a later one", rule: "span-order#{path}/#{i}") unless Chrono.duration(a["at"], b["at"]).positive?
            c.map(at, "the same span is written twice", rule: "span-twice#{path}/#{i}") if seen.include?([ s["from"], s["to"] ])
            seen << [ s["from"], s["to"] ]
          end
        end

        def inside?(year, from, to) = Chrono.duration(from, year) >= 0 && Chrono.duration(year, to) >= 0

        # ---- tense ------------------------------------------------------------------------------------

        def tense_state(eff, c, path)
          window = eff["window"] or return
          lo, hi = window.map(&:to_i)
          c.diagram("#{path}/window", "the window goes from a smaller number to a larger one and contains 0 (now)", rule: "window#{path}") unless lo < hi && lo <= 0 && hi >= 0
          marks = Array(eff["marks"])
          ids = marks.map { |m| m["id"] }
          c.map("#{path}/marks", "mark ids must be unique", rule: "mark-ids#{path}") if ids.uniq.size != ids.size
          marks.each_with_index do |m, i|
            at = "#{path}/marks/#{i}"
            spoken = LANG_OF.keys.select { |k| m[k] }
            if spoken.size != 1
              c.diagram(at, "a mark says its sentence in one language: text_en or text_es", rule: "mark-text#{path}/#{i}")
            elsif c.subject != LANG_OF[spoken.first]
              c.diagram("#{at}/#{spoken.first}", "#{spoken.first} is for #{LANG_OF[spoken.first]} lessons", rule: "mark-lang#{path}/#{i}")
            else
              n = Diagrams.label_words(m[spoken.first])
              c.add("E-READ", "#{at}/#{spoken.first}", "a mark has #{n} words (at most #{caps['tense_mark_words']})", rule: "tense-words#{path}/#{i}") if n > caps["tense_mark_words"]
            end
            c.label("#{at}/label_it", m["label_it"])
            c.role("#{at}/role", m["role"]) if m["role"]
            span = m["span"]
            want = { "point" => [], "range" => %w[to], "habit" => [], "plan" => %w[from] }.fetch(span)
            allowed = want + (span == "habit" ? %w[to] : [])
            (%w[to from] - allowed).each { |k| c.diagram("#{at}/#{k}", "a #{span} mark has no #{k}", rule: "mark-#{k}#{path}/#{i}") if m[k] }
            want.each { |k| c.diagram("#{at}/#{k}", "a #{span} mark needs #{k}", rule: "mark-need-#{k}#{path}/#{i}") if m[k].nil? }
            { "at" => m["at"], "to" => m["to"], "from" => m["from"] }.each do |k, v|
              c.diagram("#{at}/#{k}", "#{k} is outside the window", rule: "mark-in-#{k}#{path}/#{i}") if v && !(lo..hi).cover?(v.to_i)
            end
            c.diagram("#{at}/to", "a range or a habit goes from a smaller number to a larger one", rule: "mark-order#{path}/#{i}") if m["to"] && m["to"].to_i <= m["at"].to_i
            c.diagram("#{at}/from", "a plan is made before it happens: from is smaller than at", rule: "plan-order#{path}/#{i}") if m["from"] && m["from"].to_i >= m["at"].to_i
          end
        end

        # ---- what the browser is told -------------------------------------------------------------------

        def served(data, mode: :student, set: nil)
          return StudentBody.diagram_generic(data) unless mode == :select

          count = set ? targets(data, set).size : selectable(data).size
          out = { "type" => "timeline", "alt_it" => "Una linea con #{[ count, 1 ].max} punti da scegliere.", "scale" => data["scale"] }
          if data["scale"] == "years"
            out.merge!("from" => data["from"], "to" => data["to"])
            out["events"] = Array(data["events"]).map { |e| e.slice("id", "at").merge("label_it" => "·") }
            out["periods"] = Array(data["periods"]).map { |p| p.slice("from", "to").merge("label_it" => "·") }
          else
            out.merge!("window" => data["window"])
            out["marks"] = Array(data["marks"]).map { |m| m.slice("id", "at", "to", "from", "span").merge((m.key?("text_es") ? "text_es" : "text_en") => "·") }
          end
          out
        end

        def selectable(data) = Array(data["events"]) + Array(data["periods"]) + Array(data["marks"])

        def targets(data, set)
          case set.to_s
          when "events" then Array(data["events"]).map { |e| e["id"] }
          when "periods" then Array(data["periods"]).each_index.map { |i| "p#{i + 1}" }
          when "marks" then Array(data["marks"]).map { |m| m["id"] }
          else raise ArgumentError, "timeline has no select set #{set.inspect}"
          end
        end

        def target_names(data, set)
          case set.to_s
          when "events" then Array(data["events"]).to_h { |e| [ e["id"], plain(e["label_it"]) ] }
          when "periods" then Array(data["periods"]).each_with_index.to_h { |p, i| [ "p#{i + 1}", plain(p["label_it"]) ] }
          when "marks" then Array(data["marks"]).to_h { |m| [ m["id"], plain(m["text_en"] || m["text_es"]) ] }
          else {}
          end
        end

        # ---- what a state prints ------------------------------------------------------------------------

        def plain(t) = t.to_s.gsub(/\\role\{[a-z-]+\}\{([^{}]*)\}/, '\1').delete("$")

        # A label of the neutral select form ("·") is told as a point.
        def name_of(t) = plain(t) == "·" ? text("neutral_point") : plain(t)

        def list_it(items) = items.size <= 1 ? items.join : "#{items[0..-2].join(', ')} e #{items.last}"

        def rel(v)
          n = v.to_i
          text(n.negative? ? "rel_before" : n.zero? ? "rel_now" : "rel_after")
        end

        def sorted_events(eff) = Array(eff["events"]).sort_by { |e| Chrono.position(e["at"]) }

        def describe(data, state: 0)
          eff = effective(data, state)
          eff["scale"] == "years" ? describe_years(eff) : describe_tense(eff)
        end

        def describe_years(eff)
          parts = [ text("years_intro", from: year_label(eff["from"]), to: year_label(eff["to"])) ]
          parts << text("centuries_line", list: list_it(centuries(eff["from"], eff["to"]))) if eff["centuries"]
          Array(eff["lanes"]).each { |l| parts << text("lane_line", label: plain(l["label_it"])) } if Array(eff["lanes"]).size > 1
          Array(eff["periods"]).each { |p| parts << text("period_line", label: name_of(p["label_it"]), from: year_label(p["from"]), to: year_label(p["to"])) }
          events = sorted_events(eff)
          events.each { |e| parts << text("event_line", year: event_year_label(e), label: name_of(e["label_it"])) }
          Array(eff["spans"]).each do |s|
            a = events.find { |e| e["id"] == s["from"] }
            b = events.find { |e| e["id"] == s["to"] }
            next unless a && b

            parts << (s["show_value"] ? text("span_line", a: plain(a["label_it"]), b: plain(b["label_it"]), n: duration_text(Chrono.duration(a["at"], b["at"]))) : text("span_open", a: plain(a["label_it"]), b: plain(b["label_it"])))
          end
          # "a.C." already ends in a full stop: the sentence's own stop is not written twice (as the browser's describe)
          parts.join(" ").gsub(/\b([ac]\.C\.)\./, '\\1')
        end

        def describe_tense(eff)
          parts = [ text("tense_intro") ]
          Array(eff["marks"]).sort_by { |m| [ m["at"].to_i, m["id"] ] }.each do |m|
            say = name_of(m["text_en"] || m["text_es"])
            how = case m["span"]
            when "point" then text("mark_point", at: rel(m["at"]))
            when "range" then text("mark_range", at: rel(m["at"]), to: rel(m["to"]))
            when "habit" then text("mark_habit")
            else text("mark_plan", from: rel(m["from"]), at: rel(m["at"]))
            end
            how += ", #{text('mark_uncertain')}" if m["uncertain"]
            parts << (m["label_it"] ? "#{say} (#{plain(m['label_it'])}): #{how}." : "#{say}: #{how}.")
          end
          parts.join(" ")
        end

        # Every string a state prints: the years and durations as the figure shows them and as a number answer would be written, the words.
        def printed(data, state)
          eff = effective(data, state)
          out = eff["scale"] == "years" ? printed_years(eff) : printed_tense(eff)
          out << (Diagrams.effective_states(data)[state] || {})["op_it"]
          out << describe(data, state: state)
          out.compact.map(&:to_s).reject(&:empty?).uniq
        end

        def signed(year) = Chrono.year(year).to_s

        def printed_years(eff)
          out = []
          events = Array(eff["events"])
          events.each { |e| out.push(e["label_it"], e["note_it"], event_year_label(e), signed(e["at"])) }
          Array(eff["periods"]).each { |p| out << p["label_it"] }
          Array(eff["lanes"]).each { |l| out << l["label_it"] }
          out.concat(centuries(eff["from"], eff["to"])) if eff["centuries"]
          if eff["every"]
            ticks(eff["from"], eff["to"], eff["every"]).each { |y| out.push(year_label(y), signed(y)) }
          end
          Array(eff["spans"]).each do |s|
            next unless s["show_value"]

            a = events.find { |e| e["id"] == s["from"] }
            b = events.find { |e| e["id"] == s["to"] }
            next unless a && b

            n = Chrono.duration(a["at"], b["at"])
            out.push(n.to_s, duration_text(n))
          end
          out.push(text("measure_label"), text("measure_pick"), text("measure_too_many")) if eff["measure"]
          out << text("note_hint") if events.any? { |e| e["note_it"] }
          out
        end

        def printed_tense(eff)
          out = [ text("before"), text("now"), text("after") ]
          Array(eff["marks"]).each { |m| out.push(m["text_en"], m["text_es"], m["label_it"]) }
          out
        end

        # The durations a measure figure can show: every pair of its events, in either order of choosing.
        def reachable(data)
          return [] unless data["measure"]

          out = ([ data ] + Diagrams.effective_states(data)).flat_map do |eff|
            events = Array(eff["events"])
            events.combination(2).flat_map { |a, b| n = Chrono.duration(a["at"], b["at"]).abs; [ n.to_s, duration_text(n) ] }
          end.uniq
          out.size > Contract::REACHABLE_CAP ? :over_cap : out
        end
      end
    end
  end
end
