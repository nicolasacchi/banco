# frozen_string_literal: true

module Lessons
  module Diagrams
    # The climograph (T6, WAVE2 2.4; geography 3.2): twelve monthly temperatures and rainfalls, from a vetted station (`station:
    # geo/stations.brasilia`) or inline with a source. Our code fixes the Bagnouls-Gaussen scale (the mm axis is twice the degrees axis,
    # zeros aligned; the browser compresses what falls above 100 mm into a marked band) and computes everything else: the arid months
    # (P <= 2T), the annual total, the annual mean, the warmest and the coldest month and the range. None of it is author data (1.1).
    # The browser twin is app/javascript/lesson/diagrams/chart/climograph.js; both run test/fixtures/lesson2/climate.json.
    module Climograph
      extend Contract

      LAYERS = %w[bars line arid range total].freeze
      TABLE = "geo/stations"

      class << self
        def rule(key) = Validation::Rules.get(:lesson2, :types, :climograph, key)

        # { arid: [month numbers 1..12], total:, mean:, warmest:, coldest:, range:, tmax:, tmin: } of twelve Rationals each.
        def stats(temp, precip)
          tmax = temp.max
          tmin = temp.min
          {
            arid: (0..11).select { |i| precip[i] <= 2 * temp[i] }.map { |i| i + 1 },
            total: precip.sum, mean: temp.sum / 12, warmest: temp.index(tmax) + 1, coldest: temp.index(tmin) + 1,
            range: tmax - tmin, tmax: tmax, tmin: tmin
          }
        end

        # The row of "geo/stations.id", or nil.
        def row_of(ref)
          table, id = ref.to_s.split(".", 2)
          table == TABLE ? Lessons::VettedData.row(TABLE, "stations", id) : nil
        end

        def label_of(row)
          row["name_it"] == row["country_it"] ? row["name_it"] : "#{row['name_it']} (#{row['country_it']})"
        end

        def source_of(row)
          if row["source"].to_s.start_with?("Environment and Climate Change Canada")
            "Medie 1991-2020, Environment and Climate Change Canada"
          else
            "Medie 1991-2020 dei servizi meteorologici nazionali (OMM)"
          end
        end

        # The figure with a station replaced by its numbers (the author's own place_it and source_it win).
        def resolved(data)
          row = data["station"] && row_of(data["station"])
          out = row ? data.merge("temp" => row["temp"], "precip" => row["precip"], "lat" => row["lat"], "alt_m" => row["alt_m"],
                                 "place_it" => data["place_it"] || label_of(row), "source_it" => data["source_it"] || source_of(row)) : data
          cmp = data["compare"]
          if cmp && cmp["station"] && (crow = row_of(cmp["station"]))
            out = out.merge("compare" => cmp.merge("temp" => crow["temp"], "place_it" => cmp["place_it"] || label_of(crow)))
          end
          out
        end

        def series(values) = Array(values).map { |v| Diagrams.num(v) }

        def static(data, c)
          if data["station"]
            c.add("E-LESSON-DATA", "/station", "#{data['station']} names no row of #{TABLE} (an id such as geo/stations.brasilia)", rule: "station") unless row_of(data["station"])
            c.diagram("/temp", "a station brings its own numbers: leave temp and precip out", rule: "station-and-temp") if data["temp"] || data["precip"]
          end
          cmp = data["compare"]
          if cmp
            c.diagram("/compare", "compare names a station or gives temp, not both and not neither", rule: "compare-one") if cmp["station"].nil? == cmp["temp"].nil?
            c.add("E-LESSON-DATA", "/compare/station", "#{cmp['station']} names no row of #{TABLE}", rule: "compare-station") if cmp["station"] && !row_of(cmp["station"])
            check_series(cmp["temp"], "/compare/temp", :temp, c) if cmp["temp"]
            c.label("/compare/place_it", cmp["place_it"])
            c.diagram("/compare", "compare gives the name of the second place: place_it or a station", rule: "compare-name") if cmp["station"].nil? && cmp["place_it"].nil?
          end
          if cmp && !([ data ] + Diagrams.effective_states(data)).any? { |e| (e["show"] || %w[bars line]).include?("line") }
            c.diagram("/compare", "compare draws a second temperature line: some state shows the line", rule: "compare-line")
          end
          c.label("/place_it", data["place_it"])
          lat = Diagrams.num(data["lat"]) if data["lat"]
          c.diagram("/lat", "lat is a latitude between -90 and 90", rule: "lat") if lat && (lat < -90 || lat > 90)
          alt = Diagrams.num(data["alt_m"]) if data["alt_m"]
          c.diagram("/alt_m", "alt_m is an altitude between -500 and 9000 metres", rule: "alt") if alt && (alt < -500 || alt > 9000)
          unless data["station"]
            check_series(data["temp"], "/temp", :temp, c) if data["temp"]
            check_series(data["precip"], "/precip", :precip, c) if data["precip"]
            c.diagram("/place_it", "an inline climograph names its place: place_it", rule: "place") if data["place_it"].nil?
          end
        end

        def check_series(values, path, kind, c)
          lo, hi = rule(kind == :temp ? :temp_range : :precip_range)
          Array(values).each_with_index do |v, i|
            n = Diagrams.num(v)
            next if n.nil?

            c.diagram("#{path}/#{i}", "#{v} is outside #{lo} to #{hi} (#{kind == :temp ? 'degrees' : 'millimetres'})", rule: "#{kind}#{path}/#{i}") unless n >= lo && n <= hi
          end
        end

        def state(eff, c, path)
          show = eff["show"] || %w[bars line]
          c.diagram("#{path}/show", "arid needs bars and line in the same state (a month is arid when the bar is under the line)", rule: "arid#{path}") if show.include?("arid") && !(show.include?("bars") && show.include?("line"))
          c.diagram("#{path}/show", "range needs the line", rule: "range#{path}") if show.include?("range") && !show.include?("line")
          c.diagram("#{path}/show", "total needs the bars", rule: "total#{path}") if show.include?("total") && !show.include?("bars")
          c.diagram("#{path}/show", "a layer is named once", rule: "dup#{path}") if show.uniq.size != show.size
        end

        # ---- served, targets, printed, reachable -----------------------------------------------------------------------

        def served(data, mode: :student)
          out = Lessons::StudentBody.diagram_generic(data)
          full = resolved(Diagrams.merge_states(data).except("states"))
          %w[temp precip place_it lat alt_m source_it compare].each { |k| out[k] = full[k] if full.key?(k) }
          out
        end

        def months_of(set) = set.to_s == "months" ? (1..12).map { |m| "m#{m}" } : raise(ArgumentError, "climograph has no select set #{set.inspect}")

        def targets(_data, set) = months_of(set)

        # The effective state i (0 for a figure without states) with its numbers resolved.
        def effective(data, state)
          eff = Diagrams.effective_states(data)
          resolved(eff.empty? ? data : eff.fetch([ state.to_i, eff.size - 1 ].min))
        end

        # Every number the state prints, as an author writes it: the values of the shown layers and the computed lines.
        def printed(data, state)
          eff = effective(data, state)
          show = eff["show"] || %w[bars line]
          temp = series(eff["temp"])
          precip = series(eff["precip"])
          s = stats(temp, precip)
          out = []
          out.concat(eff["temp"]) if show.include?("line")
          out.concat(eff["precip"]) if show.include?("bars")
          out.concat(Array(eff.dig("compare", "temp"))) if eff["compare"]
          out.push(s[:range], s[:tmax], s[:tmin]) if show.include?("range")
          out << s[:total] if show.include?("total")
          ChartSupport.numbers(out)
        end

        # With the read cursor the student can step through the months and read each value of the shown layers.
        def reachable(data)
          return [] unless data["read"]

          out = []
          ([ data ] + Diagrams.effective_states(data)).each { |eff| out.concat(printed_values(resolved(eff))) }
          list = ChartSupport.numbers(out)
          list.size > Contract::REACHABLE_CAP ? :over_cap : list
        end

        def printed_values(eff)
          show = eff["show"] || %w[bars line]
          (show.include?("line") ? eff["temp"].to_a : []) + (show.include?("bars") ? eff["precip"].to_a : [])
        end
      end
    end
  end
end
