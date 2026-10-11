require "test_helper"

# The hints and keys around a typed answer in a lesson check name the form of the answer, never a number: a fixed
# example can coincide with the real answer of an exercise and give it away.
class CheckHintsTest < ActiveSupport::TestCase
  KEYS = %w[fraction_line_hint helper_keys key_minus key_bar key_comma check_empty invalid].freeze

  test "the hints and helper keys of a typed answer contain no digits" do
    texts = I18n.t("lesson2", locale: :it)
    flat = flatten(texts)
    KEYS.each do |key|
      value = flat[key]
      assert value, "missing text #{key}"
      assert_no_match(/\d/, value, "#{key} must not name a number")
    end
  end

  test "the one-line input has no placeholder" do
    source = Rails.root.join("app/javascript/lesson/blocks/check.js").read
    assert_no_match(/placeholder/, source)
  end

  private

  def flatten(hash, out = {})
    hash.each { |k, v| v.is_a?(Hash) ? flatten(v, out) : out[k.to_s] = v }
    out
  end
end
