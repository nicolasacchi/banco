require "test_helper"

# The `pages` rule set of the scan (D-290, SPEC B7): vectors with their expected result.
class PageScanTest < ActiveSupport::TestCase
  VECTORS = JSON.parse(File.read(Rails.root.join("test/fixtures/js_scan/pages.json")))

  def hits(src) = Validation::PageScan.scan(src, allowed_imports: %w[banco three], local: %w[main.mjs x.mjs])

  VECTORS.each_with_index do |v, i|
    test "vector #{i}: #{v['src'].lines.first.to_s.strip.first(50)}" do
      found = hits(v["src"])
      if v["ok"]
        assert_empty found.map(&:rule), "expected no hit"
      else
        assert_includes found.map(&:rule), v["rule"], "expected the rule #{v['rule']}"
      end
    end
  end

  test "imports: a relative module of the bundle, banco and a declared library pass" do
    assert_empty hits('import { banco } from "banco"; import * as THREE from "three"; import { f } from "./x.mjs"')
    assert_not_empty hits('import { f } from "./missing.mjs"')
    assert_not_empty hits('import { f } from "../x.mjs"')
    assert_not_empty hits('import { f } from "/kit/banco-page@1.0/bridge.mjs"')
    assert_not_empty hits('export * from "https://x.org/a.js"')
  end

  test "the words of a sentence are not code" do
    assert_empty hits("const t = 'Il valore di Date e Function non conta: window e document restano parole'")
    assert_empty hits("/* window.parent */ const x = 1 // fetch()")
  end

  test "every name of the rules is a hit when used bare" do
    Validation::Rules.get(:page, :scan, :banned_identifiers).each do |name|
      assert_includes hits("const q = #{name}").map(&:rule), name, name
    end
  end
end
