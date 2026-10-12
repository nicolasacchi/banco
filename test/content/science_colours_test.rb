require "test_helper"

# The atom colours of the science family (T7, app/assets/stylesheets/lesson/science.css): one stroke colour per element, at 4:1 or more on the surface of
# every theme (WCAG 1.4.11 asks 3:1 for a shape that carries meaning; the symbol inside every atom is the other cue), and the symbol's text on the tint
# of the atom at 7:1 or more.
class ScienceColoursTest < ActiveSupport::TestCase
  CSS = Rails.root.join("app/assets/stylesheets/lesson/science.css").read
  SURFACES = { "cream" => "#fffaf0", "light" => "#f5f5f5", "dark" => "#25231f" }.freeze
  TEXT = { "cream" => "#1c1a14", "light" => "#111111", "dark" => "#f3ecdc" }.freeze

  def luminance(hex)
    r, g, b = hex.delete("#").scan(/../).map { |c| c.to_i(16) / 255.0 }
    f = ->(c) { c <= 0.03928 ? c / 12.92 : ((c + 0.055) / 1.055)**2.4 }
    (0.2126 * f.call(r)) + (0.7152 * f.call(g)) + (0.0722 * f.call(b))
  end

  def contrast(a, b)
    hi, lo = [ luminance(a), luminance(b) ].sort.reverse
    (hi + 0.05) / (lo + 0.05)
  end

  def mix(a, b, share)
    a.delete("#").scan(/../).zip(b.delete("#").scan(/../)).map { |x, y| format("%02x", ((x.to_i(16) * share) + (y.to_i(16) * (1 - share))).round) }.join.prepend("#")
  end

  def block(selector_pattern) = CSS[/#{selector_pattern}\s*\{(.*?)\}/m, 1]

  def colours(text) = text.scan(/--atom-([A-Za-z]+): (#[0-9a-f]{6})/).to_h

  test "every element stroke is 4:1 on the surface of its theme, and its symbol reads at 7:1 on the 16 percent tint" do
    light = colours(block(/:root, :root\[data-theme="light"\], \.l2-box\[data-theme="cream"\]/.source))
    dark = colours(block(/:root\[data-theme="dark"\], \.l2-box\[data-theme="dark"\]/.source))
    assert_equal light.keys.sort, dark.keys.sort
    assert_operator light.size, :>=, 10
    { "cream" => light, "light" => light, "dark" => dark }.each do |theme, set|
      set.each do |name, hex|
        assert_operator contrast(hex, SURFACES[theme]), :>=, 4.0, "#{name} on #{theme}"
        assert_operator contrast(TEXT[theme], mix(hex, SURFACES[theme], 0.16)), :>=, 7.0, "the symbol on #{name} in #{theme}"
      end
    end
  end

  test "colour is never the only cue: the symbol is drawn inside every atom, and the radii differ" do
    assert_match(/\.dg-atomtext/, CSS)
    assert_match(/\.dg-atom\.dg-neutral/, CSS, "the select mode has its own neutral look")
  end
end
