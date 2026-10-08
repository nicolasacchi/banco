require "test_helper"
require_relative "../support/validation_fixtures"
require_relative "../support/course_rows"
require_relative "../support/chrome_helper"
require_relative "../support/validation_servers"

# Phase 1b S1: practice items go through the item pipeline (submit, review, blind solve)
# without touching the diagnosis (A11): kinds, hints stored apart from the display,
# the 13-point review, items list --kind. No Chrome is needed (static items).
class PracticeItemsTest < ActionDispatch::IntegrationTest
  include ActiveJob::TestHelper
  include CourseRows
  include ChromeHelper
  F = ValidationFixtures

  setup do
    @token = ApiToken.issue!(role: "agent_claude", label: "practice test")
    build_course
    @author = session!(:author, "claude-opus-5-5")
    @reviewer = session!(:reviewer, "gpt-5.2")
    @solver = session!(:solver, "kimi-k3")
  end

  def session!(role, model) = AgentSession.create!(label: "t", role: role.to_s, agent: "test", model: model)

  def api(path, method: :get, body: nil, as: nil, headers: {})
    headers = { "Authorization" => "Bearer #{@token}" }.merge(headers)
    headers["X-Banco-Session"] = as.id.to_s if as
    on(:api, path, method: method, headers: headers, params: body, as: body ? :json : nil)
  end

  def json = response.parsed_body

  def submit_item(key, item, base: nil)
    api("/api/v1/work/submit", method: :post, body: { item: key, base: base, files: F.files_for(item) }, as: @author)
  end

  def passed_revision(key, item)
    submit_item(key, item)
    assert_response :accepted, json.inspect
    perform_enqueued_jobs
    revision = ItemRevision.find(json["revision_id"])
    assert_equal "passed", revision.status, revision.latest_validation&.codes_json
    revision
  end

  def checklist(count)
    (1..count).map { |i| { "id" => i, "result" => "pass", "evidence" => "Controllato sull'istanza numero #{i}: nessun difetto trovato qui." } }
  end

  def review_doc(revision, count)
    { "schema" => "banco.review/1", "schema_version" => 1, "revision" => revision.id.to_s, "checklist" => checklist(count), "findings" => [] }
  end

  def review(revision, count)
    api("/api/v1/revisions/#{revision.id}/review", method: :post, body: { review: review_doc(revision, count) }, as: @reviewer)
  end

  test "a practice item passes, keeps its kind and its hints apart from the display" do
    revision = passed_revision("p-eq-1", F.practice_item)
    assert_equal "practice_item", revision.item.kind
    assert_equal 12, revision.instances.count
    first = revision.instances.order(:id).first
    assert_equal F::HINTS, JSON.parse(first.hints_json)
    assert_not_includes first.display_json, "togli"
    assert_equal Brief.find("practice-item").sha256, revision.brief_sha256
  end

  test "a diagnosis item stores no hints and keeps the diagnosis brief" do
    revision = passed_revision("d-eq-1", F.static_item)
    assert_equal "diagnosis_item", revision.item.kind
    assert_nil revision.instances.first.hints_json
    assert_equal Brief.find("diagnosis-item").sha256, revision.brief_sha256
  end

  test "an instance's own hints win over the item's" do
    item = F.practice_item
    item["instances"][0]["hints_it"] = [ "Guarda il termine noto.", "Spostalo dall'altra parte." ]
    revision = passed_revision("p-eq-2", item)
    stored = revision.instances.order(:id).map { |i| JSON.parse(i.hints_json) }
    assert_equal [ "Guarda il termine noto.", "Spostalo dall'altra parte." ], stored.first
    assert_equal F::HINTS, stored.last
  end

  test "hints on an instance of a diagnosis item are E-HINTS" do
    item = F.static_item
    item["instances"][0]["hints_it"] = [ "Uno.", "Due." ]
    result = Validation::ItemRunner.new(files: F.files_for(item), context: F.context).call
    assert_includes result.findings.map(&:code), "E-HINTS"
  end

  test "a good practice item has no hint or pool finding" do
    result = Validation::ItemRunner.new(files: F.files_for(F.practice_item), context: F.context).call
    assert_equal "passed", result.status, result.findings.map(&:to_h).inspect
    assert_empty result.findings.map(&:code) & %w[E-HINTS E-HINT-KEY W-HINT-OPTION E-PRACTICE-POOL W-PRACTICE-CODE-SPARSE]
  end

  test "a number taken from the display is allowed in a hint; the key is not" do
    item = F.practice_item
    item["instances"][0]["hints_it"] = [ "Parti da 13 e da 2.", "Fai la differenza.", "Scrivi il numero." ]
    result = Validation::ItemRunner.new(files: F.files_for(item), context: F.context).call
    assert_not_includes result.findings.map(&:code), "E-HINT-KEY"
    # instance 1 shows x+2=13 (key 11); instance 2 shows x+3=15 (key 12)
    leak = Validation::ItemRunner.new(files: F.files_for(F.practice_item({ "hints_it" => [ "Guarda.", "Il numero e 11." ] })), context: F.context).call
    assert_includes leak.findings.map(&:code), "E-HINT-KEY"
  end

  test "a practice item cannot become a diagnosis item or the reverse" do
    revision = passed_revision("p-eq-3", F.practice_item)
    submit_item("p-eq-3", F.static_item, base: revision.id)
    assert_response :unprocessable_entity
    assert_equal "E-FILES", json["code"]
    assert_match(/practice item/, json["message"])
  end

  test "items list --kind separates the two kinds and each row carries its kind" do
    diag = passed_revision("d-eq-2", F.static_item)
    prac = passed_revision("p-eq-4", F.practice_item)
    api("/api/v1/items?subject=math")
    assert_equal({ diag.id => "diagnosis_item", prac.id => "practice_item" }, json["rows"].to_h { |r| [ r["revision_id"], r["kind"] ] })
    api("/api/v1/items?subject=math&kind=practice")
    assert_equal [ prac.id ], json["rows"].map { |r| r["revision_id"] }
    api("/api/v1/items?subject=math&kind=diagnosis")
    assert_equal [ diag.id ], json["rows"].map { |r| r["revision_id"] }
    api("/api/v1/items?kind=testlet")
    assert_response :not_found
  end

  test "a practice item is invisible to the diagnosis: stage, reserve, blueprint candidates, coverage, home" do
    passed_revision("d-eq-3", F.static_item)
    approve_graph!(@subject, @graph)
    before = { stage: SubjectStage.for(@subject), reserve: Item.reserve(@subject).pluck(:key), home: Teacher::Home.new.rows.map(&:to_h) }
    api("/api/v1/subjects/math/blueprint")
    candidates = json
    revision = passed_revision("p-eq-5", F.practice_item)
    assert_equal before[:stage], SubjectStage.for(@subject)
    assert_equal before[:reserve], Item.reserve(@subject).pluck(:key)
    assert_equal before[:home], Teacher::Home.new.rows.map(&:to_h)
    api("/api/v1/subjects/math/blueprint")
    assert_equal candidates, json
    assert_equal [ "d-eq-3" ], Item.diagnosis.pluck(:key)
    assert_equal [ "p-eq-5" ], Item.practice.pluck(:key)
    info = Validation::ItemInfo.for(revision)
    assert_equal "practice_item", info.kind
  end

  test "the review of a practice item has 13 points, any other has 11 (E-REVIEW-CHECKLIST)" do
    prac = passed_revision("p-eq-6", F.practice_item)
    diag = passed_revision("d-eq-4", F.static_item)
    api("/api/v1/revisions/#{prac.id}/review", as: @reviewer)
    assert_equal (1..13).to_a, json["checklist"].map { |c| c["id"] }
    assert_equal F::HINTS, json["instances"].first["hints_it"]
    api("/api/v1/revisions/#{diag.id}/review", as: @reviewer)
    assert_equal (1..11).to_a, json["checklist"].map { |c| c["id"] }

    review(prac, 11)
    assert_response :unprocessable_entity
    assert_equal "E-REVIEW-CHECKLIST", json["code"]
    review(diag, 13)
    assert_response :unprocessable_entity
    assert_equal "E-REVIEW-CHECKLIST", json["code"]
    review(diag, 12)
    assert_equal "E-REVIEW-CHECKLIST", json["code"]
    review(prac, 13)
    assert_response :created, json.inspect
    review(diag, 11)
    assert_response :created, json.inspect
  end

  test "solve open never carries hints, messages or solutions" do
    revision = passed_revision("p-eq-7", F.practice_item)
    api("/api/v1/revisions/#{revision.id}/solve", as: @solver)
    assert_response :ok, json.inspect
    text = response.body
    F::HINTS.each { |h| assert_not_includes text, h }
    assert_not_includes text, "hints"
    assert_not_includes text, "Togli"
    assert_equal 12, json["instances"].size
    assert(json["instances"].all? { |i| i.keys.sort == %w[display instance] })
  end

  test "a blueprint check refuses a practice item pinned by revision id" do
    revision = passed_revision("p-eq-8", F.practice_item)
    info = Validation::ItemInfo.lookup.call(revision.id.to_s)
    findings = Validation::Findings.new
    Validation::BlueprintChecks.pinned([ revision.id ], F::SKILL, "/entries/0/items", Validation::ItemInfo.lookup, findings)
    assert_includes findings.map(&:code), "E-BLUEPRINT-PRACTICE-ITEM"
    assert_equal "practice_item", info.kind
  end

  test "a generated practice item keeps the hints its generator returns, else the item's" do
    require_chrome!
    generator = <<~JS
      export function generate(seed, rng) {
        const a = rng.int(2, 40);
        const c = a + rng.int(2, 60);
        const out = {
          display: { stem_it: "Risolvi $x+" + a + "=" + c + "$." },
          answer: String(c - a),
          errors: [{ code: "sign_error", value: String(c + a) }],
          solution: { steps: [{ text_it: "Togli " + a + " da entrambi i lati." }], final: "x = " + (c - a) }
        };
        if (seed % 2 === 0) out.hints_it = ["Guarda il termine noto.", "Toglilo dai due lati."];
        return out;
      }
    JS
    item = F.generated_item("kind" => "practice_item", "level" => 1, "hints_it" => F::HINTS)
    files = F.generated_files(item, generator: generator)
    result = Validation::ItemRunner.new(files: files, context: F.context, harness_token: stage_token(files)).call
    assert_equal "passed", result.status, result.findings.map(&:to_h).inspect
    hints = result.instances.map { |i| i[:hints] }
    assert_includes hints, F::HINTS
    assert_includes hints, [ "Guarda il termine noto.", "Toglilo dai due lati." ]
    assert_equal 24, hints.size
  end
end
