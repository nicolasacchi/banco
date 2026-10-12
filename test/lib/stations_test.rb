require "test_helper"
require "open3"

# geo/stations (T6, WAVE2 1.9, D-269): the vetted climate normals 1991-2020 of the stations a climograph can name, and the second table
# (geo/stations_expected: a summary of an independent computation) compared with what our code derives from them.
class StationsTest < ActiveSupport::TestCase
  V = Lessons::VettedData
  STATIONS = V.table("geo/stations").fetch("stations")
  EXPECTED = V.table("geo/stations_expected").fetch("expected")
  Climo = Lessons::Diagrams::Climograph

  def num(text) = Lessons::Num.parse(text)

  def stats(row) = Climo.stats(row["temp"].map { |v| num(v) }, row["precip"].map { |v| num(v) })

  test "both tables are valid against their schemas, and the second covers exactly the stations of the first" do
    assert_empty V.errors("geo/stations")
    assert_empty V.errors("geo/stations_expected")
    assert_equal STATIONS.keys.sort, EXPECTED.keys.sort
    assert_operator STATIONS.size, :>=, 20
  end

  test "every station has twelve months inside the climograph's ranges, a place, a source and a period" do
    names = STATIONS.values.map { |r| r["name_it"] }
    assert_equal names.uniq.size, names.size, "an Italian name is used once"
    STATIONS.each do |id, row|
      assert_equal 12, row["temp"].size, id
      assert_equal 12, row["precip"].size, id
      row["temp"].each { |t| assert_includes (-60..45), num(t), "#{id} temp #{t}" }
      row["precip"].each { |p| assert_includes (0..1500), num(p), "#{id} precip #{p}" }
      assert_includes (-90..90), num(row["lat"]), id
      assert_includes (-180..180), num(row["lon"]), id
      assert_includes (-500..9000), num(row["alt_m"]), id
      assert_equal "1991-2020", row["period"], id
      assert_match(/\A(WMO|Environment and Climate Change Canada)/, row["source"], id)
      assert_match(/\A[A-Za-zÀ-ÿ' ]+\z/, row["name_it"], id)
    end
  end

  test "the seasons sit where the latitude says: the warmest month of a far southern station is in summer there, of a far northern one in July or August" do
    STATIONS.each do |id, row|
      lat = num(row["lat"])
      warmest = stats(row)[:warmest]
      coldest = stats(row)[:coldest]
      if lat < -25
        assert_includes [ 12, 1, 2, 3 ], warmest, "#{id}: warmest month #{warmest}"
        assert_includes [ 5, 6, 7, 8, 9 ], coldest, "#{id}: coldest month #{coldest}"
      elsif lat > 40
        assert_includes [ 6, 7, 8 ], warmest, "#{id}: warmest month #{warmest}"
        assert_includes [ 12, 1, 2 ], coldest, "#{id}: coldest month #{coldest}"
      end
    end
  end

  test "the second table agrees with what our code derives: the annual mean, the annual total, the extremes and the arid months" do
    STATIONS.each do |id, row|
      want = EXPECTED.fetch(id)
      s = stats(row)
      band = want["temp_band"] ? num(want["temp_band"]) : Rational(1, 2)
      assert_operator (s[:mean] - num(want["annual_temp"])).abs, :<=, band, "#{id}: annual mean #{s[:mean].to_f} against #{want['annual_temp']}"
      total = num(want["annual_precip"])
      assert_operator (s[:total] - total).abs, :<=, [ Rational(20), total / 10 ].max, "#{id}: annual total #{s[:total].to_f} against #{want['annual_precip']}"
      # the extremes: the same month, or a month within 0,3 degrees of ours (an equatorial station has two near-equal months)
      assert_operator (num(row["temp"][want["warmest"] - 1]) - s[:tmax]).abs, :<=, Rational(3, 10), "#{id}: warmest month #{want['warmest']} against #{s[:warmest]}"
      assert_operator (num(row["temp"][want["coldest"] - 1]) - s[:tmin]).abs, :<=, Rational(3, 10), "#{id}: coldest month #{want['coldest']} against #{s[:coldest]}"
      differs = Array(want["arid_differs"])
      assert_equal want["arid"].sort - differs, s[:arid].sort - differs, "#{id}: arid months outside the ones named in arid_differs"
      assert_operator differs.size, :<=, 2, "#{id}: at most two arid months may differ between the sources"
      assert_equal true, band <= 2, "#{id}: a temperature band above two degrees is no cross-check" if want["temp_band"]
      assert want["temp_band_why"], "#{id}: a wider band says why" if want["temp_band"]
    end
  end

  test "the stations that lessons rely on say what the lessons say" do
    arid = ->(id) { stats(STATIONS.fetch(id))[:arid] }
    assert_equal (5..9).to_a, arid.("brasilia"), "Brasília: a dry winter, May to September"
    assert_equal [ 1, 2, 3, 4, 5, 11, 12 ], arid.("mumbai"), "Mumbai: five months with almost no rain, then the monsoon"
    assert_equal (1..12).to_a, arid.("cairo")
    assert_empty arid.("singapore")
    assert_empty arid.("belem")
    assert_empty arid.("moscow")
    assert_equal [ 8 ], arid.("manaus"), "Manaus has one borderline month: not a station for 'equatorial' (the draft's own warning)"
    assert_operator num(STATIONS.fetch("winnipeg")["temp"].first), :<, -15
    assert_operator stats(STATIONS.fetch("dalanzadgad"))[:total], :<, 250, "the Gobi is a desert by its total"
    assert_operator stats(STATIONS.fetch("mumbai"))[:total], :>, 2000
    assert_equal 6, stats(STATIONS.fetch("tokyo"))[:warmest] + stats(STATIONS.fetch("tokyo"))[:coldest] - 3, "Tokyo: August and January"
  end

  test "the Italian label puts the country after the place and leaves it out when they are the same" do
    assert_equal "Brasília (Brasile)", Climo.label_of(STATIONS.fetch("brasilia"))
    assert_equal "Singapore", Climo.label_of(STATIONS.fetch("singapore"))
    assert_equal "Città del Capo (Sudafrica)", Climo.label_of(STATIONS.fetch("cape_town"))
  end

  test "the compiled JS module equals the table" do
    out, status = Open3.capture2e(Rails.root.join("bin/build-lesson-data").to_s, "--check")
    assert status.success?, out
  end
end
