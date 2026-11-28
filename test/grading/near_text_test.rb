require "test_helper"

# Grading::NearText.kind (D-339): pure, deterministic; the vectors are test/fixtures/grading/near_text.json.
class NearTextTest < ActiveSupport::TestCase
  CASES = JSON.parse(File.read(Rails.root.join("test/fixtures/grading/near_text.json")))["cases"]

  test "the file has unique ids and covers both kinds and nil" do
    ids = CASES.map { |c| c["id"] }
    assert_equal ids.uniq, ids
    assert_equal [ nil, "one_word", "typo" ], CASES.map { |c| c["expect"] }.uniq.sort_by(&:to_s)
  end

  CASES.each do |c|
    test "vector #{c['id']}" do
      kind = Grading::NearText.kind(c["answer"], c["candidates"], case_sensitive: c["case_sensitive"] == true, subject: c["subject"])

      c["expect"] ? assert_equal(c["expect"].to_sym, kind, c["id"]) : assert_nil(kind, c["id"])
    end
  end

  test "the same inputs give the same kind" do
    assert_equal Grading::NearText.kind("libary", [ "library" ]), Grading::NearText.kind("libary", [ "library" ])
  end

  test "the kind of a wrong answer on a graded item is derived from the key and the accepted forms" do
    key = [ "doesn't have", "does not have" ]
    assert_equal :typo, Grading::NearText.kind("doesnt have", key)
    assert_equal :one_word, Grading::NearText.kind("does not", key)
    assert_nil Grading::NearText.kind("has not", key)
  end
end
