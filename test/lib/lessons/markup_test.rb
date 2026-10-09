require "test_helper"

# Markup v2 (lessons only), the strict Ruby mirror of the browser parser. The same fixture,
# test/fixtures/markup/v2.json, is run by node (test/javascript/items/markup_v2.test.mjs).
class LessonsMarkupTest < ActiveSupport::TestCase
  CASES = JSON.parse(File.read(Rails.root.join("test/fixtures/markup/v2.json")))

  # Cases with "options" (roles: true, the lesson/2 additions of A5) are run below with roles: true; the browser parser (R2) runs them too.
  CASES.select { |c| c.key?("blocks") && !c.key?("options") }.each_with_index do |c, i|
    test "valid input #{i} gives the shared blocks" do
      assert_equal c["blocks"], Lessons::Markup.parse(c["input"])
    end
  end

  CASES.select { |c| c.key?("error") && !c.key?("options") }.each_with_index do |c, i|
    test "refused input #{i}: #{c['error']}" do
      error = assert_raises(Lessons::Markup::Refused) { Lessons::Markup.parse(c["input"]) }
      assert_equal c["error"], error.construct
      assert_equal c["line"], error.line
    end
  end

  CASES.select { |c| c.key?("blocks") && c.key?("options") }.each_with_index do |c, i|
    test "lesson/2 valid input #{i}: #{c['input'][0, 40].inspect}" do
      assert_equal c["blocks"], Lessons::Markup.parse(c["input"], roles: c["options"]["roles"])
    end
  end

  CASES.select { |c| c.key?("error") && c.key?("options") }.each_with_index do |c, i|
    test "lesson/2 refused input #{i}: #{c['error']}" do
      error = assert_raises(Lessons::Markup::Refused) { Lessons::Markup.parse(c["input"], roles: c["options"]["roles"]) }
      assert_equal c["error"], error.construct
      assert_equal c["line"], error.line
    end
  end

  test "without the roles option a role span and a link keep being refused as before" do
    assert_raises(Lessons::Markup::Refused) { Lessons::Markup.parse("Vedi [qui](scheda:x).") }
    assert_equal [ [ "subject", 2 ], [ "unknown", 2 ] ], Lessons::Markup.roles_used("\nx\n[[subject:Il treno]] e $\\role{unknown}{x}$.", line_offset: 1)
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
