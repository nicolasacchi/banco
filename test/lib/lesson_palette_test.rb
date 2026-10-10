require "test_helper"
require_relative "../support/colour_maths"

# D-246: config/banco/lesson_palette.yml and config/banco/icons.yml, declared once. The rules of the
# palette's `rules:` block are checked here, not by agents.
class LessonPaletteTest < ActiveSupport::TestCase
  C = ColourMaths
  PALETTE = YAML.safe_load_file(Rails.root.join("config/banco/lesson_palette.yml"))
  ICONS = YAML.safe_load_file(Rails.root.join("config/banco/icons.yml"))
  RULES = PALETTE.fetch("rules")
  # The student's themes (application.css): cream is the default and what print uses; the light theme
  # (white) takes the cream colours, which are dark enough on white.
  THEMES = { "cream" => { bg: "#fbf3df", surface: "#fffaf0", text: "#1c1a14" }, "dark" => { bg: "#1b1a17", surface: "#25231f", text: "#f3ecdc" } }.freeze
  LIGHT = { bg: "#ffffff", surface: "#f5f5f5", text: "#111111" }.freeze
  SHAPES = %w[box weight circle square triangle diamond ring star].freeze
  CARRIERS = %w[glyph position icon tint band].freeze
  SUBJECTS = %w[math italian].freeze

  def roles(subject) = PALETTE.fetch(subject).fetch("roles")

  def all_roles(subject) = PALETTE.fetch("common").merge(roles(subject))

  test "the file has a version, the rules and a palette per subject with at most eight roles beyond common" do
    assert_equal 1, PALETTE["version"]
    SUBJECTS.each { |s| assert_operator roles(s).size, :<=, RULES["max_roles_per_subject"], s }
    assert_equal RULES["max_roles_per_subject"], 8
  end

  test "every role has a label in Italian, a known carrier and the colours its carrier needs" do
    SUBJECTS.each do |subject|
      all_roles(subject).each do |name, role|
        where = "#{subject}.#{name}"
        assert_match(/\A[a-z]+(-[a-z]+)*\z/, name, where)
        assert role["label_it"].to_s.size.positive?, where
        assert_includes CARRIERS, role["carrier"], where
        case role["carrier"]
        when "tint", "band" then assert role["tint"], where
        else assert(role["fg"] && role["mark"], where)
        end
        assert role["tint"], where if role["carrier"] == "position"
        assert_includes SHAPES, role["shape"], where if role["shape"]
        assert role["icon"], where if role["carrier"] == "icon"
        THEMES.each_key { |t| [ "fg", "mark", "tint" ].each { |k| assert_match(/\A#\h{6}\z/, role[k][t], "#{where}.#{k}.#{t}") if role[k] } }
      end
    end
  end

  # The equations' roles are drawn in the balance (pans, boxes, bells) and in the member tiles: no red and no green anywhere
  # in them, so that a colour never says "right" or "wrong" (the hue of a saturated colour decides).
  def hue_and_saturation(hex)
    r, g, b = hex.delete("#").scan(/../).map { |c| c.hex / 255.0 }
    max = [ r, g, b ].max
    min = [ r, g, b ].min
    return [ 0, 0 ] if max == min

    d = max - min
    h = if max == r then ((g - b) / d) % 6 elsif max == g then ((b - r) / d) + 2 else ((r - g) / d) + 4 end
    [ (h * 60).round, d / (1 - (2 * ((max + min) / 2) - 1).abs) ]
  end

  test "the roles of the equations use no red and no green" do
    %w[unknown known left right].each do |name|
      role = roles("math").fetch(name)
      %w[fg mark tint].each do |key|
        next unless role[key]

        THEMES.each_key do |theme|
          hue, sat = hue_and_saturation(role[key][theme])
          next if sat < 0.35

          assert(hue >= 14 && hue < 340, "math.#{name}.#{key}.#{theme} #{role[key][theme]} is red (hue #{hue})")
          assert(hue < 75 || hue > 170, "math.#{name}.#{key}.#{theme} #{role[key][theme]} is green (hue #{hue})")
        end
      end
    end
  end

  test "text colours keep 7:1 on the background and the surface of the cream and dark themes (and white)" do
    SUBJECTS.each do |subject|
      all_roles(subject).each do |name, role|
        next unless role["fg"]

        THEMES.each do |theme, t|
          %i[bg surface].each do |ground|
            assert_operator C.contrast(role["fg"][theme], t[ground]), :>=, RULES["text_contrast"], "#{subject}.#{name} fg #{theme} on #{ground}"
          end
        end
        assert_operator C.contrast(role["fg"]["cream"], LIGHT[:bg]), :>=, RULES["text_contrast"], "#{subject}.#{name} fg on white"
      end
    end
  end

  test "shapes and strokes keep 3:1, and the ink keeps 7:1 on every tint" do
    SUBJECTS.each do |subject|
      all_roles(subject).each do |name, role|
        THEMES.each do |theme, t|
          if role["mark"]
            %i[bg surface].each do |ground|
              assert_operator C.contrast(role["mark"][theme], t[ground]), :>=, RULES["graphic_contrast"], "#{subject}.#{name} mark #{theme} on #{ground}"
            end
          end
          assert_operator C.contrast(role["tint"][theme], t[:text]), :>=, RULES["ink_on_tint_contrast"], "#{subject}.#{name} ink on tint #{theme}" if role["tint"]
        end
      end
    end
  end

  test "roles that share a diagram stay apart under protanopia, deuteranopia and tritanopia" do
    minimum = RULES["cvd_min_delta_e"]
    SUBJECTS.each do |subject|
      roles = roles(subject).reject { |_, r| r["carrier"] == "band" }
      THEMES.each_key do |theme|
        roles.to_a.combination(2).each do |(a, ra), (b, rb)|
          needs = [ ra, rb ].any? { |r| r["carrier"] == "icon" } ? minimum["icon"] : minimum["colour"]
          distance = C.cvd_distance(ra["mark"][theme], rb["mark"][theme])
          assert_operator distance, :>=, needs, "#{subject}: #{a} and #{b} in #{theme} are #{distance.round(1)} apart"
        end
      end
    end
  end

  test "an icon role has an icon no other role of the subject uses, and a shape of its own" do
    SUBJECTS.each do |subject|
      all = all_roles(subject).reject { |name, _| %w[accent].include?(name) }
      icons = all.values.filter_map { |r| r["icon"] }
      assert_equal icons.uniq.size, icons.size, "#{subject}: an icon is used by two roles"
      shapes = roles(subject).values.filter_map { |r| r["shape"] }
      assert_equal shapes.uniq.size, shapes.size, "#{subject}: a shape is used by two roles"
    end
  end

  test "the colour-vision maths is right on known pairs" do
    assert_in_delta 0.0, C.delta_e(C.lab(C.lin("#336699")), C.lab(C.lin("#336699"))), 1e-9
    assert_in_delta 21.0, C.contrast("#000000", "#ffffff"), 1e-9
    # Sharma, Wu and Dalal 2005, pair 1 of the test data: 2.0425
    assert_in_delta 2.0425, C.delta_e([ 50.0, 2.6772, -79.7751 ], [ 50.0, 0.0, -82.7485 ]), 1e-4
    assert_in_delta 2.8615, C.delta_e([ 50.0, 3.1571, -77.2803 ], [ 50.0, 0.0, -82.7485 ]), 1e-4
    assert_operator C.cvd_distance("#ff0000", "#00ff00"), :<, 25
  end

  test "the step tags name icons of the subject's list or the structural list" do
    PALETTE.fetch("step_tags").each do |subject, tags|
      allowed = ICONS["structural"].keys + ICONS["subjects"].fetch(subject).keys
      tags.each do |tag, t|
        assert_match(/\A[a-z]+\z/, tag, subject)
        assert t["label_it"].to_s.size.positive?, "#{subject}.#{tag}"
        assert_includes allowed, t["icon"], "#{subject}.#{tag}"
      end
    end
  end

  test "icon roles name icons of their subject's list or the structural list, and the ui list is ours only" do
    SUBJECTS.each do |subject|
      allowed = ICONS["structural"].keys + ICONS["ui"].keys + ICONS["subjects"].fetch(subject).keys
      all_roles(subject).each_value { |r| assert_includes allowed, r["icon"], subject if r["icon"] }
    end
  end
end
