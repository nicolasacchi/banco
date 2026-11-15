require "test_helper"
require "net/http"
require_relative "../support/validation_servers"
require_relative "../support/chrome_helper"
require_relative "../support/student_ui_rows"

# The item shots in the server's Chrome (D-336): every instance of an item revision drawn as the student's phone draws it (390 x 844, cream, device scale 1),
# the whole page pictured, the findings per instance. Needs Chrome (BROWSER_PATH); skips without.
class ItemRenderRunnerTest < ActiveSupport::TestCase
  include ChromeHelper
  include StudentUiRows

  SVG = '<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 300 160" width="300" height="160"><rect x="10" y="10" width="280" height="140" fill="#cde"/>' \
        '<path d="M20 140L150 20L280 140Z" fill="#69c"/></svg>'.freeze
  KEY = "7391,25".freeze
  WRONG = "8888".freeze

  setup do
    require_chrome!
    @shots_dir = Dir.mktmpdir("item-shots")
    @assets_dir = Dir.mktmpdir("item-assets")
    ENV["BANCO_LESSON_SHOTS_DIR"] = @shots_dir
    Rails.application.config.x.item_assets_dir = @assets_dir
    @world = build_ui_subject(components: %w[choice number fraction matching ordering expression], approve: false)
    @session = AgentSession.find_by!(label: "ui-author")
  end

  teardown do
    ENV.delete("BANCO_LESSON_SHOTS_DIR")
    Rails.application.config.x.item_assets_dir = nil
    FileUtils.rm_rf([ @shots_dir, @assets_dir ])
  end

  # BANCO_SHOT_DIR=/some/dir keeps the shots as files for the eye.
  def draw(revision)
    Validation::ItemRenderCheck.new(revision).call
    row = ItemRender.latest_for(revision)
    if ENV["BANCO_SHOT_DIR"]
      FileUtils.mkdir_p(ENV["BANCO_SHOT_DIR"])
      row.shots.each { |s| File.binwrite(File.join(ENV["BANCO_SHOT_DIR"], "item#{revision.id}-#{JSON.parse(revision.body_json)['component']}-instance#{s['instance']}.webp"), LessonShots.read(s["sha256"])) }
    end
    row
  end

  def dump(row) = row.result["errors"].map { |e| "#{e['code']} instance #{e['instance']}: #{e['message']} (#{e['where']})" }.join("\n")

  # The host page of instance 1 of a revision, loaded in the context and ready: the module script of the host can run after the load event, so the test
  # waits for its global as the runner does and says what the page showed when it never comes.
  def open_host(ctx, revision, number = 1)
    page = ctx.create_page
    page.command("Emulation.setDeviceMetricsOverride", width: 390, height: 844, deviceScaleFactor: 1, mobile: false) # the phone, as the runner has it
    page.go_to(Validation::Harness.item_page_url(Validation::Harness.issue("irev", revision.id), number))
    assert Validation::ItemRenderRunner.wait_defined(page, 20), "the host did not define bancoItemRender: #{Validation::ItemRenderRunner.describe(page)}"
    assert page.evaluate_async("window.bancoItemRender.ready.then(arguments[0])", 20)["ok"]
    page
  end

  # [width, height] of a WebP file, from its first chunk (lossy, lossless or extended).
  def webp_size(bytes)
    assert_equal "RIFF", bytes[0, 4]
    assert_equal "WEBP", bytes[8, 4]
    case bytes[12, 4]
    when "VP8 " then bytes[26, 4].unpack("v2").map { |v| v & 0x3fff }
    when "VP8L"
      bits = bytes[21, 4].unpack1("V")
      [ (bits & 0x3fff) + 1, ((bits >> 14) & 0x3fff) + 1 ]
    when "VP8X"
      w, h = bytes[24, 6].unpack("C3C3").each_slice(3).map { |a, b, c| (a | (b << 8) | (c << 16)) + 1 }
      [ w, h ]
    else flunk "a WebP chunk this test does not know: #{bytes[12, 4].inspect}"
    end
  end

  # An item revision made by hand: one body, instances given as [display, answer, errors].
  def revision_with(component, body: {}, files: nil, instances:)
    item = Item.create!(subject: @world[:subject], key: "shot-#{component}-#{SecureRandom.hex(3)}", kind: "diagnosis_item")
    full = { schema: "banco.item/1", schema_version: 1, kind: "diagnosis_item", subject: "math", skill: skill_key("math", component), component: component,
             expected_seconds: 60, prompt: { stem_it: "Domanda di prova." } }.merge(body)
    revision = ItemRevision.create!(item: item, seq: 1, body_json: full.to_json, author_session: @session, file_sessions_json: "{}", brief_sha256: "0" * 64,
                                    files_json: files && JSON.generate(files))
    ItemValidation.create!(item_revision: revision, seq: 1, status: "passed")
    instances.each_with_index do |(display, answer, errors, solution), i|
      ItemInstance.create!(item_revision: revision, seed: i + 1, display_json: display.to_json, answer_json: answer.to_json, errors_json: (errors || []).to_json,
                           solution_json: solution&.to_json, fingerprint: Digest::SHA256.hexdigest("#{revision.id}-#{i}-#{display.to_json}"))
    end
    revision
  end

  test "every component's instances get a whole-page shot 390 CSS px wide, with the seed and the order of the choices" do
    figured = build_ui_revision(@world[:subject], @session, "choice", skill_key("math", "choice"), figure_svg: SVG)
    revisions = @world[:revisions].merge("choice with a figure" => figured)
    revisions.each do |label, revision|
      row = draw(revision)
      assert_equal "passed", row.status, "#{label}: #{dump(row)}"
      assert_equal Validation::Harness.item_version, row.harness_version
      assert row.chrome_version.present?
      stored = revision.instances.order(:id).to_a
      shots = row.shots
      assert_equal (1..stored.size).to_a, shots.map { |s| s["instance"] }, label
      shots.each do |shot|
        bytes = LessonShots.read(shot["sha256"])
        assert bytes, "#{label}: the file of instance #{shot['instance']} exists"
        assert_equal 390, shot["width"], label
        assert_equal 1, shot["scale"], label
        assert_equal "390x844-cream", shot["viewport"]
        width, height = webp_size(bytes)
        assert_equal 390, width, "#{label} instance #{shot['instance']}: the picture is 390 px wide (device scale 1)"
        assert_equal shot["height"], height, label
        assert_operator height, :>=, 200, label
        assert_equal "item-shots|#{revision.id}|#{shot['instance']}", shot["seed"]
      end
      ids = %w[o1 o2 o3 o4]
      assert_equal ids.sort, shots.first["shown_order"]["options"].sort, label if label.start_with?("choice")
    end
    # the figure drew: the page's <img> has its size
    drawn = Validation::ChromeRunner.session do |session|
      session.context do |ctx|
        page = open_host(ctx, figured)
        page.evaluate("[...document.querySelectorAll('.item img')].map((i) => i.naturalWidth)")
      end
    end
    assert_equal [ 300 ], drawn
  end

  test "the page holds no key, error value, hint or solution, in the frame of the page the student meets the item in, and the maths field is there" do
    solution = { steps: [ { text_it: "Il risultato è #{KEY}." } ], final: KEY }
    instances = [ [ { stem_it: "$3+4$" }, KEY, [ { code: "adds_wrong", value: WRONG } ], solution ] ]
    practice = revision_with("number", body: { kind: "practice_item", hints_it: [ "Parti da #{KEY}.", "Quasi #{KEY}." ] }, instances: instances)
    sitting = revision_with("number", instances: instances)
    expression = @world[:revisions]["expression"]
    pages = [ practice, sitting, expression ].map do |revision|
      Validation::ChromeRunner.session do |session|
        session.context do |ctx|
          page = open_host(ctx, revision)
          { html: page.evaluate("document.documentElement.outerHTML"), text: page.evaluate("document.body.innerText"),
            fields: page.evaluate("document.querySelectorAll('math-field').length"), checked: page.evaluate("document.querySelectorAll('input:checked').length") }
        end
      end
    end
    practice_page, sitting_page, expression_page = pages
    assert_includes practice_page[:text], "Controlla"
    assert_includes practice_page[:text], "Mostra un aiuto (1 di 2)"
    assert_includes practice_page[:text], "Mostrami la soluzione"
    assert_includes sitting_page[:text], "Invia"
    assert_includes sitting_page[:text], "Non lo so"
    assert_includes sitting_page[:text], "Come si risponde"
    assert_equal 1, expression_page[:fields], "the expression item draws MathLive's field"
    [ practice_page, sitting_page ].each do |page|
      [ KEY, "7391", WRONG, "adds_wrong", "Parti da", "Quasi" ].each { |secret| refute_includes page[:html], secret, "the DOM holds #{secret}" }
    end
    # and the host's own HTML, before any script runs
    served = Net::HTTP.get(URI(Validation::Harness.item_page_url(Validation::Harness.issue("irev", practice.id), 1)))
    [ KEY, "7391", WRONG, "adds_wrong", "Parti da", "Quasi" ].each { |secret| refute_includes served, secret }
  end

  test "practice items laid out as in production give no finding: the action bar bleeds to the card's edges on purpose" do
    options = (1..4).map { |n| { id: "o#{n}", text: "Risposta #{n}" } }
    hints = { kind: "practice_item", hints_it: [ "Primo aiuto.", "Secondo aiuto." ] }
    number = revision_with("number", body: hints.merge(unit: "cm"), instances: [ [ { stem_it: "$3+4$" }, "7", [] ], [ { stem_it: "Quanto fa $12+30$?" }, "42", [] ] ])
    choice = revision_with("choice", body: hints, instances: [ [ { options: options }, "o1", [] ], [ { options: options, stem_it: "Quale è giusta?" }, "o2", [] ] ])
    [ number, choice ].each do |revision|
      row = draw(revision)
      assert_equal "passed", row.status, dump(row)
      assert_empty row.result["errors"], dump(row)
      assert_equal 2, row.shots.size
    end
  end

  # D-335 (items 29 and 30): the help line of a number says nothing of decimals when the key is whole; a program line in a table cell is a code span, and a
  # word that fits its cell is never broken at 390 px (`overflow-wrap: break-word`, not `anywhere`).
  test "a whole-number item says no word of decimals, and a decimal one still does" do
    whole = revision_with("number", body: { kind: "practice_item" }, instances: [ [ { stem_it: "$3+4$" }, "7", [] ] ])
    decimal = revision_with("number", body: { kind: "practice_item" }, instances: [ [ { stem_it: "$3+4$" }, "7,5", [] ] ])
    accepted = revision_with("number", body: { kind: "practice_item", accept: [ "7,0" ] }, instances: [ [ { stem_it: "$3+4$" }, "7", [] ] ])
    texts = [ whole, decimal, accepted ].map do |revision|
      Validation::ChromeRunner.session { |session| session.context { |ctx| open_host(ctx, revision).evaluate("document.body.innerText") } }
    end
    assert_includes texts[0], "Scrivi il numero intero."
    refute_includes texts[0], "decimali"
    assert_includes texts[1], "Per i decimali usa la virgola."
    assert_includes texts[2], "Per i decimali usa la virgola.", "an accepted decimal form is a decimal answer"
  end

  test "a table with a code column at 390 px: program lines in the code span, no word that fits is broken, the short header stays on one line" do
    table = { header: [ "N.", "Codice", "Cosa fa" ],
              rows: [ [ "1", "[[code:CInt(x)]]", "Legge un dato per x" ], [ "2", "[[code:x \\ 100]]", "Fa x per 100" ], [ "3", "[[code:Write(x)]]", "Dà x al video" ] ] }
    revision = revision_with("choice", body: { prompt: { stem_it: "Quale riga legge un intero? Usa [[code:CInt(x)]] come esempio.", table: table } },
                                       instances: [ [ { options: (1..4).map { |n| { id: "o#{n}", text: "Riga [[code:x = #{n}]]" } } }, "o1", [] ] ])
    row = draw(revision)
    assert_equal "passed", row.status, dump(row)
    assert_empty row.result["errors"], dump(row)
    facts = Validation::ChromeRunner.session do |session|
      session.context do |ctx|
        page = open_host(ctx, revision)
        page.evaluate(<<~JS)
          (() => {
            const lines = (node) => new Set([...node.getClientRects()].map((r) => Math.round(r.top))).size
            return {
              codes: [...document.querySelectorAll(".code-span")].map((c) => ({ text: c.textContent, lines: lines(c), font: getComputedStyle(c).fontFamily })),
              raw: document.body.innerText.includes("[[code:"),
              header: [...document.querySelectorAll("th")].map((th) => { const range = document.createRange(); range.selectNodeContents(th); return { text: th.textContent, lines: lines(range) } }),
              wrap: getComputedStyle(document.querySelector("td")).overflowWrap
            }
          })()
        JS
      end
    end
    assert_equal false, facts["raw"], "a code span is drawn, not printed as it was written"
    texts = facts["codes"].map { |c| c["text"] }
    assert_equal [ "CInt(x)", "CInt(x)", "x \\ 100", "Write(x)", "x = 1", "x = 2", "x = 3", "x = 4" ].sort, texts.sort
    facts["codes"].each { |c| assert_equal 1, c["lines"], "#{c['text']} is on one line at 390 px" }
    assert_equal "break-word", facts["wrap"]
    facts["header"].select { |h| h["text"] == "N." }.each { |h| assert_equal 1, h["lines"], "the short header N. is on one line" }
  end

  test "an instance that runs out of the phone's width is reported, the others are not, and every instance is still pictured" do
    long = (1..40).map { |n| "x_{#{n}}" }.join("+")
    options = (1..4).map { |n| { id: "o#{n}", text: "Risposta #{n}" } }
    revision = revision_with("choice", instances: [
      [ { options: options }, "o1", [] ],
      # a formula in the line that says how to answer: no scroll box of its own, so it widens the page
      [ { options: options, answer_format_it: "Scrivi la somma $#{long}$." }, "o2", [] ]
    ])
    row = draw(revision)
    assert_equal "failed", row.status, dump(row)
    overflow = row.result["errors"].select { |e| e["code"] == "E-ITEM-OVERFLOW" }
    assert_equal [ 2 ], overflow.map { |e| e["instance"] }.uniq, dump(row)
    puts dump(row) if ENV["BANCO_SHOT_DIR"]
    assert_equal [ 1, 2 ], row.shots.map { |s| s["instance"] }
    assert row.shots.all? { |s| LessonShots.exist?(s["sha256"]) }
  end

  test "a figure that does not draw is reported" do
    broken = '<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 10 10"><path d="M0 0L10 10"'
    revision = revision_with("choice", files: { "assets/broken.svg" => broken }, instances: [
      [ { options: (1..4).map { |n| { id: "o#{n}", text: "Risposta #{n}" } }, figure: { asset: "assets/broken.svg", alt_it: "Un disegno rotto." } }, "o1", [] ]
    ])
    row = draw(revision)
    assert_equal "failed", row.status, dump(row)
    assert_match(/a figure did not draw/, row.result["errors"].first["message"])
  end

  test "a revision with more instances than the cap is pictured to the cap and says so" do
    Validation::Rules.with(item_render: { max_instances: 2 }) do
      row = draw(@world[:revisions]["number"])
      assert_equal "passed", row.status, dump(row)
      assert_equal 2, row.shots.size
      assert_equal 5, row.result["instances_total"]
      assert_equal 2, row.result["instances"]
      assert_equal [ "note" ], row.result["errors"].map { |e| e["level"] }
    end
  end
end
