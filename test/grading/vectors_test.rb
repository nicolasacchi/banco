require "test_helper"

# test/fixtures/grading/vectors.json is run here for every component and by
# app/javascript/grader/test/vectors.test.mjs for the expression cases.
class GradingVectorsTest < ActiveSupport::TestCase
  VECTORS = JSON.parse(File.read(Rails.root.join("test/fixtures/grading/vectors.json")))

  def run_vector(vector)
    spec = Grading::Spec.from_hash(vector["item"].merge("component" => vector["component"]))
    raw = vector["raw"]
    raw = raw.to_json if raw.is_a?(Hash) || raw.is_a?(Array) # the stored form of structured answers
    Grading.grade_spec(spec, raw, source: vector["source"] || "mathlive")
  end

  test "the file is the shared one: closed and expression cases, unique ids" do
    ids = VECTORS["cases"].map { |c| c["id"] }
    assert_equal ids.uniq, ids
    components = VECTORS["cases"].map { |c| c["component"] }.uniq
    assert_empty %w[choice ordering matching number fraction normalized_text expression] - components
  end

  VECTORS["cases"].each do |vector|
    test "vector #{vector['id']}" do
      result = run_vector(vector)
      expect = vector["expect"]

      assert_equal expect["verdict"], result.verdict, "#{vector['id']}: #{result.inspect}"
      assert_equal expect["error_codes"].sort, result.error_codes.sort if expect["error_codes"]
      assert_equal expect["form_violations"].sort, result.form_violations.sort if expect["form_violations"]
      assert_equal expect["invalid_code"], result.invalid_code if expect["invalid_code"]
      assert_equal expect["method"], result.grading_method if expect["method"]
      assert_equal expect["normalized"], result.normalized if expect["normalized"]
      assert_equal expect["inverted_pairs"], JSON.parse(result.normalized)["inverted_pairs"] if expect.key?("inverted_pairs")
      assert result.message_it.present? if result.invalid?
    end
  end
end
