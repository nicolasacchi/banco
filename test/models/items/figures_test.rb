require "test_helper"
require_relative "../../support/course_rows"

# D-321: a figure named by asset gets its digest and its file when the item is drawn; the ledger is not rewritten.
class ItemsFiguresTest < ActiveSupport::TestCase
  include CourseRows

  SVG = '<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 10 10"><title>t</title><path d="M0 0L10 10"/></svg>'.freeze

  setup do
    build_course
    @dir = Dir.mktmpdir
    Rails.application.config.x.item_assets_dir = @dir
  end

  teardown do
    Rails.application.config.x.item_assets_dir = nil
    FileUtils.rm_rf(@dir)
  end

  def part_for(revision, display)
    body = JSON.parse(revision.body_json)
    Items::Part.new(subject: @subject, revision: revision).call(body, body["component"], display)
  end

  def figure_display = { "stem_it" => "x", "figure" => { "asset" => "assets/fig.svg", "alt_it" => "Una linea." } }

  test "an asset figure gets the digest of its file and the file is written once" do
    revision = make_practice_item("fig-1", "math.eq", instances: 1, figure_svg: SVG)
    sha = Digest::SHA256.hexdigest(SVG)
    out = part_for(revision, figure_display)
    assert_equal({ alt_it: "Una linea.", src: "/assets/items/#{sha}.svg" }, out[:figure])
    path = File.join(@dir, "#{sha}.svg")
    assert_equal SVG, File.read(path)
    mtime = File.mtime(path)
    sleep 0.01
    part_for(revision, figure_display)
    assert_equal mtime, File.mtime(path), "written once"
    assert_equal [ "#{sha}.svg" ], Dir.children(@dir), "no temporary file is left"
  end

  test "an explicit sha256 is honoured and nothing is written" do
    revision = make_practice_item("fig-2", "math.eq", instances: 1)
    sha = "ab" * 32
    File.write(File.join(@dir, "#{sha}.svg"), SVG)
    out = part_for(revision, "stem_it" => "x", "figure" => { "sha256" => sha, "alt_it" => "A" })
    assert_equal "/assets/items/#{sha}.svg", out[:figure][:src]
  end

  test "an explicit sha256 with no file falls back to the asset, then to the alt text" do
    sha = "cd" * 32
    revision = make_practice_item("fig-2b", "math.eq", instances: 1, figure_svg: SVG)
    out = part_for(revision, "figure" => { "sha256" => sha, "asset" => "assets/fig.svg", "alt_it" => "A" })
    assert_equal "/assets/items/#{Digest::SHA256.hexdigest(SVG)}.svg", out[:figure][:src]
    bare = make_practice_item("fig-2c", "math.eq", instances: 1)
    assert_equal({ alt_it: "A" }, part_for(bare, "figure" => { "sha256" => sha, "alt_it" => "A" })[:figure])
  end

  test "an unwritable assets directory gives the alt text, not an error" do
    File.write(File.join(@dir, "blocker"), "x")
    Rails.application.config.x.item_assets_dir = File.join(@dir, "blocker", "sub")
    revision = make_practice_item("fig-5", "math.eq", instances: 1, figure_svg: SVG)
    assert_equal({ alt_it: "Una linea." }, part_for(revision, figure_display)[:figure])
  end

  test "a label that says Data: keeps its picture, a javascript: attribute does not" do
    ok = '<svg xmlns="http://www.w3.org/2000/svg"><text x="1" y="9">Data: 5</text></svg>'
    revision = make_practice_item("fig-6", "math.eq", instances: 1, figure_svg: ok)
    assert part_for(revision, figure_display)[:figure][:src]
    bad = '<svg xmlns="http://www.w3.org/2000/svg"><a xlink:href=" javascript:alert(1)"><text>x</text></a></svg>'
    revision = make_practice_item("fig-7", "math.eq", instances: 1, figure_svg: bad)
    assert_nil part_for(revision, figure_display)[:figure][:src]
  end

  test "a display without a figure is unchanged" do
    revision = make_practice_item("fig-3", "math.eq", instances: 1, figure_svg: SVG)
    out = part_for(revision, "stem_it" => "x")
    assert_not out.key?(:figure)
    assert_empty Dir.children(@dir)
  end

  test "an asset the revision does not have keeps the alt text only" do
    revision = make_practice_item("fig-4", "math.eq", instances: 1)
    out = part_for(revision, figure_display)
    assert_equal({ alt_it: "Una linea." }, out[:figure])
  end

  test "a dirty SVG is refused: the alt text stays, no file is written" do
    [ '<svg xmlns="http://www.w3.org/2000/svg"><script>alert(1)</script></svg>',
      '<svg xmlns="http://www.w3.org/2000/svg" onload="alert(1)"><path d="M0 0"/></svg>',
      '<svg xmlns="http://www.w3.org/2000/svg"><foreignObject><p>x</p></foreignObject></svg>',
      '<svg xmlns="http://www.w3.org/2000/svg"><image href="https://example.com/a.png"/></svg>',
      '<svg xmlns="http://www.w3.org/2000/svg"><a href="javascript:alert(1)"><path d="M0 0"/></a></svg>',
      '<!DOCTYPE svg [<!ENTITY x "y">]><svg xmlns="http://www.w3.org/2000/svg"/>',
      '<svg xmlns="http://www.w3.org/2000/svg"><style>@import url(https://example.com/a.css);</style></svg>',
      "<html><body>not an svg</body></html>" ].each_with_index do |dirty, n|
      revision = make_practice_item("fig-dirty-#{n}", "math.eq", instances: 1, figure_svg: dirty)
      out = part_for(revision, figure_display)
      assert_equal({ alt_it: "Una linea." }, out[:figure], dirty)
    end
    assert_empty Dir.children(@dir)
  end
end
