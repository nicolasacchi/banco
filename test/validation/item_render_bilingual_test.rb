require "test_helper"
require_relative "../support/course_rows"
require_relative "../support/validation_servers"
require_relative "../support/chrome_helper"

# The bilingual items (D-402) in the server's Chrome, at the phone's 390 px: the pictures of instance 1 (as drawn, and with the translation open, one file each),
# the gap above a translation line, the `[[it:..]]` span, an item whose material is target-only (no `_it`), and the legend of a matching's right-hand labels.
# Needs Chrome (BROWSER_PATH); skips without. BANCO_SHOT_DIR=/some/dir keeps the pictures as files for the eye.
class ItemRenderBilingualTest < ActiveSupport::TestCase
  include CourseRows
  include ChromeHelper

  setup do
    require_chrome!
    @shots_dir = Dir.mktmpdir("item-shots-bilingual")
    ENV["BANCO_LESSON_SHOTS_DIR"] = @shots_dir
    @english = build_course(subject_key: "english")
    @session = AgentSession.create!(label: "bilingual-author", role: "author")
  end

  teardown do
    ENV.delete("BANCO_LESSON_SHOTS_DIR")
    FileUtils.rm_rf(@shots_dir)
  end

  def revision_with(component, prompt:, instances:, body: {})
    item = Item.create!(subject: @english, key: "bil-#{component}-#{SecureRandom.hex(3)}", kind: "practice_item")
    full = { schema: "banco.item/1", schema_version: 1, kind: "practice_item", subject: "english", bilingual: true, skill: "english.demo", component: component,
             expected_seconds: 60, prompt: prompt }.merge(body)
    revision = ItemRevision.create!(item: item, seq: 1, body_json: JSON.generate(full), author_session: @session, file_sessions_json: "{}", brief_sha256: "0" * 64)
    ItemValidation.create!(item_revision: revision, seq: 1, status: "passed")
    instances.each_with_index do |(display, answer), i|
      ItemInstance.create!(item_revision: revision, seed: i + 1, display_json: JSON.generate(display), answer_json: JSON.generate(answer), errors_json: "[]",
                           fingerprint: Digest::SHA256.hexdigest("#{revision.id}-#{i}-#{JSON.generate(display)}"))
    end
    revision
  end

  # A choice that is a gap in a sentence. With `material: false` the sentence and the options are target-only (the form-material rule): no `stem_it`, no `text_it`.
  def choice(material: true, prompt: {})
    options = %w[am is are].each_with_index.map { |w, i| { id: "o#{i + 1}", text: w }.merge(material ? { text_it: "essere" } : {}) }
    display = { stem_en: "My brother ___ thirteen.", options: options }
    display[:stem_it] = "Mio fratello ___ tredici anni." if material
    steps = { steps_en: %w[Read. Choose.], steps_it: %w[Leggi. Scegli.], answer_format_en: "Choose one word.", answer_format_it: "Scegli una parola." }
    revision_with("choice", prompt: { stem_en: "Choose the right form.", stem_it: "Scegli la forma giusta." }.merge(prompt), body: steps, instances: [ [ display, "o2" ], [ display, "o2" ] ])
  end

  def matching
    left = [ { id: "l1", text: "dog", text_it: "cane" }, { id: "l2", text: "cat", text_it: "gatto" } ]
    right = [ { id: "r1", text: "it barks", text_it: "abbaia" }, { id: "r2", text: "it purrs", text_it: "fa le fusa" } ]
    revision_with("matching", prompt: { stem_en: "Match each animal.", stem_it: "Abbina ogni animale." }, instances: [ [ { left: left, right: right }, { "l1" => "r1", "l2" => "r2" } ] ])
  end

  def keep(row, label)
    return unless ENV["BANCO_SHOT_DIR"]

    FileUtils.mkdir_p(ENV["BANCO_SHOT_DIR"])
    row.shots.each { |s| File.binwrite(File.join(ENV["BANCO_SHOT_DIR"], "#{label}-instance#{s['instance']}#{"-#{s['state']}" if s['state']}.webp"), LessonShots.read(s["sha256"])) }
  end

  def draw(revision, label)
    Validation::ItemRenderCheck.new(revision).call
    row = ItemRender.latest_for(revision)
    keep(row, label)
    row
  end

  # The host page of instance 1, loaded and ready; yields the page to a block that measures it.
  def with_host(revision, translation: true)
    Validation::ChromeRunner.session do |session|
      session.context do |ctx|
        page = ctx.create_page
        page.command("Emulation.setDeviceMetricsOverride", width: 390, height: 844, deviceScaleFactor: 1, mobile: false)
        page.go_to(Validation::Harness.item_page_url(Validation::Harness.issue("irev", revision.id), 1, translation: translation))
        assert Validation::ItemRenderRunner.wait_defined(page, 20), "the host did not define bancoItemRender: #{Validation::ItemRenderRunner.describe(page)}"
        result = page.evaluate_async("window.bancoItemRender.ready.then(arguments[0])", 20)
        assert result["ok"], result.inspect
        yield page, result
      end
    end
  end

  # [above, below, text, parent] of every block translation line that is shown, in CSS px: the distance from the bottom of what is above it (the previous sibling, or
  # the text of its parent) to its top, and from its bottom to the top of what follows it (the next sibling of it or of its parents). A line that touches the text
  # above or below it has a gap under 3.
  GAPS = <<~JS.freeze
    JSON.stringify([...document.querySelectorAll(".tr")].filter((n) => getComputedStyle(n).display === "block").map((n) => {
      const shown = (e) => e && getComputedStyle(e).display !== "none"
      const prev = shown(n.previousElementSibling) ? n.previousElementSibling : null
      let above = prev ? prev.getBoundingClientRect().bottom : null
      if (above === null) {
        const own = [...n.parentElement.childNodes].filter((c) => c !== n && !(c.nodeType === 1 && c.classList.contains("tr")))
        if (own.length === 0) return null
        const range = document.createRange(); range.setStartBefore(own[0]); range.setEndAfter(own[own.length - 1])
        above = range.getBoundingClientRect().bottom
      }
      let below = null
      for (let up = n; up && up !== document.body && below === null; up = up.parentElement) {
        let next = up.nextElementSibling
        while (next && !shown(next)) next = next.nextElementSibling
        if (next && next.getBoundingClientRect().top >= n.getBoundingClientRect().top) below = next.getBoundingClientRect().top - n.getBoundingClientRect().bottom
      }
      const round = (x) => (x === null ? null : Math.round(x * 10) / 10)
      return [round(n.getBoundingClientRect().top - above), round(below), n.textContent.slice(0, 30), n.parentElement.className || n.parentElement.tagName]
    }).filter(Boolean))
  JS

  test "instance 1 has a picture as drawn and one with the translation open, in two files of their own; the list names the state" do
    revision = choice
    row = draw(revision, "choice")
    assert_equal "passed", row.status, row.result["errors"].inspect
    assert_equal [ [ 1, nil ], [ 1, "tr" ], [ 2, nil ] ], row.shots.map { |s| [ s["instance"], s["state"] ] }
    plain, open = row.shots.values_at(0, 1)
    assert_not_equal plain["sha256"], open["sha256"], "the translation shows more: the two pictures differ"
    assert_operator open["height"], :>, plain["height"], "the open picture is taller: it holds the Italian lines"
    assert_equal [ plain["seed"], plain["shown_order"] ], [ open["seed"], open["shown_order"] ]
  end

  test "with the translation open no block translation line touches the text above or below it, at 390 px" do
    with_host(choice) do |page, result|
      gaps = JSON.parse(page.evaluate(GAPS))
      assert_operator gaps.size, :>=, 3, "the instruction, the sentence and the format have a block line: #{gaps.inspect}"
      touching = gaps.select { |above, below, *| above < 3 || (below && below < 3) }
      assert_empty touching, "a translation line touches the text above or below it: #{touching.inspect}"
      assert_empty result["findings"].map { |f| "#{f['code']} #{f['message']}" }
    end
  end

  test "[[it:..]] draws an Italian span (lang it) and no markup is printed as text" do
    revision = choice(prompt: { stem_en: "Say it in English: [[it:Mio fratello ha tredici anni]].", stem_it: "Dillo in inglese." })
    with_host(revision, translation: false) do |page, result|
      assert_equal [ "it", "Mio fratello ha tredici anni" ], JSON.parse(page.evaluate(%(JSON.stringify([...document.querySelectorAll(".prompt span.lang-it")].map((n) => [n.getAttribute("lang"), n.textContent])[0]))))
      assert_empty result["findings"].map { |f| "#{f['code']} #{f['message']}" }, "no E-ITEM-RENDER «markup printed as text»"
    end
  end

  test "an item with target-only material draws no translation line and no button on it, and keeps the instruction's" do
    with_host(choice(material: false)) do |page, result|
      shown = JSON.parse(page.evaluate(%(JSON.stringify([...document.querySelectorAll(".tr")].filter((n) => getComputedStyle(n).display !== "none").map((n) => [n.textContent, !!n.closest(".instance-stem, label.option")])))))
      assert_equal [ "Scegli la forma giusta.", "Leggi.", "Scegli.", "Scegli una parola." ], shown.reject { |_, material| material }.map(&:first)
      assert_equal [], shown.select { |_, material| material }, "no translation of the sentence or of the options"
      assert_equal 0, page.evaluate(%(document.querySelectorAll(".item-body .tr-toggle").length))
      assert_empty result["findings"].map { |f| "#{f['code']} #{f['message']}" }
    end
  end

  test "a matching's right-hand labels have their Italian in a legend under the rows, shown with the translation" do
    revision = matching
    with_host(revision) do |page, _result|
      legend = JSON.parse(page.evaluate(%(JSON.stringify([...document.querySelectorAll(".match-legend li")].map((n) => [n.textContent, getComputedStyle(n.parentElement).display])))))
      assert_equal [ [ "it barks = abbaia", "block" ], [ "it purrs = fa le fusa", "block" ] ], legend.sort, "one line for each right-hand label (shuffled like the select's options)"
      rows = JSON.parse(page.evaluate(%(JSON.stringify([...document.querySelectorAll(".match-row")].map((n) => n.getBoundingClientRect().bottom)))))
      top = page.evaluate(%(document.querySelector(".match-legend").getBoundingClientRect().top))
      assert_operator top, :>=, rows.max, "the legend is under the rows"
    end
    with_host(revision, translation: false) do |page, _result|
      assert_equal "none", page.evaluate(%(getComputedStyle(document.querySelector(".match-legend")).display))
    end
    draw(revision, "matching")
  end
end
