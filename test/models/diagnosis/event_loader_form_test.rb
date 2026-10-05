require "test_helper"

class Diagnosis::EventLoaderFormTest < ActiveSupport::TestCase
  G = Struct.new(:verdict, :error_codes_json, :form_violations_json, :method, keyword_init: true)

  def fields(grading, body, skill = "a")
    Diagnosis::EventLoader.allocate.send(:grading_fields, grading, body, skill)
  end

  test "a wrong_form on the item's own skill carries its first violation as the code" do
    g = G.new(verdict: "wrong_form", error_codes_json: "[]", form_violations_json: '["not_fully_factored","lowest_terms"]')
    f = fields(g, { "form" => [ "factored" ] })
    assert_equal "skill", f[:form]
    assert_equal "not_fully_factored", f[:error_code]
  end

  test "a declared form skill gets no code" do
    g = G.new(verdict: "wrong_form", error_codes_json: "[]", form_violations_json: '["lowest_terms"]')
    f = fields(g, { "form" => [ "x" ], "form_skill" => "b" })
    assert_equal "declared", f[:form]
    assert_nil f[:error_code]
  end

  test "an existing typical-error code is kept" do
    g = G.new(verdict: "wrong_form", error_codes_json: '["e1"]', form_violations_json: '["lowest_terms"]')
    assert_equal "e1", fields(g, { "form" => [ "x" ] })[:error_code]
  end

  test "an accent slip on a flag item names the orthography skill (D-096)" do
    g = G.new(verdict: "typical_error", error_codes_json: '["es_accents"]', form_violations_json: nil)
    f = fields(g, { "accent_policy" => "flag" })
    assert f[:orthography_slip]
    assert_equal "spanish.accents", f[:orthography_skill]
    g = G.new(verdict: "typical_error", error_codes_json: '["it_apostrophe_accent"]', form_violations_json: nil)
    assert_equal "italian.spelling", fields(g, { "accent_policy" => "flag" })[:orthography_skill]
    strict = fields(G.new(verdict: "typical_error", error_codes_json: '["es_accents"]', form_violations_json: nil), {})
    assert_nil strict[:orthography_skill]
  end
end
