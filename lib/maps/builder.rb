# frozen_string_literal: true

require "json"
require "yaml"
require "zlib"
require "digest"
require_relative "geom"
require_relative "sources"
require_relative "tables"

module Maps
  # Builds public/vendor/banco-maps@1/<base>.js from the committed sources and tables, offline and
  # deterministic (T5, W2-1). One file per base; a card with a map loads only its own.
  class Builder
    ROOT = Sources::ROOT
    OUT = File.join(ROOT, "public/vendor/banco-maps@1")
    HISTORY = File.join(Tables::DATA, "history")
    VECTORS = File.join(ROOT, "test/fixtures/maps/projection_vectors.json")
    WIDTH = 1000.0
    GZIP_BUDGET = 60_000
    EPSILONS = [ 0.25, 0.35, 0.5, 0.7, 1.0, 1.4, 2.0, 2.8 ].freeze
    TROPIC = 23.4 # the lessons' own value ("23,4")
    # Our label positions for the continents ([lon, lat]).
    CONTINENT_ANCHORS = {
      "africa" => [ 20, 5 ], "asia" => [ 90, 45 ], "europe" => [ 15, 50 ], "north_america" => [ -100, 45 ],
      "south_america" => [ -60, -12 ], "oceania" => [ 135, -25 ], "antarctica" => [ 0, -80 ]
    }.freeze
    # Natural Earth's continent to our key; the Russian Federation is in both Europe and Asia.
    CONTINENT_KEYS = {
      "Africa" => "africa", "Asia" => "asia", "Europe" => "europe", "North America" => "north_america",
      "South America" => "south_america", "Oceania" => "oceania", "Antarctica" => "antarctica"
    }.freeze
    BOTH_CONTINENTS = { "RUS" => %w[europe asia] }.freeze
    HISTORIC_RIVERS = Tables::HISTORIC_RIVERS

    # detail: continents | states | regions (italy) | historical
    BASES = {
      "world" => { title_it: "Il mondo", proj: "equal_earth", window: [ -180, -90, 180, 90 ], crop: false, res: 110, detail: "continents", river_rank: 2, lake_rank: 1 },
      "europe" => { title_it: "Europa", proj: "equal_earth", window: [ -25, 34, 45, 72 ], res: 50, detail: "states", river_rank: 4, lake_rank: 2 },
      "africa" => { title_it: "Africa", proj: "equal_earth", window: [ -20, -36, 53, 38 ], res: 110, detail: "states", river_rank: 3, lake_rank: 2 },
      "asia" => { title_it: "Asia", proj: "equal_earth", window: [ 25, -11, 180, 78 ], res: 110, detail: "states", river_rank: 3, lake_rank: 2 },
      "north_america" => { title_it: "America del Nord", proj: "equal_earth", window: [ -170, 5, -20, 84 ], res: 110, detail: "states", river_rank: 3, lake_rank: 3 },
      "south_america" => { title_it: "America del Sud", proj: "equal_earth", window: [ -83, -57, -33, 14 ], res: 110, detail: "states", river_rank: 3, lake_rank: 2 },
      "oceania" => { title_it: "Oceania", proj: "equal_earth", window: [ 110, -50, 180, 0 ], res: 110, detail: "states", river_rank: 3, lake_rank: 2 },
      "arctic" => { title_it: "L'Artico", proj: "lambert_azimuthal", pole: "north", window: [ -180, 60, 180, 90 ], crop: false, res: 110, detail: "states", river_rank: 2, lake_rank: 1 },
      "antarctic" => { title_it: "L'Antartide", proj: "lambert_azimuthal", pole: "south", window: [ -180, -90, 180, -60 ], crop: false, res: 110, detail: "states", river_rank: 0, lake_rank: 0 },
      "italy" => { title_it: "Italia", proj: "equal_earth", window: [ 6, 35.4, 19, 47.3 ], res: 50, detail: "regions", river_rank: 4, lake_rank: 4 },
      "mediterraneo_antico" => { title_it: "Il Mediterraneo antico", proj: "mercator", window: [ -12, 24, 58, 58 ], res: 50, detail: "historical", river_rank: 4, lake_rank: 3 }
    }.freeze

    attr_reader :warnings

    def initialize
      @warnings = []
    end

    def names = @names ||= YAML.safe_load_file(Tables::NAMES).fetch("names")
    def places = @places ||= YAML.safe_load_file(File.join(HISTORY, "places.yml")).fetch("places")
    def regions = @regions ||= YAML.safe_load_file(File.join(HISTORY, "regions.yml")).fetch("regions")

    # { "world.js" => text, ... "SHA256SUMS" => text, ... } for the whole directory.
    def build_all
      files = {}
      @eps = {}
      BASES.each_key { |b| files["#{b}.js"] = build(b) }
      files["PROVENANCE.md"] = provenance
      files["LICENSE"] = licence
      files["README.txt"] = readme
      files["SHA256SUMS"] = sums(files)
      files
    end

    def sums(files)
      files.sort.map { |name, text| "#{Digest::SHA256.hexdigest(text)}  ./#{name}" }.join("\n") + "\n"
    end

    # Writes the directory, and the projection vectors the JS twin will check.
    def write!
      files = build_all
      FileUtils.mkdir_p(OUT)
      (Dir.children(OUT) - files.keys).each { |f| FileUtils.rm_rf(File.join(OUT, f)) }
      files.each { |name, text| File.write(File.join(OUT, name), text) }
      FileUtils.mkdir_p(File.dirname(VECTORS))
      File.write(VECTORS, vectors_json)
      files
    end

    def check
      files = build_all
      bad = files.reject { |name, text| File.exist?(File.join(OUT, name)) && File.read(File.join(OUT, name)) == text }.keys
      bad << "projection_vectors.json" unless File.exist?(VECTORS) && File.read(VECTORS) == vectors_json
      extra = Dir.children(OUT) - files.keys
      [ bad, extra ]
    end

    def projection_of(base)
      cfg = BASES.fetch(base)
      @proj ||= {}
      @proj[base] ||= Geom.fit(cfg[:proj], cfg[:window], WIDTH, crop: cfg.fetch(:crop, true), pole: cfg[:pole])
    end

    # Sample points for the JS twin (app/javascript/lesson/lib/map_projection.js), both for each base's own
    # projection and for the three types with fixed parameters (the poles included), so a type no base
    # uses today is still checked.
    POINTS = [ [ 0, 0 ], [ 12.5, 41.9 ], [ -51.1, 0 ], [ 100, -30 ], [ -70, 60 ], [ 30, -75 ], [ 180, 45 ], [ -180, -45 ], [ 9, 78 ], [ -120, -62 ] ].freeze
    FIXED = [
      { "type" => "equal_earth", "scale" => 100.0, "tx" => 500.0, "ty" => 250.0 },
      { "type" => "mercator", "scale" => 100.0, "tx" => 500.0, "ty" => 250.0 },
      { "type" => "lambert_azimuthal", "pole" => "north", "scale" => 100.0, "tx" => 500.0, "ty" => 500.0 },
      { "type" => "lambert_azimuthal", "pole" => "south", "scale" => 100.0, "tx" => 500.0, "ty" => 500.0 }
    ].freeze

    def vector_points(pr, lat_range = nil)
      POINTS.filter_map do |lon, lat|
        next if lat_range && !lat_range.cover?(lat)

        x, y = pr.project(lon, lat)
        [ lon, lat, x.round(2), y.round(2) ]
      end
    end

    def vectors_json
      bases = BASES.keys.to_h do |b|
        pr = projection_of(b)
        [ b, { "projection" => pr.to_h, "points" => vector_points(pr) } ]
      end
      fixed = FIXED.map do |h|
        pr = Geom::Projection.new(h["type"], h["scale"], h["tx"], h["ty"], 1000.0, 0, h["pole"])
        { "projection" => h, "points" => vector_points(pr, h["type"] == "mercator" ? -80..80 : nil) }
      end
      JSON.pretty_generate("version" => 2, "note" => "lon, lat, x, y in the viewBox; the JS projection twin (equal_earth, lambert_azimuthal with a pole, mercator) must agree to 0.01. `bases` use each base's own projection, `projections` fixed parameters for every type",
                           "bases" => bases, "projections" => fixed) + "\n"
    end

    # ---- one base -------------------------------------------------------------------------

    def build(base)
      cfg = BASES.fetch(base)
      last = nil
      EPSILONS.each do |eps|
        text = render(base, cfg, eps)
        last = text
        size = Zlib::Deflate.deflate(text, 9).bytesize
        if size <= GZIP_BUDGET
          (@eps ||= {})[base] = [ eps, size, text.bytesize ]
          return text
        end
      end
      raise "#{base}: over the #{GZIP_BUDGET} byte gzip budget even at the coarsest tolerance (#{Zlib::Deflate.deflate(last, 9).bytesize})"
    end

    def stats = @eps || {}

    def render(base, cfg, eps)
      window = cfg[:window].map(&:to_f)
      pr = projection_of(base)
      @ctx = { base: base, cfg: cfg, window: window, pr: pr, eps: eps }
      areas, groups = cfg[:detail] == "historical" ? historical_areas : modern_areas(cfg)
      doc = {
        "v" => 1, "base" => base, "title_it" => cfg[:title_it], "fill_rule" => "evenodd",
        "projection" => pr.to_h, "viewBox" => [ 0, 0, WIDTH.to_i, pr.height.round(1) ], "box" => window, "crop" => cfg.fetch(:crop, true),
        "detail" => cfg[:detail], "tolerance" => eps, "reads" => reads_of(cfg)
      }
      doc["approximate"] = true if cfg[:detail] == "historical"
      doc["land"] = land_path if cfg[:detail] == "historical"
      doc["areas"] = areas.sort_by { |a| a["id"] }
      doc["groups"] = groups.sort_by { |g| g["id"] }
      doc["oceans"] = ocean_labels
      doc["water"] = lakes
      doc["lines"] = rivers
      doc["places"] = cfg[:detail] == "historical" ? historical_places : modern_places
      doc["graticule"] = graticule
      doc.delete("groups") if doc["groups"].empty?
      "// banco-maps@1 #{base}: generated by bin/build-maps from Natural Earth (public domain)#{cfg[:detail] == 'historical' ? ' and Pleiades (CC BY 3.0)' : ''}; see PROVENANCE.md. Do not edit.\n" \
        "export default #{JSON.generate(doc)};\n"
    end

    # Ids resolve PER BASE: the base says which table each collection of ids is read from. The ancient base
    # reads its areas in history/regions and its places in history/places, so "sicilia" the Roman province
    # (history/regions) is never confused with "sicilia" the Italian region (geo/names, read by the italy base).
    def reads_of(cfg)
      if cfg[:detail] == "historical"
        { "areas" => "history/regions", "places" => "history/places", "lines" => "geo/names", "oceans" => "geo/names" }
      else
        { "areas" => "geo/names", "groups" => "geo/names", "places" => "geo/names", "lines" => "geo/names", "oceans" => "geo/names" }
      end
    end

    # ---- geometry helpers -----------------------------------------------------------------

    def rings_of(geom)
      polys = geom["type"] == "Polygon" ? [ geom["coordinates"] ] : geom["coordinates"]
      polys.flat_map do |poly|
        poly.each_with_index.map { |ring, i| Geom.orient(ring[0...-1], i.zero?) }
      end
    end

    # lon/lat rings -> projected, clipped, simplified rings in viewBox units
    def prepare(rings)
      w = @ctx[:window]
      pr = @ctx[:pr]
      rings.filter_map do |ring|
        clipped = Geom.clip_ring(Geom.densify(ring, 2.0), w)
        next if clipped.empty?
        pts = Geom.clip_ring(Geom.densify(clipped, 2.0).map { |lon, lat| pr.project(lon, lat) }, pr.rect)
        next if pts.empty?
        s = Geom.simplify(pts, @ctx[:eps])
        s.size >= 3 ? s : nil
      end
    end

    # the area record from lon/lat rings; nil when nothing of it is in the window
    def area_record(id, kind, rings, keep_tiny: true)
      pr = @ctx[:pr]
      pts = prepare(rings)
      pts = pts.select { |r| Geom.area(r) >= 0.6 } unless keep_tiny && pts.size == 1
      if pts.empty?
        biggest = prepare(rings).max_by { |r| Geom.area(r) }
        return nil unless biggest
        pts = [ biggest ]
      end
      main = pts.max_by { |r| Geom.area(r) }
      ax, ay = Geom.anchor(main)
      x0, y0, x1, y1 = Geom.bbox(pts)
      { "id" => id, "kind" => kind, "d" => Geom.path(pts), "anchor" => [ ax.round(1), ay.round(1) ], "bbox" => [ x0, y0, x1, y1 ].map { |v| v.round(1) } }.tap { pr }
    end

    # in the window and inside the viewBox
    def inside_window?(lon, lat)
      w, s, e, n = @ctx[:window]
      return false unless lon >= w && lon <= e && lat >= s && lat <= n
      x, y = @ctx[:pr].project(lon, lat)
      x0, y0, x1, y1 = @ctx[:pr].rect
      x >= x0 && x <= x1 && y >= y0 && y <= y1
    end

    def xy(lon, lat) = @ctx[:pr].project(lon, lat).map { |v| v.round(1) }

    # ---- modern bases ---------------------------------------------------------------------

    def modern_areas(cfg)
      file = "ne_#{cfg[:res]}m_admin_0_countries"
      areas = []
      member_of = Hash.new { |h, k| h[k] = [] }
      italy_regions = cfg[:detail] == "regions" ? italy_region_rings : nil
      Tables.countries(file).each do |f|
        p = f["p"]
        id = Tables.country_id(p)
        next if italy_regions && id == "ITA"
        rec = area_record(id, p["TYPE"] == "Sovereign country" ? "country" : "territory", rings_of(f["g"]))
        next unless rec
        areas << rec
        key = CONTINENT_KEYS[p["CONTINENT"]]
        (BOTH_CONTINENTS[id] || [ key ]).compact.each { |k| member_of[k] << id }
      end
      groups = []
      if cfg[:detail] == "regions"
        recs = italy_regions.filter_map { |slug, rings| area_record(slug, "region", rings) }
        areas.concat(recs)
        groups << group_record("ITA", "country", recs.map { |r| r["id"] }, recs)
        member_of["europe"] << "ITA"
      end
      if cfg[:detail] == "continents"
        member_of.each do |key, ids|
          anchor = CONTINENT_ANCHORS[key]
          next unless anchor && inside_window?(*anchor)
          groups << { "id" => key, "kind" => "continent", "members" => ids.sort, "anchor" => xy(*anchor) }
        end
      else
        member_of.each do |key, ids|
          next unless CONTINENT_ANCHORS.key?(key)
          groups << { "id" => key, "kind" => "continent", "members" => ids.sort, "anchor" => xy(*CONTINENT_ANCHORS[key]) } if ids.any? && key == cfg[:title_it].then { |t| t && base_key(t) }
        end
      end
      [ areas, groups ]
    end

    def base_key(title) = CONTINENT_KEYS.values.find { |k| Tables::CONTINENTS[k][0] == title }

    def group_record(id, kind, members, recs)
      big = recs.max_by { |r| (r["bbox"][2] - r["bbox"][0]) * (r["bbox"][3] - r["bbox"][1]) }
      xs = recs.flat_map { |r| [ r["bbox"][0], r["bbox"][2] ] }
      ys = recs.flat_map { |r| [ r["bbox"][1], r["bbox"][3] ] }
      { "id" => id, "kind" => kind, "members" => members.sort, "anchor" => big["anchor"], "bbox" => [ xs.min, ys.min, xs.max, ys.max ] }
    end

    # {region slug => [lon/lat rings of its provinces, dissolved]}
    def italy_region_rings
      by_region = Hash.new { |h, k| h[k] = [] }
      Sources.read_checked("ne_10m_admin_1_states_provinces")["features"].each do |f|
        next unless f["p"]["adm0_a3"] == "ITA"
        name = Tables::ITALY_REGIONS[f["p"]["region"]] or raise "unknown Italian region #{f['p']['region'].inspect}"
        by_region[Tables.slug(name)].concat(rings_of(f["g"]))
      end
      by_region.transform_values { |rings| Geom.dissolve(rings) }
    end

    def modern_places
      Sources.read_checked("ne_110m_populated_places")["features"].filter_map do |f|
        lon, lat = f["g"]["coordinates"]
        next unless inside_window?(lon, lat)
        id = place_id(f["p"])
        x, y = xy(lon, lat)
        { "id" => id, "x" => x, "y" => y, "cap" => f["p"]["ADM0CAP"].to_f == 1.0 }
      end.sort_by { |p| p["id"] }
    end

    def place_id(p)
      @place_ids ||= {}
      @place_ids[p["NAMEASCII"] + p["ADM0_A3"]] ||= begin
        id = Tables.slug(p["NAMEASCII"])
        names.key?(id) && names[id]["kind"] == "city" && names[id]["name_en"] == p["NAME_EN"] ? id : "#{id}-#{p['ADM0_A3'].downcase}"
      end
    end

    # ---- the ancient Mediterranean --------------------------------------------------------

    def historical_areas
      areas = regions.filter_map do |id, r|
        rings = Geom.dissolve(r.fetch("units").flat_map { |u| unit_rings(u) })
        area_record(id, "region", rings)
      end
      [ areas, [] ]
    end

    def unit_rings(unit)
      @admin0 ||= Tables.countries("ne_50m_admin_0_countries").to_h { |f| [ Tables.country_id(f["p"]), f ] }
      @admin1 ||= Sources.read_checked("ne_10m_admin_1_states_provinces")["features"]
      if unit.include?("/")
        cc, name = unit.split("/", 2)
        feats = @admin1.select { |f| f["p"]["adm0_a3"] == cc && (f["p"]["name"] == name || f["p"]["region"] == name) }
        raise "region unit #{unit}: nothing in Natural Earth admin-1" if feats.empty?
        feats.flat_map { |f| rings_of(f["g"]) }
      else
        cc, box = unit.split("@", 2)
        feat = @admin0[cc] or raise "region unit #{unit}: no such country"
        rings = rings_of(feat["g"])
        return rings unless box
        b = box.split(",").map(&:to_f)
        rings.filter_map { |r| c = Geom.clip_ring(Geom.densify(r, 1.0), b); c.empty? ? nil : c }
      end
    end

    def land_path
      pts = Sources.read_checked("ne_50m_land")["features"].flat_map { |f| prepare(rings_of(f["g"])) }
      pts = pts.select { |r| Geom.area(r) >= 0.6 }
      Geom.path(pts)
    end

    def historical_places
      places.map do |id, p|
        x, y = xy(p["lon"], p["lat"])
        { "id" => id, "x" => x, "y" => y, "kind" => p["kind"] }
      end.select { |p| true }.sort_by { |p| p["id"] }
    end

    # ---- water, lines, labels -------------------------------------------------------------

    def lakes
      cfg = @ctx[:cfg]
      return [] if cfg[:lake_rank].zero? || cfg[:detail] == "historical" && false
      by_id = Hash.new { |h, k| h[k] = [] }
      Sources.read_checked("ne_#{cfg[:res]}m_lakes")["features"].each do |f|
        p = f["p"]
        next if p["scalerank"].to_i > cfg[:lake_rank]
        by_id[Tables.slug(p["name_en"] || p["name"] || "lake-#{by_id.size}")].concat(rings_of(f["g"]))
      end
      # an unnamed shape: lakes are not in the gazetteer
      by_id.sort.filter_map do |_, rings|
        pts = prepare(rings).select { |r| Geom.area(r) >= 4 }
        pts.empty? ? nil : { "d" => Geom.path(pts) }
      end
    end

    def rivers
      cfg = @ctx[:cfg]
      return [] if cfg[:river_rank].zero?
      by_id = Hash.new { |h, k| h[k] = [] }
      Sources.read_checked("ne_#{cfg[:res]}m_rivers_lake_centerlines")["features"].each do |f|
        p = f["p"]
        next if p["featurecla"] && p["featurecla"] != "River" && p["featurecla"] != "Lake Centerline"
        name = p["name_en"] || p["name"] or next
        next if cfg[:detail] == "historical" ? !HISTORIC_RIVERS.include?(name) : p["scalerank"].to_i > cfg[:river_rank]
        lines = f["g"]["type"] == "LineString" ? [ f["g"]["coordinates"] ] : f["g"]["coordinates"]
        lines.each do |line|
          Geom.clip_line(line, @ctx[:window]).each do |piece|
            pts = piece.map { |lon, lat| @ctx[:pr].project(lon, lat) }
            Geom.clip_line(pts, @ctx[:pr].rect).each { |part| by_id[Tables.slug(name)] << Geom.simplify(part, @ctx[:eps], closed: false) }
          end
        end
      end
      by_id.filter_map { |id, ls| ls.empty? ? nil : { "id" => id, "d" => Geom.path(ls, closed: false) } }.sort_by { |l| l["id"] }
    end

    def ocean_labels
      return [] if @ctx[:cfg][:detail] == "historical"
      Tables::OCEANS.filter_map do |id, (_, anchors)|
        pt = anchors.find { |lon, lat| inside_window?(lon, lat) }
        pt ? { "id" => id, "x" => xy(*pt)[0], "y" => xy(*pt)[1] } : nil
      end
    end

    def graticule
      w, s, e, n = @ctx[:window]
      pr = @ctx[:pr]
      parallel = lambda do |lat|
        next nil unless lat > s && lat < n
        pts = (0..((e - w) / 5.0).ceil).map { |i| pr.project([ w + i * 5.0, e ].min, lat) }
        Geom.path(Geom.clip_line(pts, pr.rect), closed: false)
      end
      meridian = lambda do |lon|
        next nil unless lon > w && lon < e
        pts = (0..((n - s) / 5.0).ceil).map { |i| pr.project(lon, [ s + i * 5.0, n ].min) }
        Geom.path(Geom.clip_line(pts, pr.rect), closed: false)
      end
      {
        "equator" => parallel.call(0), "tropics" => [ TROPIC, -TROPIC ].filter_map { |l| parallel.call(l) },
        "polar_circles" => [ 90 - TROPIC, -(90 - TROPIC) ].filter_map { |l| parallel.call(l) }, "greenwich" => meridian.call(0),
        "latitudes" => { "tropic" => TROPIC, "polar_circle" => (90 - TROPIC).round(1) }
      }.compact
    end

    # ---- the text files -------------------------------------------------------------------

    def provenance
      src = Sources.manifest
      <<~MD
        # banco-maps@1: provenance

        Built by `bin/build-maps` from the trimmed sources committed in `config/banco/data/geo/source/`
        (Natural Earth #{src['natural_earth_version']}, World Bank) and the tables `config/banco/data/geo/` and
        `config/banco/data/history/`. The build is offline and deterministic; `bin/build-maps --check` (and CI)
        say whether this directory equals the build.

        ## Sources and licences

        | Data | Used for | Licence | Upstream |
        |---|---|---|---|
        | Natural Earth #{src['natural_earth_version']} 1:110m and 1:50m (countries, land, lakes, rivers, populated places) and 1:10m admin-1 (Italy, Greece, Turkey) | every base: borders, coasts, lakes, rivers, capitals and cities, the twenty regions of Italy, the units the ancient regions are composed from | public domain, no attribution needed ("Made with Natural Earth" is courteous) | https://www.naturalearthdata.com/about/terms-of-use/ |
        | Pleiades gazetteer of ancient places, dump 2026-10-11 | `mediterraneo_antico`: the coordinates of #{places.size} places (`history/places`) | CC BY 3.0: (c) The Contributors of Pleiades, https://pleiades.stoa.org (attribution is on the card: "Luoghi: Pleiades") | https://pleiades.stoa.org/ |
        | World Bank World Development Indicators (area AG.SRF.TOTL.K2 from FAO, 2021; population SP.POP.TOTL, 2023) | `geo/countries` (not in the base files) | CC BY 4.0 | https://data.worldbank.org/ |

        ## Not used, and why

        - **Ancient World Mapping Center (AWMC) GeoJSON** (provinces of the Roman Empire in 200 CE and 60 BCE, coastlines).
          Its licence is the Open Database Licence 1.0 (ODbL, share-alike: a derived database must be offered under the
          same licence), and the province files are unnamed polygons and linework, so naming them would be drawing
          them by hand. The regions of `mediterraneo_antico` are instead composed from Natural Earth units
          (`history/regions`), each with its note on what is missing. If the operator wants the AWMC shapes, that is
          a D entry about the licence first.
        - The coast of `mediterraneo_antico` is today's coast (Natural Earth 1:50m land), not the ancient one: the
          deltas of the Nile, Po and Rhone and the harbours that have silted up are not drawn.

        ## Ids

        Ids resolve per base. The base's `reads` says which table each collection (`areas`, `groups`, `places`,
        `lines`, `oceans`) is read from, so the same id may mean two things in two bases ("sicilia" is the
        Italian region in `italy`, read in `geo/names`, and the Roman province in `mediterraneo_antico`, read in
        `history/regions`). Within a base every id is unique. A base carries no names: the Italian name is
        fetched from the server after the answer in select mode.

        ## Approximate

        The regions of `mediterraneo_antico` are approximations: whole modern countries or provinces, or a modern
        country cut by a box (`history/regions` says which, with a line on what the region misses). The template
        prints "Confini approssimativi" on every such map. A region is checked against a published atlas page by a
        second session and by the teacher in the topic review before a lesson depends on it.

        ## Files

        One module per base (`export default {...}`; fill rule evenodd): areas with `d` (path), `anchor` and `bbox`,
        groups (continents, Italy), oceans, lakes (`water`), rivers (`lines`), cities (`places`), the graticule
        (equator, tropics at #{TROPIC} degrees, polar circles, Greenwich) and the projection (`type`, `scale`, `tx`,
        `ty`: x = tx + scale * ex, y = ty - scale * ey; `type` is the authority and is one of `equal_earth` (the world
        and the continents), `lambert_azimuthal` (azimuthal equal-area, with `pole` north or south, for the poles) or
        `mercator` (the ancient Mediterranean)). `test/fixtures/maps/projection_vectors.json` holds sample points for the
        JavaScript twin of the projection. SHA256SUMS lists every file.
      MD
    end

    def licence
      <<~TXT
        banco-maps@1: licences of the data in the .js files

        Natural Earth (https://www.naturalearthdata.com/): all versions of Natural Earth raster and vector map data
        are in the public domain. You may use the maps in any manner, including modifying the content and design,
        electronic dissemination, and offset printing. No permission is needed; crediting is unnecessary.
        "Made with Natural Earth. Free vector and raster map data @ naturalearthdata.com."

        Pleiades (https://pleiades.stoa.org/), used by mediterraneo_antico.js only:
        Copyright (c) The Contributors. Sharing and remixing permitted under the terms of the
        Creative Commons Attribution 3.0 License (CC BY 3.0), https://creativecommons.org/licenses/by/3.0/.
        The coordinates of the places are from the Pleiades dump of 2026-10-11; the Italian names and the
        choice of places are ours.

        The paths, anchors and boxes in the files are our own derivative work of the sources above.
      TXT
    end

    def readme
      <<~TXT
        banco-maps@1: the bases of the lesson `map` (one module per base), built by bin/build-maps.
        Loaded only by a card with a map. See PROVENANCE.md for the sources, the licences and what is approximate.
      TXT
    end
  end
end
