require "test_helper"

# The decisions file (810 KB) and the two docs are read and parsed once per version of the file, not once per request:
# the public routes of Updates cost a hash lookup (D-333).
class UpdatesCacheTest < ActiveSupport::TestCase
  # Runs the block with Updates reading its own copy of the decisions file (@path) at a new mtime: tests run in parallel
  # processes, and the mtime of the repository's file is not theirs to move.
  def new_version
    Dir.mktmpdir("updates-cache") do |dir|
      @path = Pathname(dir).join("decisions.md")
      FileUtils.cp(Rails.root.join(Updates::DECISIONS), @path)
      File.utime(Time.now, @path.mtime + 5 + rand(1000), @path)
      Updates.stub(:decisions_path, @path) { yield }
    end
  end

  # How many times the decisions file is parsed while the block runs.
  def parses
    count = 0
    parse = Updates.method(:parse_decisions)
    Updates.stub(:parse_decisions, ->(text) { count += 1; parse.call(text) }) { yield }
    count
  end

  test "two calls parse the decisions file once, and give the same answers" do
    new_version do
      answers = []
      count = parses do
        2.times { answers << [ Updates.changes, Updates.decision("D-333"), Updates.decision("333"), Updates.changes(since: 330) ] }
      end
      assert_equal 1, count
      assert_equal answers.first, answers.last
      assert_equal "D-333", answers.first[1][:number]
      assert_match(/\A## D-333 · /, answers.first[1][:text])
      assert_equal answers.first[1], answers.first[2]
    end
  end

  test "touching the file's mtime parses it again, once" do
    new_version do
      assert_equal 1, parses { Updates.changes }
      assert_equal 0, parses { Updates.changes }
      File.utime(Time.now, @path.mtime + 1, @path)
      assert_equal 1, parses { Updates.changes; Updates.decision("D-332") }
    end
  end

  test "an answer is a copy: changing it does not change the next one" do
    Updates.doc("api")[:sha256] = "changed"
    assert_equal Digest::SHA256.hexdigest(Rails.root.join("docs/api.md").read), Updates.doc("api")[:sha256]
    Updates.changes.clear
    assert_not_empty Updates.changes
    assert_nil Updates.doc("../config/master.key")
  end
end
