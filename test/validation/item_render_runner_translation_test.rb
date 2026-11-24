require "test_helper"
require_relative "../support/course_rows"

# The item shots of a bilingual item (D-402): the first instance is drawn a second time with the Italian translation open (`?tr=1`), and that shot says
# `state: "tr"`. A legacy item is drawn exactly as before. A stand-in for Chrome records the pages it is sent to; the real browser is the render
# host's own test (it needs BROWSER_PATH).
class ItemRenderRunnerTranslationTest < ActiveSupport::TestCase
  include CourseRows

  # What the runner asks of a page, answered by one that draws everything at 600 px.
  class FakePage
    attr_reader :urls, :boxes

    def initialize = (@urls = []; @boxes = [])
    def command(name, **options) = name == "Page.captureScreenshot" ? { "data" => Base64.strict_encode64("RIFFxxxxWEBP") } : @boxes << options && {}
    def go_to(url) = @urls << url
    def evaluate(script) = script.start_with?("typeof") ? true : 600
    def evaluate_async(_script, _timeout) = { "ok" => true, "height" => 600, "findings" => [], "exceptions" => [] }
    def close = nil
  end

  class FakeSession
    attr_reader :page

    def initialize(page) = @page = page
    def context = yield(Struct.new(:page) { def create_page = page }.new(@page))
    def version = "fake"
  end

  class FakeStore
    attr_reader :put_count

    def put(bytes) = (@put_count = @put_count.to_i + 1; Digest::SHA256.hexdigest("#{bytes}#{@put_count}"))
  end

  setup { @english = build_course(subject_key: "english") }

  def revision(bilingual:, instances: 3)
    item = Item.create!(subject: @english, key: "shot-#{SecureRandom.hex(3)}", kind: "practice_item")
    body = { schema: "banco.item/1", schema_version: 1, kind: "practice_item", subject: "english", skill: "english.demo", component: "choice", expected_seconds: 60,
             prompt: { stem_it: "Quale parola?" } }
    body[:bilingual] = true if bilingual
    revision = ItemRevision.create!(item: item, seq: 1, body_json: JSON.generate(body), file_sessions_json: "{}")
    instances.times do |i|
      options = (1..3).map { |n| { id: "o#{n}", text: "word #{n} #{i}" } }
      ItemInstance.create!(item_revision: revision, seed: i + 1, display_json: JSON.generate(options: options), answer_json: JSON.generate("o2"),
                           errors_json: "[]", fingerprint: SecureRandom.hex(8))
    end
    revision
  end

  def draw(revision)
    page = FakePage.new
    result = Validation::ItemRenderRunner.new(FakeSession.new(page), revision: revision, token: "tok", store: FakeStore.new).call
    [ result, page ]
  end

  test "a bilingual item has a second shot of instance 1 with the translation open, and only of the first instance" do
    result, page = draw(revision(bilingual: true))
    assert_equal "passed", result.status
    assert_equal [ [ 1, nil ], [ 1, "tr" ], [ 2, nil ], [ 3, nil ] ], result.shots.map { |s| [ s["instance"], s["state"] ] }
    assert_equal [ false, true, false, false ], page.urls.map { |u| u.include?("&tr=1") }
    assert_equal %w[1 1 2 3], page.urls.map { |u| u[/[?&]n=(\d+)/, 1] }
    assert_equal result.shots.size, result.shots.map { |s| s["sha256"] }.uniq.size
    tr, plain = result.shots.values_at(1, 0)
    assert_equal [ plain["seed"], plain["shown_order"] ], [ tr["seed"], tr["shown_order"] ], "the same shuffle: the two pictures differ only by the translation"
    assert_equal "tr", result.timings.find { |t| t["state"] }["state"]
  end

  test "a legacy item is drawn exactly as before: one shot per instance, no state, no tr page" do
    result, page = draw(revision(bilingual: false))
    assert_equal [ 1, 2, 3 ], result.shots.map { |s| s["instance"] }
    assert(result.shots.none? { |s| s.key?("state") })
    assert(page.urls.none? { |u| u.include?("tr=1") })
    assert(result.timings.none? { |t| t.key?("state") })
  end

  test "the host address asks for the translation only when told to" do
    plain = Validation::Harness.item_page_url("tok", 2)
    assert_equal "http://127.0.0.1:#{Validation::Harness.base_url[/\d+\z/]}/h/tok/item-render.html?n=2&theme=cream", plain
    assert_equal "#{plain}&tr=1", Validation::Harness.item_page_url("tok", 2, translation: true)
  end

  test "the rule is one instance and says so" do
    assert_equal 1, Validation::Rules.get(:item_render, :translation_instances)
  end

  test "the shot meta says the state only for the translation picture" do
    revision = revision(bilingual: true)
    presentation = Items::ShotPresentation.call(revision, Items::ShotPresentation.instance(revision, 1), 1)
    assert_equal({ "instance" => 1, "seed" => presentation[:seed], "shown_order" => presentation[:shown_order] }, Items::ShotPresentation.meta(presentation))
    assert_equal "tr", Items::ShotPresentation.meta(presentation, state: "tr")["state"]
    assert Items::ShotPresentation.translation?(revision)
    refute Items::ShotPresentation.translation?(revision(bilingual: false))
  end
end
