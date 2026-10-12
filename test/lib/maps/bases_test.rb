require "test_helper"
require "open3"
require "json_schemer"

# T5, day one: bin/build-maps makes public/vendor/banco-maps@1/ from sourced open data; the tables it
# reads (geo/names, geo/countries, history/places, history/regions) are vetted data (W2-D08).
class MapsBasesTest < ActiveSupport::TestCase
  DIR = Rails.root.join("public/vendor/banco-maps@1")
  DATA = Rails.root.join("config/banco/data")
  BASES = Maps::Builder::BASES.keys
  NAMES = YAML.safe_load_file(DATA.join("geo/names.yml")).fetch("names")
  PLACES = YAML.safe_load_file(DATA.join("history/places.yml")).fetch("places")
  REGIONS = YAML.safe_load_file(DATA.join("history/regions.yml")).fetch("regions")

  def self.base(name) = (@bases ||= {})[name] ||= JSON.parse(DIR.join("#{name}.js").read.sub(/\A.*?export default /m, "").sub(/;\s*\z/, ""))
  def base(name) = self.class.base(name)

  def self.rebuilt = @rebuilt ||= Maps::Builder.new.build_all

  def schema_errors(schema, data)
    JSONSchemer.schema(Rails.root.join(schema).read.then { |t| JSON.parse(t) }).validate(data).map { |e| e["error"] }
  end

  test "the directory has one module per base and the text files" do
    assert_equal (BASES.map { |b| "#{b}.js" } + %w[LICENSE PROVENANCE.md README.txt SHA256SUMS]).sort, DIR.children.map { |c| c.basename.to_s }.sort
    assert_equal %w[arctic antarctic europe italy mediterraneo_antico world].sort, (%w[arctic antarctic europe italy mediterraneo_antico world] & BASES).sort
    assert_equal %w[africa asia north_america south_america oceania], (BASES & %w[africa asia north_america south_america oceania]).sort_by { |b| %w[africa asia north_america south_america oceania].index(b) }
  end

  test "the build is deterministic: two builds are byte for byte the same" do
    second = Maps::Builder.new.build_all
    assert_equal self.class.rebuilt.keys, second.keys
    self.class.rebuilt.each { |name, text| assert_equal text, second[name], "#{name} differs between two builds" }
  end

  test "the committed files equal the build (bin/build-maps --check)" do
    out, status = Open3.capture2e(Rails.root.join("bin/build-maps").to_s, "--check")
    assert status.success?, out
    self.class.rebuilt.each { |name, text| assert_equal text, DIR.join(name).read, "#{name} is not the build" }
  end

  test "file sizes: every base is at most 60 KB gzipped and none is empty; the whole directory stays small" do
    BASES.each do |b|
      raw = DIR.join("#{b}.js").read
      gz = Zlib::Deflate.deflate(raw, 9).bytesize
      assert_operator gz, :<=, 60_000, "#{b} is #{gz} bytes gzipped"
      assert_operator gz, :>, 1_000, "#{b} looks empty"
    end
    total = BASES.sum { |b| Zlib::Deflate.deflate(DIR.join("#{b}.js").read, 9).bytesize }
    assert_operator total, :<, 250_000
  end

  test "licences: public domain for Natural Earth, CC BY for Pleiades, and AWMC left out with its reason" do
    licence = DIR.join("LICENSE").read
    assert_includes licence, "public domain"
    assert_includes licence, "Creative Commons Attribution 3.0"
    assert_includes licence, "pleiades.stoa.org"
    prov = DIR.join("PROVENANCE.md").read
    assert_includes prov, "Natural Earth"
    assert_includes prov, "public domain"
    assert_includes prov, "Pleiades"
    assert_includes prov, "CC BY 3.0"
    assert_includes prov, "World Bank"
    assert_match(/Ancient World Mapping Center.*ODbL/m, prov)
    assert_includes prov, "Not used, and why"
    assert_includes prov, "Confini approssimativi"
    assert_includes base("mediterraneo_antico").to_h.to_s, "approximate" # the flag is in the file
    assert_equal true, base("mediterraneo_antico")["approximate"]
    assert_match(/Pleiades \(CC BY 3\.0\)/, DIR.join("mediterraneo_antico.js").read.lines.first)
    refute_match(/Pleiades/, DIR.join("world.js").read.lines.first)
  end

  test "every source file is listed with its upstream address, checksum and licence, and the trimmed files match" do
    manifest = Maps::Sources.manifest
    assert_equal "v5.1.2", manifest["natural_earth_version"]
    on_disk = Dir.children(Maps::Sources::DIR).grep(/\.json\.gz\z/).map { |f| f.delete_suffix(".json.gz") }
    assert_equal on_disk.sort, manifest["files"].keys.sort
    manifest["files"].each do |name, f|
      assert_match(%r{\Ahttps://}, f["url"], name)
      assert_match(/\A\h{64}\z/, f["upstream_sha256"], name)
      assert_match(/public domain|CC BY 4\.0/, f["licence"], name)
      assert_equal f["sha256"], Digest::SHA256.file(Maps::Sources.path(name)).hexdigest, "#{name} differs from sources.yml"
    end
    assert_includes manifest["files"]["ne_50m_admin_0_countries"]["url"], "natural-earth-vector/v5.1.2"
  end

  test "the build does not need the network" do
    source = Rails.root.join("lib/maps/builder.rb").read + Rails.root.join("lib/maps/geom.rb").read
    refute_match(/Net::HTTP|open-uri|URI\(/, source)
  end

  test "the four tables are valid against their schemas" do
    {
      "geo/names" => "names", "geo/countries" => "countries", "history/places" => "places",
      "history/regions" => "regions", "history/places_expected" => "places_expected"
    }.each do |table, _|
      data = YAML.safe_load_file(DATA.join("#{table}.yml"))
      assert_empty schema_errors("config/banco/data/#{table}.schema.json", data), table
    end
  end

  test "every id in a base resolves: countries, regions, rivers, cities in geo/names; places and regions in history" do
    BASES.each do |b|
      d = base(b)
      if d["detail"] == "historical"
        d["areas"].each { |a| assert REGIONS.key?(a["id"]), "#{b}: region #{a['id']} is not in history/regions" }
        d["places"].each { |p| assert PLACES.key?(p["id"]), "#{b}: place #{p['id']} is not in history/places" }
        assert_equal REGIONS.keys.sort, d["areas"].map { |a| a["id"] }.sort, "every region is drawn"
        assert_equal PLACES.keys.sort, d["places"].map { |p| p["id"] }.sort, "every place is drawn"
      else
        d["areas"].each { |a| assert NAMES.key?(a["id"]), "#{b}: #{a['id']} is not in geo/names" }
        (d["groups"] || []).each do |g|
          assert NAMES.key?(g["id"]), "#{b}: group #{g['id']} is not in geo/names"
          g["members"].each { |m| assert NAMES.key?(m), "#{b}: member #{m} of #{g['id']} is not in geo/names" }
          assert_equal (g["members"] & d["areas"].map { |a| a["id"] }), g["members"], "#{b}: group #{g['id']} names an area that is not drawn"
        end
        d["places"].each { |p| assert_equal "city", NAMES.dig(p["id"], "kind"), "#{b}: place #{p['id']}" }
        d["oceans"].each { |o| assert_equal "ocean", NAMES.dig(o["id"], "kind"), "#{b}: ocean #{o['id']}" }
      end
      d["lines"].each { |l| assert_equal "river", NAMES.dig(l["id"], "kind"), "#{b}: line #{l['id']} is not a river in geo/names" }
      ids = d["areas"].map { |a| a["id"] } + (d["groups"] || []).map { |g| g["id"] }
      assert_equal ids.uniq, ids, "#{b}: an id is used twice"
    end
  end

  test "every name has Italian text, a source, and every country has the three languages" do
    NAMES.each do |id, n|
      assert_predicate n["name_it"].to_s.strip, :present?, id
      assert_predicate n["source"].to_s.strip, :present?, id
    end
    NAMES.select { |_, n| n["kind"] == "country" }.each do |id, n|
      assert n["name_en"].present? && n["name_es"].present?, "#{id} lacks name_en or name_es"
    end
    assert_operator NAMES.count { |_, n| n["kind"] == "country" }, :>=, 190
  end

  test "the exonym rule: the Italian name the school books use" do
    assert_equal "Brasile", NAMES.dig("BRA", "name_it")
    assert_equal "Stati Uniti d'America", NAMES.dig("USA", "name_it")
    assert_equal "San Paolo", NAMES.dig("sao-paulo", "name_it")
    assert_equal "Città del Capo", NAMES.dig("cape-town", "name_it")
    assert_equal "Rio delle Amazzoni", NAMES.dig("amazon", "name_it")
    assert_equal "Danubio", NAMES.dig("danube", "name_it")
    assert_equal "Reno", NAMES.dig("rhine", "name_it")
    assert_equal "Puglia", NAMES.dig("puglia", "name_it")
    assert_equal "Sicilia", NAMES.dig("sicilia", "name_it")
    assert_equal "Cipro", NAMES.dig("CYP", "name_it")
    overrides = YAML.safe_load_file(DATA.join("geo/names_overrides.yml")).fetch("overrides")
    overrides.each { |id, o| assert NAMES.key?(id), "override #{id} names nobody"; assert_equal o["name_it"], NAMES[id]["name_it"]; assert o["why"].present? }
  end

  test "the twenty regions of Italy are in the italy base, and Italy is one group of them" do
    d = base("italy")
    regions = d["areas"].select { |a| a["kind"] == "region" }
    assert_equal 20, regions.size
    assert_equal regions.map { |r| r["id"] }.sort, d["groups"].find { |g| g["id"] == "ITA" }["members"]
    assert_nil d["areas"].find { |a| a["id"] == "ITA" }
  end

  test "the continents are groups of the world base, with Russia in both Europe and Asia" do
    g = base("world")["groups"].to_h { |x| [ x["id"], x["members"] ] }
    assert_equal %w[africa antarctica asia europe north_america oceania south_america], g.keys.sort
    assert_includes g["europe"], "RUS"
    assert_includes g["asia"], "RUS"
    assert_includes g["south_america"], "BRA"
    assert_includes g["africa"], "EGY"
    assert_includes g["asia"], "TUR"
  end

  test "countries table: area and population carry a year and a source; known values are right" do
    c = YAML.safe_load_file(DATA.join("geo/countries.yml")).fetch("countries")
    assert_equal 8_515_770, c.dig("BRA", "area_km2")
    assert_equal 302_068, c.dig("ITA", "area_km2")
    assert_equal 2021, c.dig("BRA", "area_year")
    assert_equal 2023, c.dig("BRA", "population_year")
    assert_operator c.dig("BRA", "population"), :>, 200_000_000
    assert_operator c.dig("ITA", "population"), :>, 55_000_000
    assert_match(/World Bank/, c.dig("ITA", "area_source"))
    c.each_key { |id| assert NAMES.key?(id), "#{id} has no name" }
    assert_empty NAMES.select { |_, n| n["kind"] == "country" }.keys - c.keys, "a country without a countries row"
    assert_operator c.count { |_, r| r["area_km2"] }, :>, 180
  end

  test "history/places: every place has its Pleiades id, source and licence; ids are unique; about sixty places" do
    assert_operator PLACES.size, :>=, 60
    assert_equal PLACES.values.map { |p| p["pleiades"] }.uniq.size, PLACES.size
    PLACES.each do |id, p|
      assert_includes p["source"], "pleiades.stoa.org/places/#{p['pleiades']}", id
      assert_includes p["source"], "CC BY 3.0", id
    end
    assert_includes YAML.safe_load_file(DATA.join("history/places.yml"))["licence"], "CC BY 3.0"
  end

  test "history/places agrees with the independent table of where the places are" do
    expected = YAML.safe_load_file(DATA.join("history/places_expected.yml")).fetch("expected")
    assert_equal PLACES.keys.sort, expected.keys.sort, "the two tables list different places"
    PLACES.each do |id, p|
      lat, lon, tol = expected.fetch(id)
      assert_in_delta lat, p["lat"], tol, "#{id}: latitude differs from the second table"
      assert_in_delta lon, p["lon"], tol, "#{id}: longitude differs from the second table"
    end
  end

  test "every historical place is inside the base's viewBox and every known battle and city of the plan is there" do
    d = base("mediterraneo_antico")
    w, h = d["viewBox"][2], d["viewBox"][3]
    d["places"].each { |p| assert p["x"].between?(0, w) && p["y"].between?(0, h), "#{p['id']} is outside the base" }
    %w[roma cartagine atene alessandria bisanzio gerusalemme ravenna milano azio canne zama alesia filippi teutoburgo ancira rimini rubicone vallo-di-adriano].each do |id|
      assert PLACES.key?(id), "#{id} missing from history/places"
    end
  end

  test "history/regions: about forty regions or fewer, each with its units and a note on what it misses; every unit resolves" do
    assert_operator REGIONS.size, :>=, 30
    %w[italia gallia-cisalpina sicilia sardegna-corsica hispania gallia britannia germania rezia-norico pannonia dacia macedonia asia-provincia siria giudea egitto cirenaica numidia mauretania armenia mesopotamia partia].each do |id|
      assert REGIONS.key?(id), id
    end
    REGIONS.each { |id, r| assert_operator r["why"].size, :>, 20, id; assert_predicate r["name_it"], :present?, id }
    d = base("mediterraneo_antico")
    assert_equal REGIONS.keys.sort, d["areas"].map { |a| a["id"] }.sort
    d["areas"].each { |a| assert_match(/\AM/, a["d"], a["id"]); assert_equal 4, a["bbox"].size }
  end

  test "an area is not empty and its label anchor and box lie inside the viewBox" do
    BASES.each do |b|
      d = base(b)
      w, h = d["viewBox"][2], d["viewBox"][3]
      (d["areas"]).each do |a|
        assert_operator a["d"].size, :>, 5, "#{b}/#{a['id']}"
        x, y = a["anchor"]
        assert x.between?(-1, w + 1) && y.between?(-1, h + 1), "#{b}/#{a['id']} anchor #{a['anchor']} outside #{w}x#{h}"
        x0, y0, x1, y1 = a["bbox"]
        assert x0 <= x1 && y0 <= y1 && x0 >= -1 && y0 >= -1 && x1 <= w + 1 && y1 <= h + 1, "#{b}/#{a['id']} bbox #{a['bbox']}"
      end
      d["places"].each { |p| assert p["x"].between?(0, w) && p["y"].between?(0, h), "#{b}/#{p['id']} outside" }
    end
  end

  test "the modern bases carry the graticule: equator and tropics where they fall, the same latitudes everywhere" do
    sa = base("south_america")["graticule"]
    assert sa["equator"]
    assert_equal 1, sa["tropics"].size # the Tropic of Capricorn; Cancer is north of the window
    assert_equal 23.4, sa["latitudes"]["tropic"]
    assert_equal 2, base("world")["graticule"]["tropics"].size
    assert_equal 2, base("world")["graticule"]["polar_circles"].size
    assert base("world")["graticule"]["greenwich"]
    assert_nil base("arctic")["graticule"]["equator"]
  end

  test "the projection vectors match the bases and a point is where the base says" do
    vec = JSON.parse(Rails.root.join("test/fixtures/maps/projection_vectors.json").read)
    BASES.each do |b|
      assert_equal base(b)["projection"], vec["bases"][b]["projection"], b
      pr = Maps::Geom::Projection.new(base(b)["projection"]["type"], base(b)["projection"]["scale"], base(b)["projection"]["tx"], base(b)["projection"]["ty"], 1000.0, 0)
      vec["bases"][b]["points"].each do |lon, lat, x, y|
        px, py = pr.project(lon, lat)
        assert_in_delta x, px, 0.05, "#{b} #{lon},#{lat}"
        assert_in_delta y, py, 0.05, "#{b} #{lon},#{lat}"
      end
    end
    # Rome on the Italy base lies where Rome's pin is on the base (cities are projected by the same function)
    rome = base("italy")["places"].find { |p| p["id"] == "rome" }
    pr = base("italy")["projection"]
    x, y = Maps::Geom::Projection.new(pr["type"], pr["scale"], pr["tx"], pr["ty"], 1000.0, 0).project(12.48, 41.89)
    assert_in_delta rome["x"], x, 2.5
    assert_in_delta rome["y"], y, 2.5
  end

  test "north is up and east is right on the Italy base: Rome is north of Tunis and west of Sarajevo" do
    d = base("italy")
    id = ->(i) { d["places"].find { |p| p["id"] == i } }
    assert_operator id.call("rome")["y"], :<, id.call("tunis")["y"]
    assert_operator id.call("rome")["x"], :<, id.call("sarajevo")["x"]
  end

  test "VendorTest's checksum rule holds for this directory: every file listed once, in the sha256sum format" do
    sums = DIR.join("SHA256SUMS").read.lines.map { |l| l.strip.split(/\s+/, 2) }
    assert_equal sums.map(&:last).sort, (DIR.children.map { |c| "./#{c.basename}" } - [ "./SHA256SUMS" ]).sort
    sums.each { |sha, f| assert_equal sha, Digest::SHA256.file(DIR.join(f)).hexdigest, f }
  end
end
