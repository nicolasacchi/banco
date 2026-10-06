require "test_helper"

class StudentLabelsTest < ActiveSupport::TestCase
  test "the reuse label is neutral: a cloze page is not a classification" do
    label = File.read(Rails.root.join("config/locales/it.yml"))[/matching_reuse_label: "(.*)"/, 1]
    assert_match(/risposta/, label)
    assert_no_match(/categori/i, label)
  end
end
