require "test_helper"
require_relative "../support/validation_fixtures"
require_relative "../support/course_rows"
require_relative "../support/validation_servers"
require_relative "../support/chrome_helper"

# The content agent's cycle over the API: submit, validate, status, open, dry run.
class WorkApiTest < ActionDispatch::IntegrationTest
  include ActiveJob::TestHelper
  include CourseRows
  include ChromeHelper
  F = ValidationFixtures

  setup do
    @token = ApiToken.issue!(role: "agent_claude", label: "work test")
    build_course
    Validation::DryRun.clear_cache
  end

  def auth = { "Authorization" => "Bearer #{@token}" }

  def api(path, method: :get, body: nil, headers: {})
    on(:api, path, method: method, headers: auth.merge(headers), params: body, as: body ? :json : nil)
  end

  # One session per role for the whole test (A-04).
  def session_of(role)
    @sessions ||= {}
    @sessions[role] ||= AgentSession.create!(label: "test", role: role.to_s, agent: "test", model: "claude-test")
  end

  # A submission of verify.mjs alone is the verifier's; any other is the author's.
  def submit(item, files, base: nil, dry: false, as: nil)
    as ||= files.keys == [ "verify.mjs" ] ? :verifier : :author
    headers = { "X-Banco-Session" => session_of(as).id.to_s }
    headers["X-Banco-Dry-Run"] = "1" if dry
    api("/api/v1/work/submit", method: :post, body: { item: item, base: base, files: files }, headers: headers)
  end

  # Other test processes share the one Chrome lock: a dry run that finds it taken waits and asks again.
  def submit_when_chrome_is_free(item, files, base: nil)
    60.times do
      submit(item, files, base: base, dry: true)
      return unless response.status == 409 && json["code"] == "E-CHROME-BUSY"

      sleep 2
    end
  end

  def json = response.parsed_body

  test "a static item: submit stores a revision and queues the validation; the job validates; status says passed" do
    assert_enqueued_with(job: ValidateItemRevisionJob) { submit("eq-1", F.files_for(F.static_item)) }
    assert_response :accepted
    record_example "work submit", "accepted"
    revision_id = json["revision_id"]
    assert_equal "validating", json["status"]
    assert_equal false, json["replayed"]
    assert_equal 1, json["seq"]

    api("/api/v1/work/revisions/#{revision_id}")
    assert_equal "validating", json["status"]
    assert_equal false, json["settled"]
    assert_equal Validation::Rules.version, json["current_rules_version"]
    assert_equal 0, json["queue_ahead"]

    perform_enqueued_jobs
    api("/api/v1/work/revisions/#{revision_id}")
    assert_equal "passed", json["status"], json.inspect
    record_example "work status", "passed"
    assert_equal true, json["settled"]
    assert_equal 3, json["instances"]
    assert_equal [], json["codes"]
    assert_equal Validation::Rules.version.to_s, json["rules_version"]
    assert_equal Contract.digest, response.headers["X-Banco-Contract"]
    assert_equal 3, ItemInstance.where(item_revision_id: revision_id).count
  end

  test "the author reads the findings submitted on a revision, in work status and work open (D-181)" do
    submit("fb-1", F.files_for(F.static_item))
    rev = ItemRevision.find(json["revision_id"])
    review = ItemReview.create!(item_revision: rev, agent_session: AgentSession.create!(label: "r", role: "reviewer", agent: "t", model: "m"), checklist_json: "[]")
    ReviewFinding.create!(item_revision: rev, source: "review", item_review: review, severity: "major", instance: 2, field: "prompt.stem_it",
                          quote: "Calcola x.", problem_it: "Ambiguo.", fix_it: "Chiarisci.")
    api("/api/v1/work/revisions/#{rev.id}")
    f = json["review_findings"].first
    assert_equal [ "review", "major", "Calcola x.", "Ambiguo.", "Chiarisci.", review.id ], f.values_at("source", "severity", "quote", "problem_it", "fix_it", "review_id")
    assert_equal 1, json["review_findings"].size
    api("/api/v1/work/items/fb-1?role=author")
    assert_equal "Chiarisci.", json["review_findings"].first["fix_it"]
    assert_not_includes json.keys, "disposition"
  end

  test "a failed revision is stored with its codes and its instances are still materialized (static)" do
    submit("bad-1", F.files_for(F.static_item("prompt" => { "stem_it" => "Scrivi la risposta che cercano." })))
    perform_enqueued_jobs
    api("/api/v1/work/revisions/#{json['revision_id']}")
    assert_equal "failed", json["status"]
    assert_includes json["codes"], "E-PHRASE"
    assert json["findings"].any? { |f| f["code"] == "E-PHRASE" && f["field"].present? }
  end

  test "two identical first submits that both prepared before either stored: the second replays, no unique-index 500 (D-073)" do
    files = F.files_for(F.static_item)
    prepare = -> { Validation::Submission.new(key: "eq-1", base: nil, files: files, session: session_of(:author)).prepare! }
    first = prepare.call
    second = prepare.call # prepared against the same (empty) state, before the first stores
    revision, replayed = first.store!
    assert_equal false, replayed
    again, replayed = second.store!
    assert_equal true, replayed
    assert_equal revision.id, again.id
    assert_equal 1, ItemRevision.count
  end

  test "a concurrent different submit that lost the race is E-STALE-BASE, not a 500" do
    first = Validation::Submission.new(key: "eq-1", base: nil, files: F.files_for(F.static_item), session: session_of(:author)).prepare!
    changed = JSON.parse(F.files_for(F.static_item).fetch("item.json")).merge("title_it" => "Altro")
    second = Validation::Submission.new(key: "eq-1", base: nil, files: F.files_for(F.static_item).merge("item.json" => JSON.generate(changed)), session: session_of(:author)).prepare!
    first.store!
    error = assert_raises(Validation::Submission::Refused) { second.store! }
    assert_equal "E-STALE-BASE", error.code
    assert_equal 409, error.http
    assert_equal 1, ItemRevision.count
  end

  test "the same files again are a replay: no new revision, no new job" do
    submit("eq-1", F.files_for(F.static_item))
    id = json["revision_id"]
    assert_no_enqueued_jobs do
      submit("eq-1", F.files_for(F.static_item), base: id)
    end
    assert_response :ok
    assert_equal true, json["replayed"]
    assert_equal id, json["revision_id"]
    assert_equal 1, ItemRevision.count
  end

  test "a replay of a revision that passed under older rules enqueues a new validation (D-154)" do
    submit("eq-1", F.files_for(F.static_item))
    id = json["revision_id"]
    ItemValidation.create!(item_revision_id: id, seq: 1, status: "passed", codes_json: "[]", rules_version: "0")
    assert_enqueued_with(job: ValidateItemRevisionJob, args: [ id ]) do
      submit("eq-1", F.files_for(F.static_item), base: id)
    end
    assert_equal true, json["replayed"]
  end

  test "a new revision needs the latest base: 409 E-STALE-BASE otherwise" do
    submit("eq-1", F.files_for(F.static_item))
    first = json["revision_id"]
    submit("eq-1", F.files_for(F.static_item("expected_seconds" => 90)))
    assert_response :conflict
    assert_equal "E-STALE-BASE", json["code"]
    submit("eq-1", F.files_for(F.static_item("expected_seconds" => 90)), base: first)
    assert_response :accepted
    assert_equal 2, json["seq"]
    submit("eq-1", F.files_for(F.static_item("expected_seconds" => 100)), base: first)
    assert_equal "E-STALE-BASE", json["code"]
    assert_equal 2, ItemRevision.count
  end

  test "refused with nothing stored: 422 E-FILES for unreadable or missing files, 413 for large ones" do
    counts = -> { [ Item.count, ItemRevision.count ] }
    before = counts.call
    submit("eq-1", { "item.json" => "{not json" })
    assert_response :unprocessable_entity
    assert_equal "E-FILES", json["code"]
    submit("eq-1", { "generator.mjs" => "export function generate() {}" })
    assert_equal "E-FILES", json["code"]
    submit("eq-1", { "item.json" => "[]" })
    assert_equal "E-FILES", json["code"]
    submit("eq-1", { "notes.txt" => "x" })
    assert_equal "E-FILES", json["code"]
    submit("Bad Key", F.files_for(F.static_item))
    assert_equal "E-FILES", json["code"]
    submit("eq-1", F.files_for(F.generated_item, "generator.mjs" => "x" * 70_000))
    assert_response :content_too_large
    assert_equal "E-TOO-LARGE", json["code"]
    submit("eq-1", F.files_for(F.generated_item).merge("assets/a.svg" => "x" * 700_000, "assets/b.svg" => "x" * 700_000, "assets/c.svg" => "x" * 700_000, "assets/d.svg" => "x" * 700_000))
    assert_equal "E-TOO-LARGE", json["code"]
    submit("eq-1", F.files_for(F.static_item("subject" => "nonsense")))
    assert_includes [ "E-NOT-FOUND", "E-FILES" ], json["code"]
    submit("eq-1", F.files_for(F.generated_item.merge("generator" => "generator.mjs")))
    assert_equal "E-FILES", json["code"] # names a generator, sends none
    assert_equal before, counts.call
  end

  test "an item of another subject than the one it exists in is refused" do
    submit("eq-1", F.files_for(F.static_item))
    id = json["revision_id"]
    Subject.create!(key: "italian", name_it: "Italiano", position: 2)
    item = F.static_item("subject" => "italian", "skill" => "italian.x")
    submit("eq-1", F.files_for(item), base: id)
    assert_equal "E-FILES", json["code"]
  end

  test "--dry-run validates in the request and writes nothing: a passing static item" do
    counts = -> { [ Item, ItemRevision, ItemValidation, ItemInstance ].map(&:count) }
    before = counts.call
    assert_no_enqueued_jobs { submit("eq-1", F.files_for(F.static_item), dry: true) }
    assert_response :ok
    assert_equal true, json["dry_run"]
    assert_equal "passed", json["status"]
    record_example "work submit", "dry-run-passed"
    assert_equal 3, json["instances"]
    assert_equal before, counts.call
  end

  test "status counts the older revisions still waiting for a verdict" do
    submit("eq-1", F.files_for(F.static_item))
    first = json["revision_id"]
    submit("eq-2", F.files_for(F.static_item))
    second = json["revision_id"]
    api("/api/v1/work/revisions/#{second}")
    assert_equal 1, json["queue_ahead"]
    ItemValidation.create!(item_revision_id: first, seq: 1, status: "passed", codes_json: "[]", rules_version: "6")
    api("/api/v1/work/revisions/#{second}")
    assert_equal 0, json["queue_ahead"]
  end

  test "an identical dry run is answered from memory, a changed file is run again" do
    Validation::DryRun.clear_cache
    files = F.files_for(F.static_item)
    submit("eq-1", files, dry: true)
    assert_response :ok
    runs = 0
    original = Validation::ItemRunner.instance_method(:call)
    Validation::ItemRunner.define_method(:call) { |*a| runs += 1; original.bind(self).call(*a) }
    begin
      submit("eq-1", files, dry: true)
      assert_response :ok
      assert_equal 0, runs
      submit("eq-1", F.files_for(F.static_item("prompt" => { "stem_it" => "Scrivi la risposta che cercano." })), dry: true)
      assert_equal 1, runs
    ensure
      Validation::ItemRunner.define_method(:call, original)
    end
  end

  test "--dry-run on a failing item answers 422 with the first code, every code and the findings" do
    before = ItemRevision.count
    submit("eq-1", F.files_for(F.static_item("prompt" => { "stem_it" => "Scrivi la risposta che cercano." })), dry: true)
    assert_response :unprocessable_entity
    assert_equal "E-PHRASE", json["code"]
    record_example "work submit", "dry-run-failed"
    assert_equal true, json["dry_run"]
    assert_includes json["codes"], "E-PHRASE"
    assert json["findings"].first["field"].present?
    assert_equal before, ItemRevision.count
  end

  test "work open: the author gets every file, the verifier never gets generator.mjs" do
    submit("eq-1", F.files_for(F.static_item, "generator.mjs" => "export function generate() { return {}; }"))
    perform_enqueued_jobs
    submit("eq-1", { "verify.mjs" => "export function verify() { return { ok: true }; }" }, base: ItemRevision.last.id)
    api("/api/v1/work/items/eq-1")
    record_example "work open", "author"
    assert_equal %w[generator.mjs item.json verify.mjs], json["files"].keys.sort
    assert_equal "author", json["role"]
    assert_equal "diagnosis-item", json["brief"]["name"]
    assert_equal 2, json["seq"]

    # The verifier opens the revision the author's instances belong to.
    first, second = ItemRevision.order(:seq).to_a
    first.instances.each { |i| ItemInstance.create!(i.attributes.except("id").merge("item_revision_id" => second.id)) }
    api("/api/v1/work/items/eq-1?role=verifier", headers: { "X-Banco-Session" => session_of(:verifier).id.to_s })
    assert_equal "verifier", json["role"]
    assert_not_includes json["files"].keys, "generator.mjs"
    assert_includes json["files"].keys, "item.json"
    assert_equal 3, json["instances"].size
    assert json["instances"].first.key?("answer")
    assert json["tests"].key?("must_accept")
    assert_not_includes response.body, "export function generate"

    api("/api/v1/work/items/eq-1?role=nobody")
    assert_equal "E-FILES", json["code"]
    api("/api/v1/work/items/none")
    assert_response :not_found
    assert_equal "E-NOT-FOUND", json["code"]
  end

  test "a submission without item.json carries it forward: a verifier adds verify.mjs alone" do
    submit("eq-1", F.files_for(F.static_item))
    first = json["revision_id"]
    submit("eq-1", { "verify.mjs" => "export function verify() { return { ok: true }; }" }, base: first)
    assert_response :accepted
    second = ItemRevision.find(json["revision_id"])
    assert_equal first, second.base_revision_id
    assert_equal ItemRevision.find(first).body_json, second.body_json
    assert_equal [ "verify.mjs" ], second.other_files.keys
    # An author resubmitting item.json keeps the verifier's verify.mjs.
    submit("eq-1", { "item.json" => JSON.generate(F.static_item("expected_seconds" => 70)) }, base: second.id)
    assert_equal [ "verify.mjs" ], ItemRevision.find(json["revision_id"]).other_files.keys
  end

  test "no token is 401; the web listener has no such route" do
    on(:api, "/api/v1/work/items/eq-1")
    assert_response :unauthorized
    on(:web, "/api/v1/work/submit", method: :post, params: {}, as: :json)
    assert_response :not_found
  end

  test "a validation error row is never a pass, and a settled error follows the last attempt" do
    submit("eq-1", F.files_for(F.static_item))
    revision = ItemRevision.find(json["revision_id"])
    Validation::RevisionValidation.new(revision, attempt: 1).record_error(Validation::ChromeRunner::Unavailable.new("no chrome"))
    api("/api/v1/work/revisions/#{revision.id}")
    assert_equal "error", json["status"]
    assert_equal false, json["settled"]
    assert_equal true, json["retrying"]
    Validation::RevisionValidation.new(revision, attempt: ValidateItemRevisionJob::ATTEMPTS).record_error(Validation::ChromeRunner::Unavailable.new("no chrome"))
    api("/api/v1/work/revisions/#{revision.id}")
    assert_equal true, json["settled"]
    assert_equal false, json["retrying"]
    assert_equal "error", json["status"]
  end

  # ---- with Chrome -------------------------------------------------------------------------

  test "a generated item: the job materializes 24 instances; verify is missing until a verifier adds it" do
    require_chrome!
    submit("gen-1", F.files_for(F.generated_item, "generator.mjs" => F::GENERATOR))
    first = json["revision_id"]
    perform_enqueued_jobs
    api("/api/v1/work/revisions/#{first}")
    assert_equal "awaiting_verifier", json["status"]
    assert_equal [ "E-VERIFY-MISSING" ], json["codes"]
    assert_equal 24, json["instances"]
    assert json["chrome_version"].present?

    api("/api/v1/work/items/gen-1?role=verifier", headers: { "X-Banco-Session" => session_of(:verifier).id.to_s })
    assert_equal 24, json["instances"].size
    assert_not_includes json["files"].keys, "generator.mjs"

    submit("gen-1", { "verify.mjs" => F::VERIFY }, base: first)
    perform_enqueued_jobs
    second = json["revision_id"]
    api("/api/v1/work/revisions/#{second}")
    assert_equal "passed", json["status"], json.inspect
    assert_equal 24, json["instances"]
    assert_equal 48, ItemInstance.count
  end

  test "a dry run of a generated item uses Chrome in the request; a busy Chrome is 409 E-CHROME-BUSY" do
    require_chrome!
    submit("gen-1", F.files_for(F.generated_item, "generator.mjs" => F::GENERATOR))
    base = json["revision_id"]
    submit_when_chrome_is_free("gen-1", { "verify.mjs" => F::VERIFY }, base: base)
    assert_response :ok, json.inspect
    assert_equal 24, json["instances"]
    assert_equal 1, ItemRevision.count
    Validation::DryRun.clear_cache  # a repeat would be answered from memory, Chrome never asked
    held = Queue.new
    release = Queue.new
    holder = Thread.new { Validation::ChromeRunner.with_lock { held << true; release.pop } }
    held.pop
    begin
      ENV["BANCO_DRY_RUN_CHROME_WAIT"] = "0.5"
      submit("gen-1", { "verify.mjs" => F::VERIFY }, base: base, dry: true)
      assert_response :conflict
      assert_equal "E-CHROME-BUSY", json["code"]
      assert_equal "retry in 30 s", json["next"]
    ensure
      ENV.delete("BANCO_DRY_RUN_CHROME_WAIT")
      release << true
      holder.join
    end
  end

  test "a dry run of a new generator item without verify.mjs is awaiting_verifier, not a failure" do
    require_chrome!
    Validation::DryRun.clear_cache
    submit_when_chrome_is_free("gen-2", F.files_for(F.generated_item, "generator.mjs" => F::GENERATOR))
    assert_response :ok, json.inspect
    assert_equal true, json["dry_run"]
    assert_equal "awaiting_verifier", json["status"]
    assert_equal [ "E-VERIFY-MISSING" ], json["codes"]
    assert_equal 24, json["instances"]
    assert_equal 0, ItemRevision.count
  end
end
