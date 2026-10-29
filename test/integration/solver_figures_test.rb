require "test_helper"
require "support/grading_rows"

# D-320: the blind solver and the reviewer see the figures of an item as the student does, as PNG files, and
# nothing that is not the drawing.
class SolverFiguresTest < ActionDispatch::IntegrationTest
  include GradingRows

  KEY = "KEYSECRET-4711".freeze
  SVG = <<~SVG.freeze
    <?xml version="1.0"?>
    <!-- #{KEY} comment -->
    <svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 400 240" width="400" height="240" data-answer="#{KEY}">
      <title>#{KEY} title</title><desc>#{KEY} desc</desc>
      <metadata>#{KEY} metadata</metadata>
      <rect width="400" height="240" fill="#fff"/>
      <polyline points="40,200 120,200 160,120 260,120 300,40 380,40" fill="none" stroke="#1d4ed8" stroke-width="3" data-points="0,1,2,3,#{KEY}"/>
      <line x1="40" y1="20" x2="40" y2="200" stroke="#000"/><line x1="40" y1="200" x2="390" y2="200" stroke="#000"/>
      <text x="200" y="228" font-size="14">Tempo (min)</text><text x="4" y="16" font-size="14">T (C)</text>
    </svg>
  SVG
  OTHER_SVG = SVG.sub("1d4ed8", "b91c1c")

  setup do
    @token = ApiToken.issue!(role: "agent_claude", label: "figures test")
    @solver = AgentSession.create!(label: "t", role: "solver", agent: "test", model: "kimi-k3")
    @reviewer = AgentSession.create!(label: "t", role: "reviewer", agent: "test", model: "gpt-5.2")
  end

  def api(path, as:)
    on(:api, path, headers: { "Authorization" => "Bearer #{@token}", "X-Banco-Session" => as.id.to_s })
  end

  def json = response.parsed_body

  # A revision with a figure in the prompt (instances 1 and 2) and a figure of its own in instance 3.
  def figured_revision(files: { "assets/curve.svg" => SVG, "assets/other.svg" => OTHER_SVG })
    body = item_body("short-answer").merge("prompt" => { "stem_it" => "Leggi il grafico.", "figure" => { "asset" => "assets/curve.svg", "alt_it" => "Una curva di riscaldamento" } })
    @n = (@n || 0) + 1
    subject = Subject.find_or_create_by!(key: "math") { |x| x.name_it = "Matematica"; x.position = 1 }
    item = Item.create!(subject: subject, key: "fig-#{@n}", kind: "short_answer")
    revision = ItemRevision.create!(item: item, seq: 1, body_json: body.to_json, author_session: AgentSession.create!(label: "a", role: "author"),
                                    file_sessions_json: "{}", brief_sha256: "0" * 64, files_json: files.empty? ? nil : JSON.generate(files))
    [ [ { stem_it: "Quando bolle?" }, "100" ], [ { stem_it: "E la fusione?" }, "0" ],
      [ { stem_it: "Altro", figure: { asset: "assets/other.svg", alt_it: "Un'altra curva" } }, "1" ] ].each_with_index do |(display, answer), i|
      ItemInstance.create!(item_revision: revision, seed: 900 + i, display_json: display.to_json, answer_json: answer.to_json, errors_json: "[]", fingerprint: SecureRandom.hex(32))
    end
    revision
  end

  def png_chunks(bytes)
    assert_equal "\x89PNG\r\n\x1a\n".b, bytes.byteslice(0, 8)
    chunks = []
    pos = 8
    while pos < bytes.bytesize
      length = bytes.byteslice(pos, 4).unpack1("N")
      chunks << bytes.byteslice(pos + 4, 4)
      pos += 12 + length
    end
    chunks
  end

  def chrome!
    path = ENV["BROWSER_PATH"].to_s
    skip "BROWSER_PATH is not set (no Chrome to drive)" if path.empty?
    skip "BROWSER_PATH #{path} is not executable" unless File.executable?(path)
  end

  test "an instance without a figure opens with no figure files, for the solver and the reviewer" do
    instance = create_instance(item_body("short-answer"), { "display" => { "stem_it" => "Uno" }, "answer" => "1" })
    api("/api/v1/revisions/#{instance.item_revision_id}/solve", as: @solver)
    assert_response :ok
    assert_equal [], json["figures"]
    api("/api/v1/revisions/#{instance.item_revision_id}/review", as: @reviewer)
    assert_response :ok
    assert_equal [], json["figures"]
  end

  test "the solver gets each figure as a PNG of the drawing alone: no key, no data attribute, no title" do
    chrome!
    Dir.mktmpdir do |dir|
      with_env("BANCO_ITEM_FIGURES_DIR" => dir) do
        revision = figured_revision
        api("/api/v1/revisions/#{revision.id}/solve", as: @solver)
        assert_response :ok
        body = response.body
        assert_not_includes body, KEY
        assert_not_includes body, "assets/"
        assert_not_includes body, "<svg"
        assert_equal %w[figure-1.png figure-2.png], json["figures"].map { |f| f["name"] }
        assert_equal [ 1, 2 ], json["figures"][0]["instances"]
        assert_equal [ 3 ], json["figures"][1]["instances"]
        assert_equal "Una curva di riscaldamento", json["figures"][0]["alt_it"]
        shown = json["instances"].map { |i| i["display"]["figure"] }
        assert_equal [ { "alt_it" => "Una curva di riscaldamento", "file" => "figure-1.png" }, { "alt_it" => "Una curva di riscaldamento", "file" => "figure-1.png" },
                       { "alt_it" => "Un'altra curva", "file" => "figure-2.png" } ], shown
        json["figures"].each do |fig|
          png = Base64.strict_decode64(fig["png_base64"])
          assert_equal [ fig["width"], fig["height"] ], png.byteslice(16, 8).unpack("NN")
          assert_equal 1000, fig["width"]
          assert_operator fig["height"], :>, 400
          assert_empty png_chunks(png) - %w[IHDR IDAT IEND PLTE sRGB gAMA pHYs cHRM], "only the pixels, no text chunk"
          assert_not_includes png, KEY
        end
        assert_not_equal json["figures"][0]["png_base64"], json["figures"][1]["png_base64"]
        # the second open is served from the cache
        assert_equal 2, Dir.children(dir).size
      end
    end
  end

  test "the reviewer gets the same files and keeps the figure's own members in the display" do
    chrome!
    Dir.mktmpdir do |dir|
      with_env("BANCO_ITEM_FIGURES_DIR" => dir) do
        revision = figured_revision
        api("/api/v1/revisions/#{revision.id}/review", as: @reviewer)
        assert_response :ok
        assert_equal 2, json["figures"].size
        assert_equal "figure-1.png", json["instances"][0]["display"]["figure"]["file"]
        assert_equal "assets/curve.svg", json["instances"][0]["display"]["figure"]["asset"]
      end
    end
  end

  test "an asset the revision does not hold is listed as missing; Chrome that cannot draw refuses the open" do
    revision = figured_revision(files: {})
    api("/api/v1/revisions/#{revision.id}/solve", as: @solver)
    assert_response :ok
    assert_equal [ true, true ], json["figures"].map { |f| f["missing"] }
    assert_nil json["figures"][0]["png_base64"]

    revision = figured_revision
    boom = ->(_svg) { raise Review::FigureImage::Unavailable, "no Chrome" }
    Review::FigureImage.stub(:png, boom) do
      api("/api/v1/revisions/#{revision.id}/solve", as: @solver)
    end
    assert_response :service_unavailable
    assert_equal "E-CHROME-UNAVAILABLE", json["code"]
  end
end
