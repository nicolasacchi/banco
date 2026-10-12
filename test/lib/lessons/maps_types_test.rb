require "test_helper"

# The maps family (T5, W2-1, D-272): map, insolation and cross_section against their vectors, the Ruby half. The browser's half is
# app/javascript/lesson/test/maps.test.mjs; both read test/fixtures/diagrams/types/TYPE.json, so the two implementations say the same words,
# list the same targets in the same order and refuse the same figures at the same JSON pointer.
class MapsTypesTest < ActiveSupport::TestCase
  DIR = Rails.root.join("test/fixtures/diagrams/types")
  TYPES = { "map" => Lessons::Diagrams::Map, "insolation" => Lessons::Diagrams::Insolation, "cross_section" => Lessons::Diagrams::CrossSection }.freeze
  DOCS = TYPES.keys.to_h { |t| [ t, JSON.parse(DIR.join("#{t}.json").read) ] }.freeze

  DOCS.each do |type, doc|
    mod = TYPES.fetch(type)
    doc["vectors"].each do |v|
      next if v["schema"] == "invalid"

      test "#{v['name']}: semantic, words, targets" do
        found = Lessons::Diagrams.check(v["data"], subject: v["subject"])
        if v["semantic"] == "ok"
          assert_empty found.map(&:to_h), v["name"]
          n = v["data"]["states"].is_a?(Array) && v["data"]["states"].any? ? v["data"]["states"].size : 1
          v["describe"].each_with_index { |text, i| assert_equal text, mod.describe(v["data"], state: i), "describe #{i}" }
          v["printed"].each_with_index { |list, i| assert_equal list, mod.printed(v["data"], i), "printed #{i}" }
          assert_equal n, v["describe"].size
          assert_equal v.fetch("reachable", []), mod.reachable(v["data"]), "reachable"
          (v["targets"] || {}).each do |set, ids|
            assert_equal ids, mod.targets(v["data"], set), "targets #{set}"
            assert_equal v["neutral"][set], mod.neutral(v["data"], set), "neutral #{set}"
            assert_equal v["served_select"][set], mod.served(v["data"], mode: :select, set: set), "served select #{set}"
          end
        else
          f = found.first
          assert_not_nil f, "#{v['name']} should be refused"
          assert_equal [ v["semantic"]["code"], v["semantic"]["path"] ], [ f.code, f.path ], v["name"]
        end
      end
    end
  end

  test "a select figure serves nothing that marks or names a candidate (L3)" do
    DOCS.each do |type, doc|
      doc["vectors"].each do |v|
        next unless v["served_select"]

        v["served_select"].each do |set, served|
          json = served.to_json
          assert_no_match(/"(role|pattern|op_it|states|features|lapse|stepper|highlight|routes|regions_since|slider)":/, json, "#{v['name']} #{set}")
          labels = served.fetch("belts", []).map { |b| b["label_it"] }.uniq
          assert_operator labels.size, :<=, 1, "#{v['name']}: every belt has the same neutral label"
          served["points"].to_a.each { |pt| assert_nil pt["label_it"] } if type == "map"
          v["targets"][set].each { |id| assert_not_includes json.gsub(/"candidates":\[[^\]]*\]/, "").gsub(/"id":"[^"]*"/, ""), id, "#{v['name']}: #{id}" } if type == "map" && set == "areas"
          assert_not_includes served.keys, "states"
        end
      end
    end
  end

  test "the student's projection of a map keeps the declared fields with the states merged" do
    v = DOCS["map"]["vectors"].find { |x| x["name"] == "map-south-america-core" }
    out = Lessons::StudentBody.diagram(v["data"])
    assert_equal "south_america", out["base"]
    assert_equal 2, out["states"].size
    assert_equal [ { "id" => "amazon" } ], out["states"][0]["lines"]
    assert_equal [], out["states"][1]["lines"]
    assert_equal "Il fiume", out["states"][0]["op_it"]
  end

  test "ids resolve per base: sicilia is a region of Italy and a Roman province, never confused" do
    italy = Maps::Base.read("italy")
    ancient = Maps::Base.read("mediterraneo_antico")
    assert_equal "Sicilia", Maps::Base.name_of(italy, "areas", "sicilia")
    assert_equal "Sicilia", Maps::Base.name_of(ancient, "areas", "sicilia")
    assert_equal "history/regions", ancient["reads"]["areas"]
    assert_equal "geo/names", italy["reads"]["areas"]
    assert_nil Maps::Base.name_of(ancient, "areas", "BRA"), "a modern country is not a region of the ancient base"
  end

  test "reading order is north to south, then west to east, then the id" do
    d = Maps::Base.read("south_america")
    assert_equal [ 2, 1, "a" ], Maps::Base.reading_key(1.4, 2.4, "a")
    ids = Lessons::Diagrams::Map.targets({ "type" => "map", "base" => "south_america", "candidates" => %w[ARG BRA PER VEN] }, "areas")
    assert_equal %w[VEN PER BRA ARG], ids
    assert_equal "a nord-ovest", Maps::Base.compass(d, 10, 10)
    assert_equal "al centro", Maps::Base.compass(d, 500, d["viewBox"][3] / 2)
    assert_equal "in alto a sinistra", Maps::Base.compass(Maps::Base.read("arctic"), 10, 10)
  end

  test "the numbers and words: one decimal rounds half away from zero, a comma, a proper minus" do
    gf = Lessons::Diagrams::GeoFormat
    assert_equal "1,3", gf.fmt1f(1.25)
    assert_equal "2,0", gf.fmt1f(1.96)
    assert_equal "−4", gf.fmt1(Rational(-4), trim: true)
    assert_equal "26,0", gf.fmt1(Rational(26))
    assert_equal "0,1", gf.fmt1(Rational(5, 100)) # half away from zero
    assert_equal "−0,1", gf.fmt1(Rational(-5, 100))
    assert_equal "23,4° nord", gf.lat_word(Rational(234, 10))
    assert_equal "51,1° ovest", gf.lon_word(Rational(-511, 10))
    assert_equal "0°", gf.lat_word(Rational(0))
    assert_equal "133 a.C.", gf.year_word(-133)
    assert_equal "14 d.C.", gf.year_word(14)
    assert_equal "a, b e c", gf.list_it(%w[a b c])
  end

  test "insolation: the spread is 1 over the cosine of the angle from the Sun, printed with one decimal" do
    i = Lessons::Diagrams::Insolation
    assert_equal "1,0", i.spread_str(Rational(0), Rational(0))
    assert_equal "1,2", i.spread_str(Rational(30), Rational(0))
    assert_equal "2,0", i.spread_str(Rational(60), Rational(0))
    assert_equal "8,7", i.spread_str(Rational(60), Rational(-234, 10))
    assert_equal "1,0", i.spread_str(Rational(234, 10), Rational(234, 10))
    assert_equal (-80..80).step(10).to_a.map { |v| Rational(v) }.select { |v| (v - Rational(-234, 10)).abs <= 85 }, i.stepper_values(Rational(-234, 10))
  end

  test "cross_section: the exaggeration is the largest nice number that keeps the drawing half as high as wide, and the temperature is exact" do
    c = Lessons::Diagrams::CrossSection
    v = DOCS["cross_section"]["vectors"].find { |x| x["name"] == "cross_section-volcano" }["data"]
    assert_equal 20, c.exaggeration(v)
    assert_equal "altezze esagerate 20 volte", c.exaggeration_text(v)
    assert_in_delta 0.5, c.aspect(v), 1e-9
    assert_equal "26 °C", c.temp_str(v, Rational(0))
    assert_equal "14 °C", c.temp_str(v, Rational(2000))
    assert_equal "−4 °C", c.temp_str(v, Rational(5000))
    steep = { "x" => { "to" => "10", "unit" => "m" }, "points" => [ %w[0 0], %w[10 5] ] }
    assert_equal 1, c.exaggeration(steep), "a steep section is not exaggerated"
    assert_equal "altezze in scala", c.exaggeration_text(steep)
  end

  test "the map names no coordinate of a historical base and every id in the vectors resolves" do
    ancient = Maps::Base.read("mediterraneo_antico")
    assert_equal true, ancient["approximate"]
    DOCS["map"]["vectors"].select { |v| v["data"]["base"] == "mediterraneo_antico" && v["semantic"] == "ok" }.each do |v|
      assert_not v["data"].key?("points"), v["name"]
      assert_not v["data"].key?("bands"), v["name"]
    end
  end
end
