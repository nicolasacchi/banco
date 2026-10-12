# frozen_string_literal: true

require "json"

module Maps
  # Reads a built base (public/vendor/banco-maps@1/<base>.js) for the Ruby checks of the lesson `map` (T5, W2-1): the ids it
  # holds, the units it draws at a detail, where each one is, and the names of the vetted tables. The JS twin is
  # app/javascript/lesson/diagrams/maps/geo.js; both run the same vectors (test/fixtures/diagrams/types/map.json).
  #
  # Ids resolve PER BASE (D-271): the base's `reads` names the table of each collection (`areas`, `groups`, `places`, `lines`,
  # `oceans`), so "sicilia" the Roman province (history/regions) is never "sicilia" the Italian region (geo/names).
  module Base
    DIR = File.expand_path("../../public/vendor/banco-maps@1", __dir__)
    NAMES = %w[geo/names history/places history/regions].freeze
    # Reading order of the targets: north to south, then west to east (rows of 1 viewBox unit), then the id.
    COMPASS_ROWS = %w[nord centro sud].freeze

    module_function

    def names_available = Dir.children(DIR).grep(/\.js\z/).map { |f| f.delete_suffix(".js") }.sort

    def read(name)
      @bases ||= {}
      @bases[name] ||= JSON.parse(File.read(File.join(DIR, "#{name}.js")).sub(/\A.*?export default /m, "").sub(/;\s*\z/, "")).freeze
    end

    # { "id" => row } of a vetted table, "geo/names" (names), "history/places", "history/regions".
    def table(name)
      @tables ||= {}
      @tables[name] ||= begin
        data = Lessons::VettedData.table(name) or raise ArgumentError, "table #{name} is not written"
        data.fetch(name == "geo/names" ? "names" : name.split("/").last)
      end
    end

    def historical?(doc) = doc["detail"] == "historical"

    def polar?(doc) = doc.dig("projection", "type") == "lambert_azimuthal"

    # The detail a figure draws when it names none.
    def default_detail(doc)
      return nil if historical?(doc)

      case doc["base"]
      when "world" then "continents"
      when "italy" then "regions"
      else "states"
      end
    end

    # The details a base can draw.
    def details(doc)
      return [] if historical?(doc)

      case doc["base"]
      when "world" then %w[continents states]
      when "italy" then %w[regions states]
      else %w[continents states]
      end
    end

    def box_of(path)
      xs = []
      ys = []
      x = 0.0
      y = 0.0
      cmd = nil
      nums = []
      flush = lambda do
        case cmd
        when "M"
          nums.each_slice(2) { |a, b| next unless b; x = a; y = b; xs << x; ys << y }
        when "l"
          nums.each_slice(2) { |a, b| next unless b; x += a; y += b; xs << x; ys << y }
        end
        nums = []
      end
      path.scan(/[Mlz]|-?\d*\.?\d+/) do |tok|
        if tok.match?(/\A[Mlz]\z/)
          flush.call
          cmd = tok
        else
          nums << tok.to_f
        end
      end
      flush.call
      return nil if xs.empty?

      [ xs.min, ys.min, xs.max, ys.max ]
    end

    # The units a figure of detail +detail+ draws and can pick: [{ "id", "kind", "members", "anchor", "bbox", "target" }]. A unit with
    # "target" false is context (a neighbour country on the regions of Italy): drawn, never a candidate.
    def units(doc, detail)
      areas = doc["areas"]
      by_id = areas.to_h { |a| [ a["id"], a ] }
      if historical?(doc)
        return areas.map { |a| { "id" => a["id"], "kind" => "region", "members" => [ a["id"] ], "anchor" => a["anchor"], "bbox" => a["bbox"], "target" => true } }
      end

      groups = doc["groups"] || []
      out = []
      case detail
      when "continents"
        groups.select { |g| g["kind"] == "continent" }.each { |g| out << group_unit(g, by_id, true) }
        covered = out.flat_map { |u| u["members"] }
        areas.reject { |a| covered.include?(a["id"]) }.each { |a| out << area_unit(a, false) }
      when "regions"
        areas.each { |a| out << area_unit(a, a["kind"] == "region") }
      else
        merged = groups.select { |g| g["kind"] == "country" }
        hidden = merged.flat_map { |g| g["members"] }
        areas.reject { |a| hidden.include?(a["id"]) }.each { |a| out << area_unit(a, a["kind"] != "region") }
        merged.each { |g| out << group_unit(g, by_id, true) }
      end
      out
    end

    def area_unit(a, target) = { "id" => a["id"], "kind" => a["kind"], "members" => [ a["id"] ], "anchor" => a["anchor"], "bbox" => a["bbox"], "target" => target }

    def group_unit(g, by_id, target)
      boxes = g["members"].filter_map { |m| by_id[m]&.fetch("bbox") }
      bbox = g["bbox"] || [ boxes.map { |b| b[0] }.min, boxes.map { |b| b[1] }.min, boxes.map { |b| b[2] }.max, boxes.map { |b| b[3] }.max ]
      { "id" => g["id"], "kind" => g["kind"], "members" => g["members"], "anchor" => g["anchor"], "bbox" => bbox, "target" => target }
    end

    # The unit named by +id+ at +detail+, or the group of that id (drawn as its members), or nil.
    def resolve_area(doc, detail, id)
      us = units(doc, detail)
      us.find { |u| u["id"] == id } || (doc["groups"] || []).find { |g| g["id"] == id }&.then { |g| group_unit(g, doc["areas"].to_h { |a| [ a["id"], a ] }, false) }
    end

    def place(doc, id) = doc["places"].find { |p| p["id"] == id }

    def line(doc, id) = (doc["lines"] || []).find { |l| l["id"] == id }

    def projection(doc)
      p = doc.fetch("projection")
      Geom::Projection.new(p["type"], p["scale"], p["tx"], p["ty"], doc["viewBox"][2], doc["viewBox"][3], p["pole"])
    end

    # [x, y] in the base's viewBox of a latitude and a longitude (floats).
    def project(doc, lat, lon) = projection(doc).project(lon, lat)

    # The name of an id read from the table the base declares for +collection+; nil when the id has no row.
    def name_of(doc, collection, id)
      table_name = doc.dig("reads", collection) or return nil
      table(table_name).dig(id, "name_it")
    end

    # The compass position of a point of the viewBox as a phrase: "a nord-ovest", "al centro". Polar bases say "in alto a sinistra".
    def compass(doc, x, y)
      w = doc["viewBox"][2].to_f
      h = doc["viewBox"][3].to_f
      col = x < w / 3 ? 0 : (x > w * 2 / 3 ? 2 : 1)
      row = y < h / 3 ? 0 : (y > h * 2 / 3 ? 2 : 1)
      if polar?(doc)
        v = [ "in alto", nil, "in basso" ][row]
        hz = [ "a sinistra", nil, "a destra" ][col]
        return "al centro" if v.nil? && hz.nil?

        return [ v, hz ].compact.join(" ")
      end
      names = [ [ "a nord-ovest", "a nord", "a nord-est" ], [ "a ovest", "al centro", "a est" ], [ "a sud-ovest", "a sud", "a sud-est" ] ]
      names[row][col]
    end

    # The sort key of reading order (north to south, west to east): rows of one viewBox unit, then x, then the id.
    def reading_key(x, y, tie) = [ (y + 0.5).floor, (x + 0.5).floor, tie.to_s ]
  end
end
