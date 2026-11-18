require "test_helper"

# B-11: high readability. The themes keep a contrast of at least 7:1 for text and
# buttons; the base type is 20 px with a 1.6 line height; nothing italic or capital.
# D-350: four themes (cream, light, dark, auto) and seven sizes, 12 to 28 px.
class ReadabilityTest < ActiveSupport::TestCase
  CSS = Rails.root.join("app/assets/stylesheets/application.css").read

  def luminance(hex)
    channels = hex.delete("#").scan(/../).map { |c| c.to_i(16) / 255.0 }
    r, g, b = channels.map { |c| c <= 0.03928 ? c / 12.92 : ((c + 0.055) / 1.055)**2.4 }
    0.2126 * r + 0.7152 * g + 0.0722 * b
  end

  def contrast(a, b)
    hi, lo = [ luminance(a), luminance(b) ].sort.reverse
    (hi + 0.05) / (lo + 0.05)
  end

  # The variables of the three palettes: the cream default, the white "light" one under :root[data-theme="light"] and the dark one under
  # :root[data-theme="dark"]. "auto" has none of its own: the page's first script gives <html> cream or dark (D-350).
  def themes
    cream = CSS[/:root \{(.*?)\}/m, 1]
    light = CSS[/:root\[data-theme="light"\] \{(.*?)\}/m, 1]
    dark = CSS[/:root\[data-theme="dark"\] \{(.*?)\}/m, 1]
    { "cream" => cream, "light" => light, "dark" => dark }.transform_values do |block|
      block.scan(/--([a-z-]+):\s*(#[0-9a-fA-F]{6})/).to_h
    end
  end

  test "the three palettes exist, and the four themes the student can choose are cream, light, dark and auto" do
    assert_equal %w[cream dark light], themes.keys.sort
    assert_equal %w[cream light dark auto], Diagnosis::Preferences::THEMES
    themes.each_value { |vars| assert_operator vars.size, :>=, 8 }
    assert_equal "#ffffff", themes["light"]["bg"], "light is white"
  end

  test "text, muted text and button text have a contrast of at least 7:1 on every theme" do
    themes.each do |name, v|
      assert_operator contrast(v["text"], v["bg"]), :>=, 7.0, "#{name}: text on background"
      assert_operator contrast(v["muted"], v["bg"]), :>=, 7.0, "#{name}: muted text on background"
      assert_operator contrast(v["text"], v["surface"]), :>=, 7.0, "#{name}: text on surface"
      assert_operator contrast(v["primary-text"], v["primary"]), :>=, 7.0, "#{name}: button text on button"
      assert_operator contrast(v["focus"], v["bg"]), :>=, 4.5, "#{name}: focus ring on background"
    end
  end

  test "the type is at least 18 px, the line height at least 1.5, left aligned, with no italics and no capitals" do
    assert_match(/html \{\s*font-size: 20px;/, CSS)
    assert_match(/line-height: 1\.[6-9]/, CSS)
    assert_match(/text-align: left;/, CSS)
    assert_match(/\.student em, \.student i, \.student cite \{ font-style: normal; \}/, CSS)
    assert_match(/--page-w: 70ch;/, CSS)
    assert_match(/max-width: var\(--page-w\);/, CSS)
    refute_match(/font-style:\s*italic/, CSS)
    refute_match(/text-transform:\s*(uppercase|capitalize)/, CSS)
    assert_match(/sans-serif/, CSS)
    # the student's own choice of a smaller root size (html[data-size=minimum|tiny|smallest|small]) is the one allowed exception
    CSS.gsub(/html\[data-size="(?:minimum|tiny|smallest|small)"\] \{ font-size: \d+px; \}/, "").scan(/font-size:\s*([\d.]+)(px|rem)/) { |size, unit| assert_operator size.to_f * (unit == "rem" ? 20 : 1), :>=, 18, "font-size #{size}#{unit}" }
  end

  test "the seven text sizes: 12, 14, 16, 18, 20 (the default), 24 and 28 px, one per size the student can choose (D-354)" do
    sizes = CSS.scan(/html(?:\[data-size="(\w+)"\])? \{ font-size: (\d+)px; \}/).to_h { |name, px| [ name || "normal", px.to_i ] }
    assert_equal({ "minimum" => 12, "tiny" => 14, "smallest" => 16, "small" => 18, "normal" => 20, "large" => 24, "larger" => 28 }, sizes)
    assert_equal Diagnosis::Preferences::SIZES.sort, sizes.keys.sort
  end

  test "a touch screen keeps targets of 44 CSS px at every size, and no length of the base sheet is in px except borders and hairlines (D-350)" do
    assert_match(/@media \(pointer: coarse\) \{\s*:root \{ --tap: max\(2\.75rem, 44px\); --tap-small: max\(2\.25rem, 44px\); \}/, CSS)
    CSS.scan(/(?<![-\w])(?:width|height|min-width|min-height|max-width|padding|margin|gap):[^;{}]*?(\d+)px/) { |(px)| assert_operator px.to_i, :<=, 1, "a size in px would not follow the text size: #{Regexp.last_match[0]}" }
  end

  test "no alarm colours: the stylesheet has no red" do
    CSS.scan(/#([0-9a-fA-F]{6})\b/) do |(hex)|
      r, g, b = hex.scan(/../).map { |c| c.to_i(16) }
      refute (r > 150 && g < 90 && b < 90), "##{hex} reads as red"
    end
  end
end
