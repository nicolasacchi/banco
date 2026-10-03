require "test_helper"

# B-11: high readability. The themes keep a contrast of at least 7:1 for text and
# buttons; the base type is 20 px with a 1.6 line height; nothing italic or capital.
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

  # The variables of the three themes: the cream default, the dark one under
  # :root[data-theme="dark"] and the light one under :root[data-theme="light"].
  def themes
    cream = CSS[/:root \{(.*?)\}/m, 1]
    dark = CSS[/:root\[data-theme="dark"\] \{(.*?)\}/m, 1]
    light = CSS[/:root\[data-theme="light"\] \{(.*?)\}/m, 1]
    { "cream" => cream, "dark" => dark, "light" => light }.transform_values do |block|
      block.scan(/--([a-z-]+):\s*(#[0-9a-fA-F]{6})/).to_h
    end
  end

  test "all three themes exist" do
    assert_equal %w[cream dark light], themes.keys.sort
    themes.each_value { |vars| assert_operator vars.size, :>=, 8 }
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
    assert_match(/max-width: 70ch;/, CSS)
    refute_match(/font-style:\s*italic/, CSS)
    refute_match(/text-transform:\s*(uppercase|capitalize)/, CSS)
    assert_match(/sans-serif/, CSS)
    CSS.scan(/font-size:\s*([\d.]+)(px|rem)/) { |size, unit| assert_operator size.to_f * (unit == "rem" ? 20 : 1), :>=, 18, "font-size #{size}#{unit}" }
  end

  test "the three text sizes are all at least 18 px" do
    sizes = CSS.scan(/html(?:\[data-size="\w+"\])? \{ font-size: (\d+)px; \}/).flatten.map(&:to_i)
    assert_equal 3, sizes.size
    assert_equal [ 20, 24, 28 ], sizes
  end

  test "no alarm colours: the stylesheet has no red" do
    CSS.scan(/#([0-9a-fA-F]{6})\b/) do |(hex)|
      r, g, b = hex.scan(/../).map { |c| c.to_i(16) }
      refute (r > 150 && g < 90 && b < 90), "##{hex} reads as red"
    end
  end
end
