require "test_helper"
require_relative "../../support/lesson2_fixtures"

# T6, the chart family on the Ruby side: climograph, seats and bar_model against their vector files (test/fixtures/diagrams/types/TYPE.json,
# the semantic, printed, values, reachable and served columns) and the computations against the shared vectors (climate.json, seats.json).
# The browser twins run the same files in app/javascript/lesson/test/chart_types.test.mjs.
class LessonsChartTypesTest < ActiveSupport::TestCase
  DIR = Rails.root.join("test/fixtures/diagrams/types")
  FILES = %w[climograph seats bar_model].to_h { |t| [ t, JSON.parse(DIR.join("#{t}.json").read) ] }.freeze
  Diag = Lessons::Diagrams

  FILES.each do |type, doc|
    doc["vectors"].select { |v| v["schema"] == "valid" }.each do |vec|
      test "semantic column: #{vec['name']}" do
        found = Diag.check(vec["data"], subject: vec["subject"])
        if vec["semantic"] == "ok"
          assert_empty found.map(&:to_h), vec["name"]
        else
          assert found.any? { |f| f.code == vec["semantic"]["code"] && f.path == vec["semantic"]["path"] },
                 "#{vec['name']}: expected #{vec['semantic'].inspect}, got #{found.map { |f| [ f.code, f.path ] }.inspect}"
        end
      end

      next unless vec["semantic"] == "ok"

      test "#{type} serves #{vec['name']} without a finding of the schema and with nothing a student must not have" do
        served = Lessons::StudentBody.diagram(vec["data"])
        assert_equal type, served["type"]
        Array(vec["served_null"]).each do |pointer|
          assert_nil served.dig(*pointer.split("/").drop(1).map { |k| k.match?(/\A\d+\z/) ? k.to_i : k }), "#{vec['name']}: #{pointer} is served as null"
        end
      end

      if vec["printed"]
        test "printed column: #{vec['name']}" do
          mod = Diag.module_for(type)
          n = [ Array(vec["data"]["states"]).size, 1 ].max
          assert_equal vec["printed"], (0...n).map { |i| mod.printed(vec["data"], i) }, vec["name"]
        end
      end

      if vec["select"] || vec["targets"] || vec.key?("reachable")
        test "targets and reachable: #{vec['name']}" do
          mod = Diag.module_for(type)
          Array(vec["select"]).each { |set| assert_equal 12, mod.targets(vec["data"], set).size }
          (vec["targets"] || {}).each { |set, n| assert_equal n, mod.targets(vec["data"], set).size, "#{vec['name']} #{set}" }
          if vec.key?("reachable")
            expected = vec["reachable"] == ":over_cap" ? :over_cap : vec["reachable"]
            assert_equal expected, mod.reachable(vec["data"]), vec["name"]
          end
        end
      end
    end
  end

  test "the reachable set is empty for a figure without a control, and a read cursor reaches the values it reads" do
    clim = FILES["climograph"]["vectors"].find { |v| v["name"] == "climograph-station-all-layers" }
    assert_equal [], Diag::Climograph.reachable(clim["data"])
    read = FILES["climograph"]["vectors"].find { |v| v["name"] == "climograph-inline-read-cursor" }
    reached = Diag::Climograph.reachable(read["data"])
    assert_includes reached, "21,6"
    assert_includes reached, "238"
    assert_equal [], Diag::BarModel.reachable(FILES["bar_model"]["vectors"][0]["data"])
  end

  test "the sliders of seats reach every number the readout can print inside their ranges, and over the cap it is an error to ask" do
    data = FILES["seats"]["vectors"].first["data"]
    reached = Diag::Seats.reachable(data)
    (280..310).each { |p| assert_includes reached, p.to_s }
    (150..200).each { |y| assert_includes reached, y.to_s }
    assert_includes reached, "201" # the quorum
    assert_includes reached, "141" # floor(280/2)+1 : the majority of the present at the smallest present
    assert_includes reached, "156" # floor(310/2)+1
    assert_not_includes reached, "320", "the figure's own fixed present is not reachable once its slider is declared: the readout shows 280 to 310"
    wide = data.merge("try" => { "present" => [ 100, 900 ], "yes" => [ 0, 99 ] })
    assert_equal :over_cap, Diag::Seats.reachable(wide)
  end

  # ---- the shared vectors of the computations ---------------------------------------------------------------------------

  CLIMATE = JSON.parse(Rails.root.join("test/fixtures/lesson2/climate.json").read).fetch("cases")
  CLIMATE.each do |c|
    test "climate: #{c['name']}" do
      s = Diag::Climograph.stats(c["temp"].map { |v| Lessons::Num.parse(v) }, c["precip"].map { |v| Lessons::Num.parse(v) })
      canon = ->(r) { "#{r.numerator}/#{r.denominator}" }
      e = c["expect"]
      assert_equal e["arid"], s[:arid]
      assert_equal e["total"], canon.(s[:total])
      assert_equal e["mean"], canon.(s[:mean])
      assert_equal e["warmest"], s[:warmest]
      assert_equal e["coldest"], s[:coldest]
      assert_equal e["range"], canon.(s[:range])
    end
  end

  SEATS = JSON.parse(Rails.root.join("test/fixtures/lesson2/seats.json").read).fetch("cases")
  SEATS.each do |c|
    test "seats arithmetic: #{c['name']}" do
      got = Diag::Seats.thresholds(c["seats"], c["present"], c["yes"], c["list"])
      assert_equal c["expect"].transform_values { |v| { need: v["need"], met: v["met"] } }, got, c["why"]
      verdict = Diag::Seats.approved(c["seats"], c["present"], c["yes"], c["list"])
      c["approved"].nil? ? assert_nil(verdict) : assert_equal(c["approved"], verdict)
    end
  end

  test "ChartSupport writes numbers the way an author does" do
    cs = Diag::ChartSupport
    assert_equal "21,6", cs.fmt(Rational(216, 10))
    assert_equal "1598", cs.fmt(1598)
    assert_equal "-3,25", cs.fmt(Rational(-13, 4))
    assert_equal "0,33", cs.fmt(Rational(1, 3), 2)
    assert_equal "0,333333", cs.fmt(Rational(1, 3))
    assert_equal "2,3", cs.fmt(Rational(225, 100), 1)
    assert_equal "-2,3", cs.fmt(Rational(-225, 100), 1)
    assert_equal "0,0", cs.fmt(Rational(-4, 100), 1)
    assert_equal "12,00", cs.fmt(12, 2)
    assert_equal [ "1,5", "2", "10" ], cs.numbers([ "10", "2,0", "1,50", "2" ])
  end

  # ---- no hidden value reaches the page (L2) --------------------------------------------------------------------------------

  test "bar_model: the value of a hidden part, the hidden base and the hidden results never reach the served page" do
    parts = { "type" => "bar_model", "alt_it" => "Una barra con una parte nascosta.", "view" => "parts", "total" => { "value" => "913" },
              "bars" => [ { "label_it" => "Barra", "parts" => [ { "value" => "311", "label_it" => "uno" }, { "value" => "602", "label_it" => "resto", "hidden" => true } ] } ],
              "states" => [ { "op_it" => "uno" }, { "bars" => [ { "label_it" => "Barra", "parts" => [ { "value" => "913", "label_it" => "tutto" } ] } ] } ] }
    json = JSON.generate(Lessons::StudentBody.diagram(parts))
    assert_not_includes json, "602"
    assert_includes json, "311"
    percent = { "type" => "bar_model", "alt_it" => "Una scala doppia con il cento per cento nascosto.", "view" => "percent", "base" => "7391,13", "unit" => "euro",
                "marks" => [ { "pct" => "22", "label_it" => "IVA" } ], "hide" => [ "100" ], "chain" => [ { "pct" => "90" } ] }
    served = Lessons::StudentBody.diagram(percent)
    json = JSON.generate(served)
    assert_not_includes json, "7391"
    assert_not_includes json, "6652" # the first step's result, 90 % of the hidden base
    assert_includes json, "1626,05", "the visible mark is served: 22 % of 7391,13"
    assert_nil served["values"]["100"]
    assert_equal [ { "from" => nil, "to" => nil } ], served["chain_values"]
    assert_not served.key?("base")
    shown = Lessons::StudentBody.diagram(percent.merge("hide" => []))
    assert_equal "7391,13", shown["values"]["100"]
    assert_equal "7391,13", shown["base"]
  end

  test "the sentinel property for the chart family: no hidden field of a random bar_model reaches the page" do
    rng = Random.new(Integer(ENV.fetch("SEED", 20261012)))
    Integer(ENV.fetch("PROP_RUNS", 50)).times do |run|
      secret = 9_000_000 + rng.rand(999_999)
      total = secret + 1000 + rng.rand(500)
      data = { "type" => "bar_model", "alt_it" => "Una barra con una parte nascosta da trovare.", "view" => "parts", "total" => { "value" => total.to_s },
               "bars" => [ { "label_it" => "Barra", "parts" => [ { "value" => (total - secret).to_s, "label_it" => "visibile" }, { "value" => secret.to_s, "label_it" => "nascosta", "hidden" => true } ] } ] }
      assert_not_includes JSON.generate(Lessons::StudentBody.diagram(data)), secret.to_s, "run #{run}"
      base = "#{secret},#{rng.rand(10..99)}"
      pct = { "type" => "bar_model", "alt_it" => "Una scala doppia con il valore base nascosto da trovare.", "view" => "percent", "base" => base, "hide" => [ "100" ],
              "marks" => [ { "pct" => "100", "label_it" => "tutto" } ] }
      assert_not_includes JSON.generate(Lessons::StudentBody.diagram(pct)), secret.to_s, "run #{run}"
    end
  end

  test "a station is resolved by the server and its numbers equal the table" do
    served = Lessons::StudentBody.diagram({ "type" => "climograph", "alt_it" => "Il clima di Brasília con barre e linea.", "station" => "geo/stations.brasilia" })
    row = Lessons::VettedData.row("geo/stations", "stations", "brasilia")
    assert_equal row["temp"], served["temp"]
    assert_equal row["precip"], served["precip"]
    assert_equal "Brasília (Brasile)", served["place_it"]
    assert_match(/1991-2020/, served["source_it"])
    assert_equal "geo/stations.brasilia", served["station"]
  end

  # ---- the lesson-level rules: L4, L5, L7 and the YAML key `yes` ------------------------------------------------------------

  def with_card(card_md)
    lines = Rails.root.join("test/fixtures/lesson2/base.md").read.lines
    at = lines.index { |l| l.start_with?("## Segui sempre la stessa procedura") }
    text = (lines[0...at] + [ card_md, "\n" ] + lines[at..]).join
    Lesson2Fixtures.check(text, "math")
  end

  SEATS_CARD = <<~MD.freeze
    ## Chi vota {idea icon=scale id=voto}

    ::: diagram seats
    alt_it: "Una camera inventata di quattrocento seggi in semicerchio, con i presenti tra duecentottanta e trecentodieci."
    layout: hemicycle
    seats: 400
    present: 320
    yes: 170
    thresholds: [legal_number, present_majority]
    try: {present: [280, 310], yes: [150, 200]}
    :::

    ::: check number
    prompt_it: "Con %<present>s presenti, quanti voti sì servono per la maggioranza dei presenti?"
    answer: "%<answer>s"
    errors:
      - {answer: "1", code: math_eval_wrong, message_it: "Servono più della metà dei presenti."}
    explain_it: "Metà più uno."
    %<extra>s:::
  MD

  test "a bare yes: key of a seats figure is the field yes, not the boolean the YAML library makes of it" do
    body = with_card(format(SEATS_CARD, present: "300", answer: "151", extra: "")).body
    seats = body["cards"].flat_map { |c| c["blocks"] }.find { |b| b["type"] == "diagram" && b.dig("diagram", "type") == "seats" }["diagram"]
    assert_equal 170, seats["yes"]
    assert_equal [ 150, 200 ], seats.dig("try", "yes")
    assert_not seats.key?(true)
  end

  test "L5: an answer a slider can reach is an error, reachable_ok_it is the way past, and an answer nobody can reach is fine" do
    codes = ->(answer, extra = "") { with_card(format(SEATS_CARD, present: "300", answer: answer, extra: extra)).findings.select { |f| f.code.include?("ANSWER") }.map(&:code) }
    assert_equal [ "E-CHECK-ANSWER-BY-SIMULATION" ], codes.("151")
    assert_empty codes.("151", "reachable_ok_it: \"Il numero legale è un'altra cosa.\"\n")
    assert_empty codes.("999")
  end

  test "L4: an answer a figure prints in some state is a warning" do
    card = <<~MD
      ## Il clima di un luogo {idea icon=scale id=clima}

      ::: diagram climograph
      alt_it: "Il climogramma di Brasília con la pioggia di ogni mese in millimetri e la linea della temperatura in gradi."
      station: geo/stations.brasilia
      show: [bars, line]
      :::

      ::: check number
      prompt_it: "Quanti millimetri piovono a dicembre?"
      answer: "241,1"
      errors:
        - {answer: "1", code: math_eval_wrong, message_it: "Guarda la barra di dicembre."}
      explain_it: "Dicembre."
      :::
    MD
    hit = with_card(card).findings.select { |f| f.code == "W-CHECK-ANSWER-IN-DIAGRAM" }
    assert_equal 1, hit.size
    assert_match(/241/, hit.first.message)
  end

  test "L7: a figure with a slider or a cursor is not allowed in an exercise of the try card, a plain one is" do
    lines = Rails.root.join("test/fixtures/lesson2/base.md").read
    plain = "    diagram: {type: climograph, alt_it: \"Il climogramma di Roma con la pioggia e la temperatura di ogni mese dell'anno.\", station: geo/stations.rome}\n"
    with_read = plain.sub("station: geo/stations.rome}", "station: geo/stations.rome, read: true}")
    mark = "  - text_it: 'Risolvi: $4x - 1 = 15$.'\n"
    assert_includes lines, mark
    blocked = Lesson2Fixtures.check(lines.sub(mark, "#{mark}#{with_read}"), "math").findings
    ok = Lesson2Fixtures.check(lines.sub(mark, "#{mark}#{plain}"), "math").findings
    assert(blocked.any? { |f| f.code == "E-LESSON-BLOCK" && f.message.include?("L7") })
    assert(ok.none? { |f| f.message.to_s.include?("L7") })
  end
end
