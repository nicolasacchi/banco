require "test_helper"

# D-403: `spaces_in_code` (D-114) is for codes (bits anywhere, letter codes in computer_science or capitals in a case sensitive item), never for the
# one-word key of a language subject typed as two words; a declared error value that equals the answer is looked at first.
class SpacedCodeTest < ActiveSupport::TestCase
  def spec(subject, answer, errors: [], **opts)
    Grading::Spec.new(component: "normalized_text", subject: subject, skill: "#{subject}.x", answer: answer,
                      errors: errors.map { |c, v| { "code" => c, "value" => v } }, **opts)
  end

  def grade(spec, raw) = Grading.grade_spec(spec, raw)

  test "a declared error that equals the answer is a typical error, even when the key typed with spaces would be a code" do
    result = grade(spec("spanish", "porque", errors: [ [ "es_causal_porque_spelling", "por que" ] ]), "por que")
    assert_equal "typical_error", result.verdict
    assert_equal [ "es_causal_porque_spelling" ], result.error_codes
    assert_equal "error", result.matched[:kind]
  end

  test "a one-word key typed as two words in a language subject is a near miss (one space), a wrong, never invalid" do
    near = grade(spec("spanish", "porque", spelling_policy: "near"), "por que")
    assert_equal "near_miss", near.verdict
    assert_not near.invalid?
    assert_equal "wrong", grade(spec("spanish", "porque"), "por que").verdict
    english = grade(spec("english", "everyday", spelling_policy: "near"), "every day")
    assert_not english.invalid?
    assert_equal "near_miss", english.verdict
    assert_equal "wrong", grade(spec("english", "everyday"), "every day").verdict
  end

  test "a letter code in computer_science typed in groups is still invalid, spaces_in_code" do
    result = grade(spec("computer_science", "GHCC"), "G H C C")
    assert_equal [ "invalid", "spaces_in_code" ], [ result.verdict, result.invalid_code ]
  end

  test "bits typed in groups are invalid in every subject" do
    %w[computer_science english].each do |subject|
      result = grade(spec(subject, "001110"), "001 110")
      assert_equal [ "invalid", "spaces_in_code" ], [ result.verdict, result.invalid_code ], subject
    end
  end

  test "a key in capitals of a case sensitive item is a letter code in any subject; in lowercase or case insensitive it is not" do
    assert_equal "spaces_in_code", grade(spec("english", "NASA", case_sensitive: true), "N A S A").invalid_code
    assert_not grade(spec("english", "NASA"), "N A S A").invalid?
    assert_not grade(spec("english", "nasa", case_sensitive: true), "n a s a").invalid?
  end

  test "a lesson check in a language subject: «por que» is its declared error, or wrong without it, never invalid" do
    check = { "component" => "normalized_text", "prompt_it" => "No sé ___ llora.", "answer" => "porque",
              "errors" => [ { "answer" => "por que", "code" => "es_causal_porque_spelling", "message_it" => "Qui si scrive in una parola." } ] }
    graded = Lessons::Checks.grade(check, "por que", nil, subject: "spanish")
    assert_equal [ "wrong", "es_causal_porque_spelling", "Qui si scrive in una parola." ], [ graded.verdict, graded.code, graded.message_it ]
    plain = Lessons::Checks.grade(check.except("errors"), "por que", nil, subject: "spanish")
    assert_equal "wrong", plain.verdict
    assert_not plain.invalid?
    code = { "component" => "normalized_text", "prompt_it" => "Scrivi.", "answer" => "GHCC" }
    assert Lessons::Checks.grade(code, "G H C C", nil, subject: "computer_science").invalid?
  end
end
