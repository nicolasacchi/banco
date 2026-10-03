require "test_helper"

# E-CODE-GLOBAL: the lint of generator.mjs and verify.mjs (A-06, A-02).
class JsScanTest < ActiveSupport::TestCase
  def rules(source) = Validation::JsScan.call(source).map(&:rule)

  # Built from parts: this file only contains the names the linter must refuse.
  EVAL = "ev" + "al"
  FUNCTION = "Func" + "tion"

  GOOD = <<~JS.freeze
    import { fmt } from "/lib/fmt.mjs";
    import { pick } from "/lib/rng.mjs";
    // Date and Math.random in a comment are fine: fetch( too
    /* performance.now() */
    export function generate(seed, rng) {
      const label = "Date, FUNCTION_WORD and fetch in a string are words";
      const text = `Calcola ${rng.int(2, 9)} per ${rng.int(2, 9)}`;
      const place = { location: 1 };
      return { display: { stem_it: label + text }, answer: String(seed) };
    }
  JS

  test "a clean generator has no hit" do
    assert_empty rules(GOOD.sub("FUNCTION_WORD", FUNCTION))
  end

  test "banned globals are hits, as whole words" do
    assert_includes rules("const t = Date.now();"), "Date"
    assert_includes rules("const x = Math.random();"), "Math.random"
    assert_includes rules("const x = Math['random']();"), "Math.random"
    assert_includes rules("performance.now()"), "performance"
    assert_includes rules("crypto.getRandomValues(a)"), "crypto"
    assert_includes rules("new Intl.NumberFormat('it')"), "Intl"
    assert_includes rules("(1.5).toLocaleString('it')"), ".toLocaleString"
    assert_includes rules("#{EVAL}('1')"), EVAL
    assert_includes rules("new #{FUNCTION}('return 1')"), FUNCTION
    assert_includes rules("fetch('x')"), "fetch"
    assert_includes rules("new XMLHttpRequest()"), "XMLHttpRequest"
    assert_includes rules("new WebSocket('x')"), "WebSocket"
    assert_includes rules("importScripts('x')"), "importScripts"
    assert_includes rules("window.location = 'x'"), "window"
    assert_includes rules("navigator.sendBeacon('x')"), "navigator"
    assert_empty rules("const updated = update(Datetime, performanceIndex);")
  end

  test "dynamic import and imports of other files are hits" do
    assert_includes rules("const m = await import('/x.mjs');"), "import("
    assert_includes rules("import { a } from './other.mjs';"), "import ./other.mjs"
    assert_includes rules("import 'https://cdn.example.org/x.js';"), "import https://cdn.example.org/x.js"
    assert_includes rules("export * from '/lib/other.mjs';"), "import /lib/other.mjs"
    assert_empty rules("import { a } from '/lib/rng.mjs'; import b from \"/lib/fmt.mjs\";")
  end

  test "external resources in strings are hits" do
    assert(rules("const u = 'https://example.org/a.png';").any? { |r| r.start_with?("external resource") })
    assert(rules("const u = '//cdn.example.org/a.js';").any? { |r| r.start_with?("external resource") })
    assert_empty rules("const ratio = 'a // b';")
  end

  test "code in a template expression is code" do
    assert_includes rules("const s = `x ${Date.now()} y`;"), "Date"
    assert_empty rules("const s = `Data: ${rng.int(1, 3)}`;")
  end

  test "a regular expression with quotes does not hide what follows" do
    assert_includes rules("const re = /[\"']+/g; fetch('x');"), "fetch"
  end

  test "object keys and properties named like a global are not hits" do
    assert_empty rules("const o = { document: 1 }; o.window = 2; o.location;")
  end
end
