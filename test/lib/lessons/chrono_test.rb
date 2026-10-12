require "test_helper"

# Lessons::Chrono against the shared vectors of the browser twin (test/fixtures/lesson2/chrono.json; app/javascript/lesson/test/chrono.test.mjs).
class LessonsChronoTest < ActiveSupport::TestCase
  VECTORS = JSON.parse(Rails.root.join("test/fixtures/lesson2/chrono.json").read)
  C = Lessons::Chrono

  def run_case(fn, args)
    case fn
    when "duration" then C.duration(*args)
    when "century" then C.century(*args)
    when "roman" then C.roman(*args)
    when "parse_roman" then C.parse_roman(*args)
    when "mutants" then C.mutants(*args)
    else flunk "unknown function #{fn}"
    end
  end

  test "the signatures are those of the vector file" do
    assert_equal VECTORS["functions"].keys.sort, C::SIGNATURES.keys.sort
    VECTORS["functions"].each { |name, spec| assert_equal spec["ruby"], C::SIGNATURES[name], name }
  end

  test "every vector case gives its result, and a refused case raises or gives nil" do
    VECTORS["functions"].each do |fn, spec|
      assert_operator spec["cases"].size, :>=, 6, "#{fn} has cases"
      spec["cases"].each do |c|
        got = begin
          run_case(fn, c["args"])
        rescue ArgumentError
          :refused
        end
        got = :refused if got.nil? && c["refused"]
        if c["refused"]
          assert_equal :refused, got, "#{fn} #{c['args'].inspect} is refused"
        else
          got = got.to_s unless got.is_a?(Hash)
          assert_equal c["result"], got, "#{fn} #{c['args'].inspect}"
        end
      end
    end
  end

  test "the year 0 is never counted: the duration is the difference of positions, and adding it back is the mutant" do
    assert_equal 40, C.duration("-27", "14")
    assert_equal 1, C.duration("-1", "1")
    (-30..30).reject(&:zero?).each do |a|
      (-30..30).reject(&:zero?).each do |b|
        assert_equal C.duration(a, b), -C.duration(b, a)
        assert_equal C.duration(a, b), (if a.negative? && b.positive? then b - a - 1 elsif a.positive? && b.negative? then b - a + 1 else b - a end)
        assert_equal b - a, C.mutants(a, b)["year_zero_counted"].to_i if a.negative? && b.positive?
        assert_not_includes C.mutants(a, b).values.map(&:to_i), C.duration(a, b)
      end
    end
  end

  test "roman and parse_roman are inverse on 1 to 3999, and a century is the roman of its number" do
    (1..3999).each { |n| assert_equal n, C.parse_roman(C.roman(n)) }
    assert_equal "XXI secolo d.C.", C.century(2005)
    assert_equal "I secolo a.C.", C.century(-1)
    assert_nil C.parse_roman("IIII")
  end

  test "Verify reaches the library: chrono.duration with its mutants" do
    fn = Lessons::Verify.resolve("chrono.duration")
    assert_equal 40, fn.call.call({ "from" => "-27", "to" => "14" })
    assert_equal({ "year_zero_counted" => "41", "eras_subtracted" => "13" }, fn.mutants.call({ "from" => "-27", "to" => "14" }))
  end
end
