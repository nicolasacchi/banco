require "test_helper"

# The kit (D-289, SPEC B6): released directories never change, the lock says so, the generator is the harness's.
class PagesKitTest < ActiveSupport::TestCase
  test "the lock lists every file of every released kit directory and nothing changed" do
    assert_empty Pages::Kit.lock_problems
  end

  test "the seeded generator of the kit is the one of the item generators, byte for byte" do
    assert_equal File.binread(Rails.root.join("lib/harness/rng.mjs")), Pages::Kit.read("1.0", "rng.mjs")
  end

  test "a kit file is found by lookup in the listing, never by joining a path" do
    assert Pages::Kit.read("1.0", "bridge.mjs")
    assert_nil Pages::Kit.read("1.0", "../1.0/bridge.mjs")
    assert_nil Pages::Kit.read("1.0", "fonts/../bridge.mjs")
    assert_nil Pages::Kit.read("9.9", "bridge.mjs")
    assert_nil Pages::Kit.read("1.0", "nope.mjs")
    assert_includes Pages::Kit.files("1.0"), "fonts/atkinson-hyperlegible-latin-400-normal.woff2"
  end

  test "the vendored libraries match their sums and the pages libs file" do
    out = `bin/vendor-pages --check 2>&1`
    assert $?.success?, out
  end

  test "a library is parsed only when the server vendors it" do
    assert_equal({ name: "three", version: "0.186.1", addon: nil }, Pages::Libs.parse("three@0.186.1"))
    assert_equal({ name: "three", version: "0.186.1", addon: "controls/OrbitControls.js" }, Pages::Libs.parse("three-addons@0.186.1:controls/OrbitControls.js"))
    assert_nil Pages::Libs.parse("three@0.1.0")
    assert_nil Pages::Libs.parse("axe-core@4.14.0") # a harness library, never a page's
    assert_nil Pages::Libs.parse("three-addons@0.186.1:loaders/GLTFLoader.js")
    assert_equal "/vendor/three@0.186.1/three.module.js", Pages::Libs.importmap([ "three@0.186.1" ])["three"]
    assert_equal "/vendor/three@0.186.1/addons/controls/OrbitControls.js", Pages::Libs.importmap([ "three-addons@0.186.1:controls/OrbitControls.js" ])["three/addons/controls/OrbitControls.js"]
  end

  test "the transfer size counts the module and its core, gzipped" do
    kb = Pages::Libs.transfer_bytes([ "three@0.186.1" ]) / 1024
    assert_operator kb, :>, 100
    assert_operator kb, :<, 600
    assert_equal 0, Pages::Libs.transfer_bytes([])
  end
end
