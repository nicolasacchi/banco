# frozen_string_literal: true

module Lessons
  module Diagrams
    # map (T5, W2-1, D-276): one type, a registry of vendored bases (public/vendor/banco-maps@1). The author writes gazetteer ids, never
    # coordinates on a historical base; the base says where everything is. The browser twin is app/javascript/lesson/diagrams/maps/map.js
    # (with geo.js for the shared geometry and wording); both run test/fixtures/diagrams/types/map.json.
    #
    # Built in W2-1: the modern bases and mediterraneo_antico, detail, graticule, highlight (patterns), bands, places, points (labels),
    # lines (a base line, a meridian or a parallel), routes, the year slider with regions_since (historical bases), candidates, states, and
    # the select targets (areas, places, bands, lines, points). Held back for the map layers of W2-2 (refused here with a clear message):
    # arrows, proportional circles (points[].value), compare, inset, and mercator on a base that is not built in Mercator.
    #
    # Stored ids of the targets (what a select check's `answer` names, stable and in reading order): an area or a place by its gazetteer
    # id; a base line by its id, a meridian "meridian:LON", a parallel "parallel:LAT"; a band "lat:FROM:TO"; a point "pt:LAT:LON" (the
    # numbers as the author wrote them).
    module Map
      extend Contract

      HELD_BACK = %w[compare inset].freeze
      GRATICULE = { "equator" => "l'equatore", "tropics" => "i tropici", "polar_circles" => "i circoli polari", "greenwich" => "il meridiano di Greenwich" }.freeze
      PATTERNS = %w[solid hatch dots cross grid].freeze
      SETS = %w[areas places bands lines points].freeze
      SET_WORDS = { "areas" => "zone", "places" => "luoghi", "bands" => "fasce", "lines" => "linee", "points" => "punti" }.freeze
      TOO_SMALL = 45 # viewBox units: the default candidates of an `areas` set are at least this wide and high

      module_function

      # ---- numbers and words (the JS twin is geo.js; the vectors run both) ----------------------------------------

      def n(text) = Diagrams.num(text)

      def f(text) = n(text)&.to_f

      GF = GeoFormat

      def lat_word(text) = GF.lat_word(n(text))

      def lon_word(text) = GF.lon_word(n(text))

      def year_word(year) = GF.year_word(year)

      def list_it(items) = GF.list_it(items)

      # The pattern of item +index+: the author's, else by the order of the distinct roles of the list (colour is never alone, A4).
      def pattern_of(items, index)
        return items[index]["pattern"] if items[index]["pattern"]

        roles = items.map { |h| h["role"] || "muted" }.uniq
        PATTERNS[roles.index(items[index]["role"] || "muted") % PATTERNS.size]
      end

      # ---- the base of a figure ---------------------------------------------------------------------------------------

      def doc(data) = Maps::Base.read(data["base"])

      def detail_of(data) = data["detail"] || Maps::Base.default_detail(doc(data))

      def raw_states(data) = data["states"].is_a?(Array) && data["states"].any? ? data["states"] : nil

      def effective(data, state)
        top = data.reject { |k, _| k == "states" }
        sts = raw_states(data)
        sts ? top.merge(sts[[ state, sts.size - 1 ].min]) : top
      end

      # ---- checks ------------------------------------------------------------------------------------------------------

      def static(data, c)
        d = doc(data)
        hist = Maps::Base.historical?(d)
        detail = detail_of(data)
        if data["detail"]
          if hist
            c.diagram("/detail", "the base #{data['base']} has no detail: its regions are the historical ones", rule: "detail")
          elsif !Maps::Base.details(d).include?(data["detail"])
            c.diagram("/detail", "the base #{data['base']} has the details #{Maps::Base.details(d).join(', ')}, not #{data['detail']}", rule: "detail")
          end
        end
        c.diagram("/mercator", "mercator: true needs a base built in Mercator (the bases are built once): only mediterraneo_antico is", rule: "mercator") if data["mercator"] && !hist
        HELD_BACK.each { |k| c.diagram("/#{k}", "#{k} arrives with the map layers (W2-2): it is not available yet", rule: "layer-#{k}") if data.key?(k) }
        Array(data["graticule"]).each_with_index do |g, i|
          c.diagram("/graticule/#{i}", "the base #{data['base']} does not draw #{g}", rule: "graticule#{i}") unless graticule_drawn?(d, g)
        end
        cands = Array(data["candidates"])
        cands.each_with_index do |id, i|
          c.diagram("/candidates/#{i}", "#{id} is not an area you can pick on #{data['base']} at the detail #{detail || 'historical'}", rule: "candidate#{i}") unless Maps::Base.units(d, detail).any? { |u| u["id"] == id && u["target"] }
        end
        c.diagram("/candidates", "a candidate is listed twice", rule: "candidates-dup") if cands.uniq.size != cands.size
        layers(data, c, "", d, hist, detail)
        Array(data["states"]).each_with_index { |s, i| layers(s, c, "/states/#{i}", d, hist, detail) if s.is_a?(Hash) }
      end

      def graticule_drawn?(d, key)
        v = (d["graticule"] || {})[key]
        v.is_a?(Array) ? v.any? : !v.nil? && v != ""
      end

      def layers(src, c, path, d, hist, detail)
        hl = src["highlight"].to_a
        hl.each_with_index do |h, i|
          at = "#{path}/highlight/#{i}"
          c.diagram("#{at}/id", "#{h['id']} is not an area of #{d['base']} at the detail #{detail || 'historical'}", rule: "hl#{at}") unless Maps::Base.resolve_area(d, detail, h["id"])
          c.role("#{at}/role", h["role"]) if h["role"]
        end
        c.diagram("#{path}/highlight", "an area is highlighted twice", rule: "hl-dup#{path}") if hl.map { |h| h["id"] }.then { |ids| ids.uniq.size != ids.size }
        src["bands"].to_a.each_with_index { |b, i| check_band(b, c, "#{path}/bands/#{i}", d, hist) }
        seen = []
        src["places"].to_a.each_with_index do |p, i|
          at = "#{path}/places/#{i}/id"
          c.diagram(at, "#{p['id']} is not a place of #{d['base']}", rule: "place#{at}") unless Maps::Base.place(d, p["id"])
          c.diagram(at, "the place #{p['id']} is listed twice", rule: "place-dup#{at}") if seen.include?(p["id"])
          seen << p["id"]
        end
        src["points"].to_a.each_with_index { |p, i| check_point(p, c, "#{path}/points/#{i}", d, hist) }
        src["lines"].to_a.each_with_index { |l, i| check_line(l, c, "#{path}/lines/#{i}", d, hist) }
        src["routes"].to_a.each_with_index do |r, i|
          at = "#{path}/routes/#{i}"
          Array(r["via"]).each_with_index do |id, j|
            next if Maps::Base.place(d, id) || Maps::Base.resolve_area(d, detail, id)

            c.diagram("#{at}/via/#{j}", "#{id} is neither a place nor an area of #{d['base']}", rule: "via#{at}/#{j}")
          end
          c.role("#{at}/role", r["role"]) if r["role"]
          c.label("#{at}/label_it", r["label_it"])
        end
        c.diagram("#{path}/arrows", "arrows arrive with the map layers (W2-2): it is not available yet", rule: "arrows#{path}") if src["arrows"].is_a?(Array) && src["arrows"].any?
        slider(src, c, path, d, hist)
      end

      def check_band(b, c, at, d, hist)
        return c.diagram(at, "agents never write coordinates on a historical base: no bands on #{d['base']}", rule: "band-hist#{at}") if hist

        from = n(b["from_lat"])
        to = n(b["to_lat"])
        if from && to
          c.diagram(at, "a band goes from a smaller to a larger latitude, between -90 and 90", rule: "band#{at}") unless from < to && from >= -90 && to <= 90
          lo = d["box"][1]
          hi = d["box"][3]
          c.diagram(at, "the band lies outside the base's window (#{lo}° to #{hi}°)", rule: "band-box#{at}") if to.to_f < lo || from.to_f > hi
        end
        c.role("#{at}/role", b["role"]) if b["role"]
        c.label("#{at}/label_it", b["label_it"])
      end

      def check_point(p, c, at, d, hist)
        return c.diagram(at, "agents never write coordinates on a historical base: no points on #{d['base']}", rule: "point-hist#{at}") if hist

        c.diagram("#{at}/value", "proportional circles (value) arrive with the map layers (W2-2): not available yet", rule: "point-value#{at}") if p.key?("value")
        lat = f(p["lat"])
        lon = f(p["lon"])
        w, s, e, nn = d["box"]
        if lat && lon && !(lat >= s && lat <= nn && lon >= w && lon <= e)
          c.diagram(at, "the point (#{p['lat']}, #{p['lon']}) is outside the base's window (lat #{s} to #{nn}, lon #{w} to #{e})", rule: "point-box#{at}")
        end
        c.label("#{at}/label_it", p["label_it"])
      end

      def check_line(l, c, at, d, hist)
        if l["id"] && l["kind"]
          c.diagram(at, "a line is a base line (id) or a meridian or a parallel (kind), not both", rule: "line-both#{at}")
        elsif l["id"]
          c.diagram("#{at}/id", "#{l['id']} is not a line of #{d['base']}", rule: "line#{at}") unless Maps::Base.line(d, l["id"])
        elsif l["kind"] == "meridian" || l["kind"] == "parallel"
          return c.diagram(at, "agents never write coordinates on a historical base: no #{l['kind']}s on #{d['base']}", rule: "line-hist#{at}") if hist

          key = l["kind"] == "meridian" ? "lon" : "lat"
          v = f(l[key])
          lo, hi = l["kind"] == "meridian" ? [ d["box"][0], d["box"][2] ] : [ d["box"][1], d["box"][3] ]
          c.diagram("#{at}/#{key}", "a #{l['kind']} needs #{key}, inside the base's window (#{lo} to #{hi})", rule: "#{l['kind']}#{at}") unless v && v >= lo && v <= hi
        else
          c.diagram(at, "a line is a base line (id) or a meridian or a parallel (kind)", rule: "line-none#{at}")
        end
        c.label("#{at}/label_it", l["label_it"])
      end

      def slider(src, c, path, d, hist)
        sl = src["slider"]
        rs = src["regions_since"].to_a
        c.diagram("#{path}/slider", "the year slider is for the historical bases", rule: "slider-base#{path}") if sl && !hist
        c.diagram("#{path}/regions_since", "regions_since is for the historical bases", rule: "since-base#{path}") if rs.any? && !hist
        c.diagram("#{path}/regions_since", "regions_since needs the year slider (from and to)", rule: "since-slider#{path}") if rs.any? && !sl
        rs.each_with_index do |r, i|
          next unless hist

          c.diagram("#{path}/regions_since/#{i}/id", "#{r['id']} is not a region of #{d['base']}", rule: "since#{path}/#{i}") unless Maps::Base.resolve_area(d, nil, r["id"])
          c.role("#{path}/regions_since/#{i}/role", r["role"]) if r["role"]
        end
        return unless sl && hist

        from = sl["from"].to_i
        to = sl["to"].to_i
        c.diagram("#{path}/slider", "the slider goes from an earlier to a later year (or is one year: from equal to to)", rule: "slider-order#{path}") if from > to
        c.diagram("#{path}/slider", "the slider stays inside one era (there is no year 0)", rule: "slider-era#{path}") if from.negative? && to.positive?
        c.diagram("#{path}/slider", "the slider spans at most 500 years", rule: "slider-span#{path}") if to - from > 500
        rs.each_with_index do |r, i|
          c.diagram("#{path}/regions_since/#{i}/since", "the year #{r['since']} is after the end of the slider (#{sl['to']}): the region would never appear", rule: "since-late#{path}/#{i}") if r["since"].to_i > to
        end
      end

      def state(_eff, _c, _path) = nil

      # ---- the view of one effective state (what is drawn) -----------------------------------------------------------------

      # The year a figure shows in state +eff+: the control's value inside the slider's range, or the slider's start; nil without slider.
      def year_of(eff, controls)
        sl = eff["slider"] or return nil
        from = sl["from"].to_i
        to = sl["to"].to_i
        y = controls && controls["year"] ? controls["year"].to_i : from
        [ [ y, from ].max, to ].min
      end

      def view(data, eff, year: nil)
        d = doc(data)
        detail = detail_of(data)
        hl_in = eff["highlight"].to_a
        hl = hl_in.each_with_index.map do |h, i|
          { "id" => h["id"], "name" => Maps::Base.name_of(d, "areas", h["id"]) || h["id"], "role" => h["role"] || "muted", "pattern" => pattern_of(hl_in, i) }
        end
        since_in = year ? eff["regions_since"].to_a.select { |r| r["since"].to_i <= year } : []
        since = since_in.each_with_index.map do |r, i|
          { "id" => r["id"], "name" => Maps::Base.name_of(d, "areas", r["id"]) || r["id"], "role" => r["role"] || "muted", "pattern" => pattern_of(since_in, i) }
        end
        bands_in = eff["bands"].to_a
        { "doc" => d, "detail" => detail, "title" => d["title_it"], "approximate" => d["approximate"] == true, "polar" => Maps::Base.polar?(d),
          "graticule" => eff["graticule"].to_a, "highlight" => hl, "since" => since,
          "places" => eff["places"].to_a.map { |p| { "id" => p["id"], "name" => Maps::Base.name_of(d, "places", p["id"]) || p["id"] } },
          "points" => eff["points"].to_a.map { |p| { "lat" => p["lat"], "lon" => p["lon"], "label" => p["label_it"] } },
          "bands" => bands_in.each_with_index.map { |b, i| { "from" => b["from_lat"], "to" => b["to_lat"], "label" => b["label_it"], "role" => b["role"] || "muted", "pattern" => pattern_of(bands_in, i) } },
          "lines" => eff["lines"].to_a.map { |l| line_view(d, l) },
          "routes" => eff["routes"].to_a.map do |r|
            { "label" => r["label_it"], "role" => r["role"] || "muted",
              "via" => r["via"].map { |id| { "id" => id, "name" => Maps::Base.place(d, id) ? (Maps::Base.name_of(d, "places", id) || id) : (Maps::Base.name_of(d, "areas", id) || id) } } }
          end,
          "year" => year, "op" => eff["op_it"] }
      end

      def line_view(d, l)
        if l["id"] then { "kind" => "id", "key" => l["id"], "name" => l["label_it"] || Maps::Base.name_of(d, "lines", l["id"]) || l["id"] }
        elsif l["kind"] == "meridian" then { "kind" => "meridian", "key" => "meridian:#{l['lon']}", "name" => l["label_it"], "lon" => l["lon"] }
        else { "kind" => "parallel", "key" => "parallel:#{l['lat']}", "name" => l["label_it"], "lat" => l["lat"] }
        end
      end

      # ---- describe and printed ------------------------------------------------------------------------------------------------

      def describe(data, state: 0, mode: "student", controls: nil)
        eff = effective(data, state)
        return describe_select(data, eff) if mode == "select"

        v = view(data, eff, year: year_of(eff, controls))
        out = [ "Carta: #{v['title']}." ]
        out << "Confini approssimativi." if v["approximate"]
        out << (v["polar"] ? "Il polo è al centro della carta." : "Il nord è in alto, l'ovest a sinistra e l'est a destra.")
        out << "Si vedono: #{list_it(v['graticule'].map { |g| GRATICULE.fetch(g) })}." unless v["graticule"].empty?
        out << "In evidenza: #{list_it(v['highlight'].map { |h| h['name'] })}." unless v["highlight"].empty?
        if v["year"]
          out << (v["since"].empty? ? "Nel #{year_word(v['year'])}" : "Nel #{year_word(v['year'])} in evidenza: #{list_it(v['since'].map { |h| h['name'] })}.")
        end
        v["bands"].each { |b| out << "#{GF.capital(b['label'] || 'fascia')}, da #{lat_word(b['from'])} a #{lat_word(b['to'])}." }
        out << "Luoghi: #{list_it(v['places'].map { |p| p['name'] })}." unless v["places"].empty?
        v["points"].each { |p| out << "#{p['label'] || 'Un punto'}: #{lat_word(p['lat'])}, #{lon_word(p['lon'])}." }
        v["lines"].each do |l|
          out << case l["kind"]
          when "id" then "Linea: #{l['name']}."
          when "meridian" then "Meridiano #{lon_word(l['lon'])}#{l['name'] ? ": #{l['name']}" : ''}."
          else "Parallelo #{lat_word(l['lat'])}#{l['name'] ? ": #{l['name']}" : ''}."
          end
        end
        v["routes"].each { |r| out << "Percorso#{r['label'] ? " (#{r['label']})" : ''}: #{list_it(r['via'].map { |x| x['name'] })}." }
        out << "#{v['op']}." if v["op"]
        out.join(" ")
      end

      def describe_select(data, eff)
        set = SETS.find { |s| target_list(data, eff, s).any? } || "areas"
        "Una carta: #{doc(data)['title_it']}. Ci sono #{target_list(data, eff, set).size} #{SET_WORDS.fetch(set)} da toccare."
      end

      # The strings the state prints (L4): the description at every year of the slider and each name, label, step line and the caption.
      def printed(data, state = 0)
        eff = effective(data, state)
        sl = eff["slider"]
        years = sl && sl["from"] != sl["to"] ? year_list(sl) : [ sl && sl["from"].to_i ]
        out = []
        years.each do |y|
          v = view(data, eff, year: y)
          out << describe(data, state: state, controls: y ? { "year" => y } : nil)
          out.concat(v["highlight"].map { |h| h["name"] }, v["since"].map { |h| h["name"] }, v["places"].map { |p| p["name"] })
          out.concat(v["points"].filter_map { |p| p["label"] }, v["bands"].filter_map { |b| b["label"] }, v["lines"].filter_map { |l| l["name"] })
          out.concat(v["routes"].flat_map { |r| [ r["label"], *r["via"].map { |x| x["name"] } ].compact })
        end
        out << eff["op_it"] if eff["op_it"]
        out << data["caption_it"] if data["caption_it"]
        out << "Confini approssimativi" if doc(data)["approximate"]
        out.compact.uniq
      end

      def year_list(sl) = (sl["from"].to_i..sl["to"].to_i).reject(&:zero?).to_a

      # The outputs the controls can show within their ranges: a year slider shows each year with the regions it lists.
      def reachable(data)
        out = []
        (raw_states(data) ? raw_states(data).each_index.map { |i| effective(data, i) } : [ effective(data, 0) ]).each do |eff|
          sl = eff["slider"]
          next unless sl && sl["from"] != sl["to"]

          year_list(sl).each do |y|
            out << year_word(y)
            out.concat(view(data, eff, year: y)["since"].map { |h| h["name"] })
          end
        end
        out = out.uniq
        out.size > Contract::REACHABLE_CAP ? :over_cap : out
      end

      # ---- served and targets ------------------------------------------------------------------------------------------------

      # The projection of the figure for the browser. :student and :teacher: the declared fields with the states merged (nothing of a
      # map is a solution). :select: the neutral figure of one set of targets, no states, no labels, no roles, no patterns, nothing
      # marked (L3); +set+ is the check's `targets` (default: the first set the figure has).
      def served(data, mode: :student, set: nil)
        return StudentBody.diagram_generic(data) unless mode.to_sym == :select

        eff = effective(data, 0)
        set ||= SETS.find { |s| target_list(data, eff, s).any? } || "areas"
        out = eff.slice("type", "alt_it", "caption_it", "size", "base", "detail", "mercator", "graticule")
        base = data["base"]
        key = ->(id) { Maps::SelectKeys.key(base, id) or raise ArgumentError, "#{id} has no select key on #{base}" }
        out["candidates"] = eff["candidates"].map(&key) if set.to_s == "areas" && eff["candidates"]
        case set.to_s
        when "bands" then out["bands"] = eff["bands"].to_a.map { |b| b.slice("from_lat", "to_lat") }
        when "places" then out["places"] = eff["places"].to_a.map { |p| { "id" => key.call(p["id"]) } }
        when "points" then out["points"] = eff["points"].to_a.map { |p| p.slice("lat", "lon") }
        when "lines" then out["lines"] = eff["lines"].to_a.map { |l| l["id"] ? { "id" => key.call(l["id"]) } : l.slice("kind", "lon", "lat") }
        end
        out
      end

      # [{ "id" (stored), "x", "y" }] of a set, in the base's viewBox, before the reading order is applied.
      def target_list(data, eff, set)
        d = doc(data)
        case set.to_s
        when "areas"
          cands = Array(eff["candidates"])
          Maps::Base.units(d, detail_of(data)).select { |u| u["target"] && (cands.empty? ? default_target?(u) : cands.include?(u["id"])) }
                    .map { |u| { "id" => u["id"], "x" => u["anchor"][0], "y" => u["anchor"][1] } }
        when "places"
          eff["places"].to_a.filter_map { |p| (pl = Maps::Base.place(d, p["id"])) && { "id" => p["id"], "x" => pl["x"], "y" => pl["y"] } }
        when "bands"
          mid_lon = (d["box"][0] + d["box"][2]) / 2.0
          eff["bands"].to_a.map do |b|
            x, y = Maps::Base.project(d, (f(b["from_lat"]) + f(b["to_lat"])) / 2, mid_lon)
            { "id" => "lat:#{b['from_lat']}:#{b['to_lat']}", "x" => x, "y" => y }
          end
        when "lines"
          eff["lines"].to_a.filter_map do |l|
            if l["id"]
              bx = Maps::Base.box_of(Maps::Base.line(d, l["id"])&.fetch("d", "").to_s) or next
              { "id" => l["id"], "x" => (bx[0] + bx[2]) / 2, "y" => (bx[1] + bx[3]) / 2 }
            elsif l["kind"] == "meridian"
              x, y = Maps::Base.project(d, (d["box"][1] + d["box"][3]) / 2.0, f(l["lon"]))
              { "id" => "meridian:#{l['lon']}", "x" => x, "y" => y }
            else
              x, y = Maps::Base.project(d, f(l["lat"]), (d["box"][0] + d["box"][2]) / 2.0)
              { "id" => "parallel:#{l['lat']}", "x" => x, "y" => y }
            end
          end
        when "points"
          eff["points"].to_a.map do |p|
            x, y = Maps::Base.project(d, f(p["lat"]), f(p["lon"]))
            { "id" => "pt:#{p['lat']}:#{p['lon']}", "x" => x, "y" => y }
          end
        else []
        end
      end

      # Without `candidates`, the areas big enough to touch.
      def default_target?(unit)
        b = unit["bbox"]
        (b[2] - b[0]) >= TOO_SMALL && (b[3] - b[1]) >= TOO_SMALL
      end

      def ordered(data, set)
        raise ArgumentError, "unknown target set #{set.inspect}" unless SETS.include?(set.to_s)

        base = data["base"]
        target_list(data, effective(data, 0), set).sort_by { |t| Maps::Base.reading_key(t["x"], t["y"], Maps::SelectKeys.key(base, t["id"]) || t["id"]) }
      end

      # The stored ids of the targets of +set+ in reading order (the same order as the JS targets()).
      def targets(data, set) = ordered(data, set).map { |t| t["id"] }

      # The compass phrase of each target in reading order (the JS `neutral_it`).
      def neutral(data, set)
        d = doc(data)
        ordered(data, set).map { |t| Maps::Base.compass(d, t["x"], t["y"]) }
      end
    end
  end
end
