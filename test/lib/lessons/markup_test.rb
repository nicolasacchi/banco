require "test_helper"

# Markup v2 (lessons only), the strict Ruby mirror of the browser parser. The same fixture,
# test/fixtures/markup/v2.json, is run by node (test/javascript/items/markup_v2.test.mjs).
class LessonsMarkupTest < ActiveSupport::TestCase
  CASES = JSON.parse(File.read(Rails.root.join("test/fixtures/markup/v2.json")))

  CASES.select { |c| c.key?("blocks") }.each_with_index do |c, i|
    test "valid input #{i} gives the shared blocks" do
      assert_equal c["blocks"], Lessons::Markup.parse(c["input"])
    end
  end

  CASES.select { |c| c.key?("error") }.each_with_index do |c, i|
    test "refused input #{i}: #{c['error']}" do
      error = assert_raises(Lessons::Markup::Refused) { Lessons::Markup.parse(c["input"]) }
      assert_equal c["error"], error.construct
      assert_equal c["line"], error.line
    end
  end

  test "the line number follows the offset of the text in the file" do
    error = assert_raises(Lessons::Markup::Refused) { Lessons::Markup.parse("Bene.\n\nMale x^2.", line_offset: 40) }
    assert_equal 42, error.line
  end

  test "raw blocks keep the numbers and the source lines" do
    block = Lessons::Markup.raw_blocks("3. tre\n4. quattro").first
    assert_equal :ol, block.type
    assert_equal [ 3, 4 ], block.items.map { |i| i[:n] }
    assert_equal "3. tre\n4. quattro", block.source
  end
end
