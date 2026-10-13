require "test_helper"
require_relative "../support/page_world"

# Free pages over the agent API (D-281, SPEC B9): open, submit and its refusals, the status, the diff, the independent review.
class PagesApiTest < ActionDispatch::IntegrationTest
  include ActiveJob::TestHelper
  include PageWorld

  setup do
    @token = ApiToken.issue!(role: "agent_claude", label: "pages test")
    page_subject!
    @author = AgentSession.create!(label: "t", role: "author", agent: "test", model: "claude-sonnet-5-5")
    @reviewer = AgentSession.create!(label: "t", role: "reviewer", agent: "test", model: "gpt-5")
    @store = Dir.mktmpdir
    @saved = ENV["BANCO_PAGES_DIR"]
    ENV["BANCO_PAGES_DIR"] = @store
  end

  teardown do
    @saved ? ENV["BANCO_PAGES_DIR"] = @saved : ENV.delete("BANCO_PAGES_DIR")
    FileUtils.rm_rf(@store)
  end

  def api(path, method: :get, body: nil, as: nil, dry: false)
    headers = { "Authorization" => "Bearer #{@token}" }
    headers["X-Banco-Session"] = as.id.to_s if as
    headers["X-Banco-Dry-Run"] = "1" if dry
    on(:api, path, method: method, headers: headers, params: body, as: body ? :json : nil)
  end

  def json = response.parsed_body

  def wire(files) = files.transform_values { |bytes| bytes.dup.force_encoding("UTF-8").valid_encoding? ? bytes.dup.force_encoding("UTF-8") : { "base64" => Base64.strict_encode64(bytes) } }

  def submit(files = page_files, base: nil, dry: false, as: @author, key: "math.pages-sample")
    api("/api/v1/pages/submit", method: :post, body: { page: key, base: base, files: wire(files) }, as: as, dry: dry)
  end

  test "a dry run validates and stores nothing" do
    submit(dry: true)
    assert_response :ok, json.inspect
    assert_equal true, json["dry_run"]
    assert_match(/\A\h{64}\z/, json["bundle_sha256"])
    assert_equal 0, Page.count
    assert_no_enqueued_jobs
  end

  test "a submit stores the revision with its files, queues the validation, and a second identical submit replays" do
    assert_enqueued_with(job: ValidatePageRevisionJob) { submit }
    assert_response :created, json.inspect
    rev = PageRevision.find(json["revision_id"])
    assert_equal 1, rev.seq
    assert_equal %w[main.mjs maths.mjs], rev.files.map(&:path).sort
    assert_equal @author.id, rev.author_session_id
    assert_equal File.binread(PageWorld::FIXTURES.join("math.pages-sample/main.mjs")), Pages::Store.read(rev.files.find_by(path: "main.mjs").sha256)
    submit(base: rev.id)
    assert_response :ok
    assert_equal true, json["replayed"]
    assert_equal 1, PageRevision.count
  end

  test "a changed page needs the latest as its base; a stale base is refused" do
    submit
    first = json["revision_id"]
    changed = page_files { |f| f["maths.mjs"] += "\n// fix" }
    submit(changed)
    assert_response :conflict
    assert_equal "E-STALE-BASE", json["code"]
    submit(changed, base: first)
    assert_response :created
    second = PageRevision.find(json["revision_id"])
    assert_equal [ 2, first ], [ second.seq, second.base_revision_id ]
  end

  test "a bundle with an error is refused with the code and stores nothing" do
    submit(page_files { |f| f["main.mjs"] += "\nfetch('x')" })
    assert_response :unprocessable_entity
    assert_equal "E-PAGE-API", json["code"]
    assert_equal 0, PageRevision.count
    submit(page_files { |f| f.delete("main.mjs") })
    assert_equal "E-PAGE-FILES", json["code"]
  end

  test "the session must be an author's, and the key a page key of a known subject" do
    submit(as: @reviewer)
    assert_response :unprocessable_entity
    assert_equal "E-SESSION-ROLE", json["code"]
    submit(key: "Math.x")
    assert_equal "E-FILES", json["code"]
    submit(key: "nosuch.thing")
    assert_response :not_found
    api("/api/v1/pages/submit", method: :post, body: { page: "math.pages-sample", files: {} }, as: @author)
    assert_equal "E-FILES", json["code"]
  end

  test "the reserved browser matrix key is refused by the API and by the store" do
    files = page_files { |f| f["page.json"] = f["page.json"].sub("math.pages-sample", "math.pages-selftest") }
    submit(files, key: "math.pages-selftest")
    assert_response :unprocessable_entity, json.inspect
    assert_equal "E-PAGE-TEXT", json["code"]
    assert_equal 0, Page.count
    outcome = Validation::PageChecks.call(files, key: "math.pages-selftest", subject: "math", operator: true)
    assert_raises(ArgumentError) { Pages::Submit.store(key: "math.pages-selftest", subject: page_subject!, outcome: outcome, warnings: [], author: @author) }
    assert_equal 0, Page.count
  end

  test "binary assets travel as base64 and are checked by their bytes" do
    png = File.binread(PageWorld::FIXTURES.join("math.pages-selftest/assets/checker.png"))
    submit(page_files { |f| f["assets/checker.png"] = png })
    assert_response :created, json.inspect
    assert_equal png, Pages::Store.read(PageRevision.last.files.find_by(path: "assets/checker.png").sha256)
    submit(page_files { |f| f["assets/other.png"] = "nope" })
    assert_equal "E-PAGE-FILES", json["code"]
  end

  test "open gives the skeleton for a new key and the latest files for an existing one" do
    api("/api/v1/pages/math.new-page")
    assert_response :ok
    assert_equal false, json["exists"]
    assert_equal "banco.page/1", JSON.parse(json["files"]["page.json"])["schema"]
    assert_includes json["files"]["main.mjs"], "banco.init"
    assert_equal [ "three" ], json["libs"]
    submit
    api("/api/v1/pages/math.pages-sample")
    assert_equal true, json["exists"]
    assert_equal "math.pages-sample", JSON.parse(json["files"]["page.json"])["key"]
    api("/api/v1/pages/nosuch.thing")
    assert_response :not_found
  end

  test "the status, the list of a subject and the diff" do
    submit
    first = PageRevision.last
    api("/api/v1/page-revisions/#{first.id}")
    assert_equal "pending", json["validation"]["status"]
    submit(page_files { |f| f["maths.mjs"] = "export const meet = () => null\n" }, base: first.id)
    second = PageRevision.last
    api("/api/v1/subjects/math/pages")
    assert_equal [ [ "math.pages-sample", second.id ] ], json["rows"].map { |r| [ r["page"], r["latest_revision_id"] ] }
    api("/api/v1/page-revisions/#{second.id}/diff")
    changed = json["files"].find { |f| f["path"] == "maths.mjs" }
    assert_equal "changed", changed["status"]
    assert_includes changed["diff"], "-export function meet"
    assert_includes changed["diff"], "+export const meet = () => null"
    assert_equal "same", json["files"].find { |f| f["path"] == "main.mjs" }["status"]
    assert_equal first.id, json["base_revision_id"]
  end

  test "shots are listed from the verdict and served by content address" do
    submit
    rev = PageRevision.last
    bytes = "RIFF....WEBPfake"
    ENV["BANCO_PAGE_SHOTS_DIR"] = Dir.mktmpdir
    sha = PageShots.put(bytes)
    PageValidation.create!(page_revision: rev, kit_version: "1.0", status: "passed", harness_version: "t", result_json: JSON.generate("errors" => []),
                           shots_json: JSON.generate([ { "kind" => "ready", "seed_index" => 0, "width" => 1280, "height" => 400, "sha256" => sha, "bytes" => bytes.size } ]))
    api("/api/v1/page-revisions/#{rev.id}/shots")
    assert_equal [ true ], json["shots"].map { |s| s["available"] }
    api("/api/v1/page-revisions/#{rev.id}/shots/#{sha}")
    assert_equal bytes, response.body
    api("/api/v1/page-revisions/#{rev.id}/shots/#{'0' * 64}")
    assert_response :not_found
  ensure
    FileUtils.rm_rf(ENV.delete("BANCO_PAGE_SHOTS_DIR").to_s)
  end

  def review_doc(rev, **over)
    { schema: "banco.page_review/1", schema_version: 1, revision: rev.id.to_s,
      checklist: (1..11).map { |i| { id: i, result: "pass", evidence: "Ho controllato il punto numero #{i} sul codice e sulle immagini." } }, findings: [] }.merge(over)
  end

  test "the review: an independent session on another family files eleven points and findings quoted from a file" do
    submit
    rev = PageRevision.last
    api("/api/v1/page-revisions/#{rev.id}/review", as: @reviewer)
    assert_response :ok, json.inspect
    assert_equal 11, json["checklist"].size
    assert_equal %w[main.mjs maths.mjs page.json], json["files"].keys.sort
    assert_equal rev.id, json["diff"]["revision_id"]
    finding = { severity: "minor", file: "maths.mjs", line: 3, quote: "if (a === c) return null", problem_it: "Il caso è chiaro.", fix_it: "Va bene così, nessuna modifica." }
    api("/api/v1/page-revisions/#{rev.id}/review", method: :post, body: { review: review_doc(rev, findings: [ finding.merge(quote: "not in the file") ]) }, as: @reviewer)
    assert_equal "E-QUOTE-NOT-FOUND", json["code"]
    api("/api/v1/page-revisions/#{rev.id}/review", method: :post, body: { review: review_doc(rev, findings: [ finding ]) }, as: @reviewer, dry: true)
    assert_response :ok
    assert_equal 0, PageReview.count
    api("/api/v1/page-revisions/#{rev.id}/review", method: :post, body: { review: review_doc(rev, findings: [ finding ]) }, as: @reviewer)
    assert_response :created, json.inspect
    assert_equal({ "minor" => 1 }, json["counts"])
    api("/api/v1/page-revisions/#{rev.id}/review", method: :post, body: { review: review_doc(rev) }, as: @reviewer)
    assert_equal "E-SESSION-NOT-INDEPENDENT", json["code"]
  end

  test "a reviewer of the same model family as an author is refused; so is the author's own session" do
    submit
    rev = PageRevision.last
    same_family = AgentSession.create!(label: "t", role: "reviewer", agent: "test", model: "claude-opus-5-5")
    api("/api/v1/page-revisions/#{rev.id}/review", as: same_family)
    assert_response :unprocessable_entity
    assert_equal "E-PROVIDER-NOT-ALLOWED", json["code"]
    api("/api/v1/page-revisions/#{rev.id}/review", method: :post, body: { review: review_doc(rev) }, as: @author)
    assert_equal "E-SESSION-ROLE", json["code"]
    api("/api/v1/page-revisions/#{rev.id}/review", as: @author)
    assert_response :ok, "the author reads the page it wrote"
  end

  test "a review of a superseded revision is refused" do
    submit
    first = PageRevision.last
    submit(page_files { |f| f["maths.mjs"] += "\n// two" }, base: first.id)
    api("/api/v1/page-revisions/#{first.id}/review", method: :post, body: { review: review_doc(first) }, as: @reviewer)
    assert_response :conflict
    assert_equal "E-STALE-BASE", json["code"]
  end

  test "no API route decides: nothing under pages or page-revisions approves" do
    assert_empty Rails.application.routes.routes.map { |r| r.path.spec.to_s }.grep(%r{api/v1/pages?(-revisions)?/.*(approve|decide|confirm)})
  end
end
