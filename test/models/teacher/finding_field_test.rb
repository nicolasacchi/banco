require "test_helper"

# D-222: the "Riguarda:" line of a finding says what the field is and whether S sees it.
class FindingFieldTest < ActiveSupport::TestCase
  CASES = {
    "stem_it" => :stem, "stem" => :stem, "prompt_stem_it" => :stem, "display/stem_it" => :stem, "instances/3/display/stem_it" => :stem,
    "passage_it" => :passage, "table" => :material, "quote" => :material, "figure" => :material,
    "options" => :options, "options/2" => :options, "options[1]" => :options, "Options" => :options,
    "answer_format_it" => :format, "steps_it" => :steps, "accept" => :accept, "must_reject" => :accept, "accent_policy" => :accept,
    "answer" => :key, "key" => :key, "error_catalogue" => :errors, "error_catalogue/1/message_it" => :errors, "message_it" => :errors,
    "sources" => :sources, "sources/1" => :sources, "sources/seconda_line 412" => :sources, "fragment" => :sources,
    "solution" => :solution, "rubric" => :rubric, "rubric/points/1" => :rubric, "model_answer_it" => :rubric,
    "title" => :metadata, "component" => :metadata, "expected_seconds" => :metadata, "skill" => :metadata,
    "generator" => :generator, "tests" => :generator, "verify" => :generator,
    "instances/2" => :instance, "instance 4" => :instance,
    "something else" => :other, "" => :other
  }.freeze

  test "every field a reviewer, the blind solve or the validation can name maps to a part of the item" do
    CASES.each { |field, part| assert_equal part, Teacher::FindingField.key_for(field), field.inspect }
  end

  test "nil and odd fields fall back to the generic phrase, which names the field" do
    assert_equal :other, Teacher::FindingField.key_for(nil)
    assert_match(/«qualcosa di strano»/, Teacher::FindingField.phrase("qualcosa di strano"))
    assert_match(/Non so dire se S la vede/, Teacher::FindingField.phrase("qualcosa di strano"))
    assert_operator Teacher::FindingField.phrase("x" * 500).size, :<, 200
  end

  test "every part has an Italian phrase that says whether S sees it" do
    parts = Teacher::FindingField::KEYS.keys + %i[instance other]
    parts.each do |part|
      text = I18n.t("teacher.skill.field.#{part}", field: "f", raise: true)
      assert_match(/\bS\b/, text, part.to_s)
      assert_match(/ved/, text, part.to_s)
      findings = Validation::Findings.new
      Validation::Readability.lint_document({ "x_it" => text }, "field", findings)
      assert_empty findings.errors.map(&:to_h), "#{part}: #{text}"
    end
  end

  test "the examples of the operator read as asked" do
    assert_equal "le fonti: le righe di programma collegate alla domanda. S non le vede.", Teacher::FindingField.phrase("sources/1")
  end
end
