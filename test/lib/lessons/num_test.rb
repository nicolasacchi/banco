require "test_helper"

# Lessons::Num against the shared vectors of the browser twin (test/fixtures/lesson2/numbers.json).
class LessonsNumTest < ActiveSupport::TestCase
  VECTORS = JSON.parse(Rails.root.join("test/fixtures/lesson2/numbers.json").read)

  VECTORS["parse"].each_with_index do |v, i|
    test "parse #{i}: #{v['input'].inspect}#{' (inf allowed)' if v['allow_inf']}" do
      allow = v["allow_inf"] == true
      if v["refused"]
        assert_nil Lessons::Num.parse(v["input"], allow_inf: allow), v["reason"]
        assert_nil Lessons::Num.canonical(v["input"], allow_inf: allow)
      else
        assert_equal v["canonical"], Lessons::Num.canonical(v["input"], allow_inf: allow)
      end
    end
  end

  VECTORS["compare"].each_with_index do |v, i|
    test "compare #{i}: #{v['a']} and #{v['b']}" do
      assert_equal v["cmp"], Lessons::Num.compare(v["a"], v["b"], allow_inf: v["allow_inf"])
    end
  end

  test "to_s writes an integer or a fraction" do
    assert_equal "3", Lessons::Num.to_s(Rational(6, 2))
    assert_equal "-5/2", Lessons::Num.to_s(Rational(-5, 2))
  end

  test "the schema patterns accept exactly the numbers Num accepts" do
    defs = JSON.parse(Rails.root.join("config/banco/schemas/diagram.json").read).fetch("$defs")
    num = Regexp.new(defs.dig("num", "pattern"))
    VECTORS["parse"].reject { |v| v["input"].include?("inf") || v.key?("allow_inf") }.each do |v|
      assert_equal !v["refused"], num.match?(v["input"].to_s), v["input"]
    end
  end
end
