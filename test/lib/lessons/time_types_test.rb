require "test_helper"

# The time family (WAVE2 2.2, T4a): timeline against its vector file, in Ruby. The browser runs the same file
# (app/javascript/lesson/test/time_types.test.mjs): the schema column, the semantic column (the first finding has the same code and path), the
# layout column and, for each good vector, what each state prints, describes and offers as select targets.
class TimeTypesTest < ActiveSupport::TestCase
  DOC = JSON.parse(Rails.root.join("test/fixtures/diagrams/types/timeline.json").read)
  T = Lessons::Diagrams::Timeline

  DOC["vectors"].each do |vec|
    test "timeline: #{vec['name']} (schema and semantic columns)" do
      errors = Banco::Schemas.validate("diagram", vec["data"])
      if vec["schema"] == "invalid"
        assert_not_empty errors, "refused by the schema"
        next
      end
      assert_empty errors.map(&:to_h), "passes the schema"
      found = Lessons::Diagrams.check(vec["data"], subject: vec["subject"])
      if vec["semantic"] == "ok"
        assert_empty found.map(&:to_h), vec["name"]
      else
        assert_equal [ vec["semantic"], vec["path"] ], [ found.first.code, found.first.path ], "#{vec['name']}: the first finding is the one the browser gives"
      end
    end
  end

  def good = DOC["vectors"].select { |v| v["schema"] == "valid" && v["semantic"] == "ok" }

  test "printed (describe included) and targets of every good vector are the ones the file holds; the browser checks the same numbers" do
    sets = JSON.parse(Rails.root.join("config/banco/schemas/diagram.json").read).dig("$defs", "timeline", "x-banco-targets")
    good.each do |vec|
      n = [ 1, Array(vec["data"]["states"]).size ].max
      assert_equal vec["expect"]["printed"], (0...n).map { |i| T.printed(vec["data"], i) }, "#{vec['name']}: printed"
      assert_equal vec["expect"]["targets"], sets.to_h { |s| [ s, T.targets(vec["data"], s) ] }, "#{vec['name']}: targets"
    end
  end

  def texts_of(node, out = [])
    case node
    when Hash then node.each { |k, v| v.is_a?(String) && k.match?(/_(it|en|es)\z/) ? out << v : texts_of(v, out) }
    when Array then node.each { |v| texts_of(v, out) }
    end
    out
  end

  test "the select form of a figure carries none of its texts (L3), and both forms are valid figures" do
    good.each do |vec|
      neutral = T.served(vec["data"], mode: :select)
      leaked = texts_of(vec["data"].except("alt_it", "caption_it", "states")).uniq.select { |t| JSON.generate(neutral.except("alt_it")).include?(t) }
      assert_empty leaked, "#{vec['name']}: texts of the figure in its select form"
      assert_empty Banco::Schemas.validate("diagram", neutral).map(&:to_h), "#{vec['name']}: the select form is a valid figure"
      assert_empty Lessons::Diagrams.check(neutral, subject: vec["subject"]).map(&:to_h), "#{vec['name']}: the select form passes the checks of its type, as the browser draws it"
      assert_empty Banco::Schemas.validate("diagram", T.served(vec["data"])).map(&:to_h), "#{vec['name']}: the student's form is a valid figure"
    end
  end

  test "the student's form keeps what is drawn and carries no measure of its own" do
    vec = good.find { |v| v["name"] == "timeline-republic-zoom" }
    served = T.served(vec["data"])
    assert_equal "years", served["scale"]
    assert_equal 3, served["states"].size
    assert_equal %w[from to periods events spans], served["states"][1].keys & %w[from to periods events spans]
  end

  test "centuries, ticks and durations come from Chrono and agree with the axis" do
    assert_equal [ "II secolo a.C.", "I secolo a.C." ], T.centuries("-146", "-27")
    assert_equal [ "I secolo a.C.", "I secolo d.C." ], T.centuries("-50", "50")
    assert_equal [ -30, -20, -10, 10, 20, 30 ], T.ticks("-30", "30", 10)
    assert_equal "40 anni", T.duration_text(Lessons::Chrono.duration("-27", "14"))
    assert_equal "1 anno", T.duration_text(1)
    two = good.find { |v| v["name"] == "timeline-two-eras" }["data"]
    assert_includes T.describe(two), "Da Fatto prima a Fatto dopo passano 40 anni."
    assert_includes T.printed(two, 0), "40"
    assert_not_includes T.printed(two, 0), "41"
  end

  test "the measure figure can show every pair of its events (L5)" do
    measure = good.find { |v| v["name"] == "timeline-measure" }["data"]
    assert_equal %w[33 89 56].sort, T.reachable(measure).select { |s| s.match?(/\A\d+\z/) }.sort
    assert_empty T.reachable(good.find { |v| v["name"] == "timeline-two-eras" }["data"])
  end

  test "the tense scale describes the order around now and says what is uncertain" do
    all = good.find { |v| v["name"] == "timeline-tense-all-kinds" }["data"]
    text = T.describe(all)
    assert_includes text, "I might go (non è sicuro): un momento dopo adesso, forse."
    assert_includes text, "I'm going to buy it (deciso prima): è deciso prima di adesso e succede dopo adesso."
    assert_includes text, "I have lived here (arriva a adesso): dura da prima di adesso a adesso."
  end
end
