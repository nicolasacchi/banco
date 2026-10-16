require "test_helper"

# D-296: the direction of an accent (grave or acute on the same vowel) never makes an answer wrong.
class AccentDirectionTest < ActiveSupport::TestCase
  def text(answer, given, subject: "italian", **opts)
    Grading::Closed.grade(Grading::Spec.new(component: "normalized_text", subject: subject, answer: answer, **opts), given)
  end

  def choice(key, chosen_id, options, errors: [])
    spec = Grading::Spec.new(component: "choice", subject: "italian", answer: key, errors: errors,
                             display: { "options" => options.map { |id, t| { "id" => id, "text" => t } } })
    Grading::Closed.grade(spec, chosen_id)
  end

  test "grave for acute and acute for grave are correct, whatever the accent policy" do
    %w[strict flag].each do |policy|
      assert_equal "correct", text("perché", "perchè", accent_policy: policy).verdict
      assert_equal "correct", text("è", "é", accent_policy: policy).verdict
      assert_equal "correct", text("perchè", "perché", accent_policy: policy).verdict
      assert_equal "correct", text("più", "piú", accent_policy: policy).verdict
      assert_equal "correct", text("á", "à", accent_policy: policy).verdict
    end
    assert_equal "perchè", text("perché", "Perchè.").normalized
  end

  test "Spanish tildes written grave are correct" do
    assert_equal "correct", text("está", "està", subject: "spanish").verdict
    assert_equal "correct", text("canción", "canciòn", subject: "spanish").verdict
  end

  test "a declared error that is the key up to direction cannot be hit" do
    r = text("perché", "perchè", errors: [ { "code" => "it_accent_grave_acute", "value" => "perchè" } ])
    assert_equal "correct", r.verdict
    assert_empty r.error_codes
  end

  test "a missing accent, an apostrophe and the other letters still count" do
    assert_equal [ "it_accents" ], text("perché", "perche").error_codes
    assert_equal [ "it_apostrophe_accent" ], text("perché", "perche'").error_codes
    assert_equal [ "it_apostrophe_accent" ], text("è", "e'").error_codes
    assert_equal "typical_error", text("è", "e", paradigm_forms: []).verdict
    assert_equal "es_accents", text("está", "esta", subject: "spanish").error_codes.first
    assert_not_equal "correct", text("año", "ano", subject: "spanish").verdict
    assert_not_equal "correct", text("pingüino", "pinguino", subject: "spanish").verdict
    assert_not_equal "correct", text("está", "estã", subject: "spanish").verdict
    assert_not_equal "correct", text("perché", "perchê").verdict
  end

  test "an accent on the wrong vowel is not correct" do
    assert_not_equal "correct", text("canción", "cancìon", subject: "spanish").verdict
    assert_not_equal "correct", text("canción", "cáncion", subject: "spanish").verdict
  end

  test "choice: an option equal to the key up to direction is correct" do
    options = { "o1" => "perché", "o2" => "perchè", "o3" => "perche'", "o4" => "perche" }
    assert_equal "correct", choice("o1", "o1", options).verdict
    declared = [ { "code" => "it_accent_grave_acute", "value" => "o2" } ]
    assert_equal "correct", choice("o1", "o2", options, errors: declared).verdict
    assert_equal "wrong", choice("o1", "o3", options).verdict
    assert_equal "wrong", choice("o1", "o4", options).verdict
    assert_equal "typical_error", choice("o1", "o4", options, errors: [ { "code" => "x", "value" => "o4" } ]).verdict
  end

  test "choice: different words and options without text are not folded together" do
    assert_equal "wrong", choice("o1", "o2", { "o1" => "è", "o2" => "e" }).verdict
    spec = Grading::Spec.new(component: "choice", subject: "math", answer: "o1", display: { "options" => [ { "id" => "o1" }, { "id" => "o2" } ] })
    assert_equal "wrong", Grading::Closed.grade(spec, "o2").verdict
  end
end
