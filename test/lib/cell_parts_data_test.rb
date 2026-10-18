require "test_helper"

# bio/cell_parts and its second table bio/cell_parts_expected (WAVE2 1.9; T7, D-312): the parts each cell kind may show in the `cell` figure, their Italian
# names, jobs and fixed colours. The first table follows OpenStax Biology 2e, the second the Italian pages (it.wikipedia, Treccani); this test compares them,
# checks the table on its own (the four shared parts in every kind, every listed part described) and the colours (3:1 on both themes, the stylesheet equal).
class CellPartsDataTest < ActiveSupport::TestCase
  TABLE = Lessons::VettedData.table("bio/cell_parts")
  EXPECTED = Lessons::VettedData.table("bio/cell_parts_expected")
  CSS = Rails.root.join("app/assets/stylesheets/lesson/science.css").read
  SURFACE = { "cream" => "#fffaf0", "dark" => "#25231f" }.freeze
  SHARED = %w[membrane cytoplasm ribosomes].freeze
  DNA_PARTS = %w[nucleoid nucleus].freeze

  def luminance(hex)
    r, g, b = hex.delete("#").scan(/../).map { |c| c.to_i(16) / 255.0 }
    f = ->(c) { c <= 0.03928 ? c / 12.92 : ((c + 0.055) / 1.055)**2.4 }
    (0.2126 * f.call(r)) + (0.7152 * f.call(g)) + (0.0722 * f.call(b))
  end

  def contrast(a, b)
    hi, lo = [ luminance(a), luminance(b) ].sort.reverse
    (hi + 0.05) / (lo + 0.05)
  end

  test "both tables are written and valid against their schemas" do
    assert Lessons::VettedData.valid?("bio/cell_parts"), Lessons::VettedData.errors("bio/cell_parts").first(3).join("; ")
    assert Lessons::VettedData.valid?("bio/cell_parts_expected"), Lessons::VettedData.errors("bio/cell_parts_expected").first(3).join("; ")
    assert_equal %w[animal bacterium plant], TABLE["kinds"].keys.sort
    assert_equal TABLE["kinds"].keys.sort, EXPECTED["kinds"].keys.sort
  end

  test "every kind has the four shared parts, exactly one place for its DNA, and lists only parts the table describes" do
    TABLE["kinds"].each do |kind, parts|
      assert_empty SHARED - parts, "#{kind} lacks a shared part"
      assert_equal 1, (parts & DNA_PARTS).size, "#{kind}: the DNA is in a nucleoid or a nucleus"
      assert_empty parts - TABLE["parts"].keys, kind
      assert_equal parts.uniq, parts, kind
      assert_not_includes parts, "dna", "dna is drawn inside the nucleoid or the nucleus, never listed"
    end
    assert_equal [ "nucleoid" ], TABLE["kinds"]["bacterium"] & DNA_PARTS, "a bacterium has no nucleus"
    listed = TABLE["kinds"].values.flatten.uniq
    assert_equal (listed + [ "dna" ]).sort, TABLE["parts"].keys.sort, "every described part is drawn by some kind (dna inside the others)"
  end

  test "the second table: an always part is in the kind, a never part is not, and every part of a kind is in the second table" do
    EXPECTED["kinds"].each do |kind, rows|
      parts = TABLE["kinds"].fetch(kind)
      rows.each do |part, row|
        case row["present"]
        when "always" then assert_includes parts, part, "#{kind} has #{part} (#{row['source']})"
        when "never" then assert_not_includes parts, part, "#{kind} has no #{part} (#{row['source']})"
        end
      end
      assert_empty parts - rows.keys, "#{kind}: every part the figure may draw is looked up in the second route"
    end
    # what the figure refuses is what the graph's errors are about: a nucleus in a bacterium, a wall or chloroplasts in an animal cell
    assert_equal "never", EXPECTED.dig("kinds", "bacterium", "nucleus", "present")
    assert_equal "never", EXPECTED.dig("kinds", "animal", "wall", "present")
    assert_equal "never", EXPECTED.dig("kinds", "animal", "chloroplasts", "present")
  end

  test "the Italian name of every part contains the stem the second route writes" do
    assert_equal TABLE["parts"].keys.sort, EXPECTED["words"].keys.sort
    TABLE["parts"].each do |part, row|
      assert_includes row["name_it"].downcase, EXPECTED["words"].fetch(part).downcase, part
      assert_operator row["job_it"].split.size, :<=, 16, "#{part}: a job is one short line"
      assert_match(/\A\p{Lu}.*\.\z/, row["job_it"], "#{part}: a job is a sentence")
    end
  end

  test "every outline is 3:1 against its theme's surface, the cytoplasm, the wall and its own fill; the ribosomes' dots too" do
    SURFACE.each do |theme, surface|
      cyto = TABLE.dig("parts", "cytoplasm", "fill", theme)
      wall = TABLE.dig("parts", "wall", "fill", theme)
      TABLE["parts"].each do |part, row|
        line = row.dig("outline", theme)
        assert_operator contrast(line, surface), :>=, 3.0, "#{part} on the #{theme} surface"
        assert_operator contrast(line, cyto), :>=, 3.0, "#{part} on the #{theme} cytoplasm"
        assert_operator contrast(line, row.dig("fill", theme)), :>=, 3.0, "#{part} on its own #{theme} fill" unless part == "ribosomes"
      end
      assert_operator contrast(TABLE.dig("parts", "membrane", "outline", theme), wall), :>=, 3.0, "the membrane against the #{theme} wall"
      assert_operator contrast(TABLE.dig("parts", "ribosomes", "fill", theme), cyto), :>=, 3.0, "the ribosomes on the #{theme} cytoplasm"
    end
  end

  test "the stylesheet repeats the colours of the table, theme by theme" do
    { "cream" => /:root, \.l2-box\[data-theme="cream"\] \{([^}]*--cp-[^}]*)\}/m, "dark" => /:root\[data-theme="dark"\], \.l2-box\[data-theme="dark"\] \{([^}]*--cp-[^}]*)\}/m }.each do |theme, pattern|
      block = CSS[pattern, 1]
      assert block, "science.css has the #{theme} block of the cell parts"
      css = block.scan(/--cp-([a-z]+)-(fill|line): (#[0-9a-f]{6})/).to_h { |part, what, hex| [ "#{part}.#{what}", hex ] }
      want = TABLE["parts"].flat_map { |part, row| [ [ "#{part}.fill", row.dig("fill", theme) ], [ "#{part}.line", row.dig("outline", theme) ] ] }.to_h
      assert_equal want, css, theme
    end
  end
end
