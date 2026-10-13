require "test_helper"
require "support/page_world"

# The static checks of a page bundle (D-290, SPEC B7).
class PageChecksTest < ActiveSupport::TestCase
  include PageWorld

  def check(files = page_files, key: "math.pages-sample") = Validation::PageChecks.call(files, key: key, subject: "math")
  def codes(outcome) = outcome.findings.errors.map(&:code).uniq

  test "the sample page passes with a bundle hash" do
    outcome = check
    assert_empty outcome.findings.errors.map(&:to_h)
    assert_match(/\A\h{64}\z/, outcome.bundle_sha256)
  end

  test "the bundle hash depends on every byte and on the manifest, not on the order of the files" do
    a = check.bundle_sha256
    assert_equal a, check(page_files.to_a.reverse.to_h).bundle_sha256
    changed = check(page_files { |f| f["maths.mjs"] += "\n// x" }).bundle_sha256
    assert_not_equal a, changed
    manifest = page_files { |f| f["page.json"] = JSON.generate(JSON.parse(f["page.json"]).merge("min_height" => 400)) }
    assert_not_equal a, check(manifest).bundle_sha256
  end

  test "no main.mjs, a file outside the allowlist, a json data file, an html file" do
    assert_includes codes(check(page_files { |f| f.delete("main.mjs") })), "E-PAGE-FILES"
    assert_includes codes(check(page_files { |f| f["data.json"] = "{}" })), "E-PAGE-FILES"
    assert_includes codes(check(page_files { |f| f["model.glb"] = "x" })), "E-PAGE-FILES"
    assert_includes codes(check(page_files { |f| f["index.html"] = "<p>" })), "E-PAGE-FILES"
    assert_includes codes(check(page_files { |f| f["sub/a.mjs"] = "export const a = 1" })), "E-PAGE-FILES"
    assert_includes codes(check(page_files { |f| 9.times { |i| f["m#{i}.mjs"] = "export const a = #{i}" } })), "E-PAGE-FILES"
  end

  test "budgets: a module over 200 KB, an asset over 300 KB, the whole over 1 MB" do
    assert_includes codes(check(page_files { |f| f["big.mjs"] = "export const a = [#{'1,' * 110_000}]" })), "E-PAGE-SIZE"
    png = "\x89PNG\r\n\x1a\n".b + ("x" * 320_000).b
    assert_includes codes(check(page_files { |f| f["assets/a.png"] = png })), "E-PAGE-SIZE"
    assert_includes codes(check(page_files { |f| 6.times { |i| f["m#{i}.mjs"] = "export const a = [#{'1,' * 90_000}#{i}]" } })), "E-PAGE-SIZE"
  end

  test "assets: an SVG with a script or an external reference, a PNG that is not one" do
    assert_includes codes(check(page_files { |f| f["assets/a.svg"] = "<svg xmlns='http://www.w3.org/2000/svg'><script>1</script></svg>" })), "E-PAGE-FILES"
    assert_includes codes(check(page_files { |f| f["assets/a.svg"] = "<svg><image href='https://x.org/a.png'/></svg>" })), "E-PAGE-FILES"
    assert_includes codes(check(page_files { |f| f["assets/a.png"] = "not a png" })), "E-PAGE-FILES"
    assert_empty check(page_files { |f| f["assets/a.svg"] = "<svg xmlns='http://www.w3.org/2000/svg'><circle r='1'/></svg>" }).findings.errors.map(&:code)
  end

  test "style.css: @import and a url outside the bundle are refused, a bundle file is not" do
    assert_includes codes(check(page_files { |f| f["style.css"] = "@import url(x.css);" })), "E-PAGE-CSS"
    assert_includes codes(check(page_files { |f| f["style.css"] = "p { background: url(https://x.org/a.png) }" })), "E-PAGE-CSS"
    assert_includes codes(check(page_files { |f| f["style.css"] = "p { background: url(assets/nope.png) }" })), "E-PAGE-CSS"
    ok = page_files do |f|
      f["assets/a.svg"] = "<svg xmlns='http://www.w3.org/2000/svg'><circle r='1'/></svg>"
      f["style.css"] = "p { background: url(assets/a.svg) }"
    end
    assert_empty codes(check(ok))
  end

  test "the manifest: schema, key, subject, libs and the word counts" do
    set = ->(h) { page_files { |f| f["page.json"] = JSON.generate(JSON.parse(f["page.json"]).merge(h)) } }
    assert_includes codes(check(set.call("bridge" => 2))), "E-SCHEMA"
    assert_includes codes(check(set.call("key" => "math.other"))), "E-PAGE-TEXT"
    assert_includes codes(check(set.call("subject" => "english"))), "E-PAGE-TEXT"
    assert_includes codes(check(set.call("libs" => [ "three@9.9.9" ]))), "E-PAGE-LIBS"
    assert_includes codes(check(set.call("libs" => [ "three-addons@0.186.1:controls/OrbitControls.js" ]))), "E-PAGE-LIBS"
    assert_includes codes(check(set.call("instructions_it" => (%w[parola] * 41).join(" ")))), "E-PAGE-TEXT"
    assert_includes codes(check(set.call("alt_it" => "Un disegno"))), "E-PAGE-TEXT"
    assert_includes codes(check(set.call("fallback_it" => "Non parte, vedi la figura."))), "E-PAGE-TEXT"
    assert_includes codes(check(set.call("instructions_it" => "Premi *qui* subito."))), "E-READ"
  end

  test "the code: a banned API is E-PAGE-API, an import of an undeclared library is E-PAGE-LIBS, a stranger is E-PAGE-IMPORT" do
    assert_includes codes(check(page_files { |f| f["main.mjs"] += "\nfetch('x')" })), "E-PAGE-API"
    assert_includes codes(check(page_files { |f| f["main.mjs"] += "\nwindow.parent.postMessage(1, '*')" })), "E-PAGE-API"
    assert_includes codes(check(page_files { |f| f["main.mjs"] = "import * as T from 'three'\n#{f['main.mjs']}" })), "E-PAGE-LIBS"
    assert_includes codes(check(page_files { |f| f["main.mjs"] = "import x from 'https://x.org/a.js'\n#{f['main.mjs']}" })), "E-PAGE-IMPORT"
    assert_includes codes(check(page_files { |f| f["main.mjs"] += "\nawait import('./maths.mjs')" })), "E-PAGE-IMPORT"
  end

  test "the private hygiene terms, when the server has the list" do
    Dir.mktmpdir do |dir|
      list = File.join(dir, "terms")
      File.write(list, "zorbaville\n")
      with_env("BANCO_HYGIENE_TERMS_FILE" => list) do
        assert_includes codes(check(page_files { |f| f["maths.mjs"] += "\n// Zorbaville" })), "E-PAGE-HYGIENE"
        assert check.hygiene_checked
      end
    end
    with_env("BANCO_HYGIENE_TERMS_FILE" => nil) { assert_not check.hygiene_checked }
  end
end
