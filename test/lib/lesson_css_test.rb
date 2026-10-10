require "test_helper"

# Atkinson Hyperlegible has no U+2260 (and other operators): the KaTeX relation and operator classes of a lesson
# must fall back to the vendored KaTeX_Main, not to a system font that may be missing (a tofu box for S).
class LessonCssTest < ActiveSupport::TestCase
  CSS = Rails.root.join("app/assets/stylesheets/lesson.css").read

  test "relations and binary operators fall back to KaTeX_Main" do
    rule = CSS.lines.find { |l| l.include?(".katex .mrel") && l.include?("font-family") }
    assert rule, "the rule for .mrel sets a font-family"
    assert_match(/font-family:\s*"Atkinson Hyperlegible",\s*KaTeX_Main/, rule)
    assert_includes rule, ".l2 .katex .mbin"
  end

  test "KaTeX_Main is vendored and declared by the KaTeX css" do
    assert Rails.root.join("public/vendor/katex@0.19.0/fonts/KaTeX_Main-Regular.woff2").exist?
    assert_includes Rails.root.join("public/vendor/katex@0.19.0/katex.min.css").read, "KaTeX_Main"
  end
end
