require "test_helper"
require "open3"
require "tmpdir"

# bin/hygiene guards a public repository, so the script must not itself carry
# the private terms it looks for, not even split into string fragments.
class HygieneTest < ActiveSupport::TestCase
  SCRIPT = Rails.root.join("bin/hygiene")

  test "the script holds no term list built from joined string fragments" do
    refute_match(/"\w+""\w+"/, SCRIPT.read)
    refute_match(/'\w+''\w+'/, SCRIPT.read)
  end

  test "terms come from HYGIENE_TERMS and are found in tracked files" do
    Dir.mktmpdir do |dir|
      sh = ->(*cmd, env: {}) { Open3.capture3(env, *cmd, chdir: dir) }
      sh.call("git", "init", "-q")
      FileUtils.mkdir_p(File.join(dir, "bin"))
      FileUtils.cp(SCRIPT, File.join(dir, "bin/hygiene"))
      File.write(File.join(dir, ".gitignore"), "/prep/\n")
      File.write(File.join(dir, "notes.txt"), "a line about Zorblax here\n")
      sh.call("git", "add", "-A")
      _o, err, st = sh.call("bin/hygiene", env: { "HYGIENE_TERMS" => "zorblax\nother" })
      refute st.success?, err
      assert_match(/forbidden term found/, err)
      _o, err, st = sh.call("bin/hygiene", env: { "HYGIENE_TERMS" => "nothere" })
      assert st.success?, err
    end
  end
end
