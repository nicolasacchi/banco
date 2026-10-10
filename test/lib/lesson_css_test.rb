require "test_helper"

# Atkinson Hyperlegible has no U+2260 (and other operators) and draws a slashed zero. The lesson page therefore puts
# digits first in "Banco Digits" (the digits of the vendored KaTeX_SansSerif, no slash), falls back to KaTeX_Main for the
# KaTeX relation and operator classes, and to "Banco Symbols" (a vendored U+2260) in running text: never a system font
# that may be missing (a tofu box for S).
class LessonCssTest < ActiveSupport::TestCase
  CSS = Rails.root.join("app/assets/stylesheets/lesson.css").read
  STACK = /font-family:\s*"Banco Digits",\s*"Atkinson Hyperlegible",\s*(?:"Banco Symbols",\s*)?KaTeX_Main/

  test "relations and binary operators fall back to KaTeX_Main after the digit face" do
    rule = CSS.lines.find { |l| l.include?(".katex .mbin") && l.include?("font-family") }
    assert rule, "the rule for .mbin sets a font-family"
    assert_match(STACK, rule)
    mrel = CSS.lines.find { |l| l.start_with?(".l2 .katex .mrel {") }
    assert_match(STACK, mrel)
  end

  test "the not-equal sign is the character in our symbols face, not KaTeX's composed glyph" do
    assert(CSS.lines.any? { |l| l.include?(".katex .mord.text") && l.include?('"Banco Symbols"') && l.include?("font-weight: inherit") })
    assert_not CSS.include?(".katex .rlap")
    text = Rails.root.join("app/javascript/lesson/text.js").read
    assert_includes text, '\\char\\"2260'
    assert_match(/"\\\\neq": NOT_EQUAL, "\\\\ne": NOT_EQUAL/, text)
  end

  test "digits are drawn without a slash: Banco Digits covers 0-9 only and comes first in the lesson's font stack" do
    assert_match(/@font-face \{ font-family: "Banco Digits"[^}]*unicode-range: U\+0030-0039[^}]*KaTeX_SansSerif-Regular\.woff2/, CSS)
    assert_match(/\.l2 \{ font-family: "Banco Digits", "Atkinson Hyperlegible", "Banco Symbols"/, CSS)
    %w[KaTeX_SansSerif-Regular KaTeX_SansSerif-Bold].each { |f| assert Rails.root.join("public/vendor/katex@0.19.0/fonts/#{f}.woff2").exist? }
  end

  test "the not-equal sign has a vendored face" do
    assert_match(/font-family: "Banco Symbols"[^}]*unicode-range: U\+2260/, CSS)
    CSS.scan(%r{/vendor/banco-symbols@1/[\w.-]+\.woff2}).uniq.each { |f| assert Rails.root.join("public#{f}").file?, "#{f} is missing" }
  end

  test "KaTeX_Main is vendored and declared by the KaTeX css" do
    assert Rails.root.join("public/vendor/katex@0.19.0/fonts/KaTeX_Main-Regular.woff2").exist?
    assert_includes Rails.root.join("public/vendor/katex@0.19.0/katex.min.css").read, "KaTeX_Main"
  end
end
