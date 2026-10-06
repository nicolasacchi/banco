require "test_helper"
require_relative "../support/validation_fixtures"
require_relative "../support/course_rows"
require_relative "../support/validation_servers"

# Independence of verify, expert review, blind solve and the providers (M6: A-04,
# A-05, A-08, operator Q8). Rules against mistakes, enforced by the server; nothing
# here decides anything: the teacher disposes of findings in the browser.
class IndependenceTest < ActionDispatch::IntegrationTest
  include ActiveJob::TestHelper
  include CourseRows
  F = ValidationFixtures
  VERIFY = "export function verify() { return { ok: true }; }".freeze
  GENERATOR = "export function generate() { return {}; }".freeze

  setup do
    @token = ApiToken.issue!(role: "agent_claude", label: "independence test")
    build_course
    @author = session!(:author, "claude-opus-5-5")
    @verifier = session!(:verifier, "claude-sonnet-5-5")
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

  def submit(item, files, as:, base: nil, dry: false)
    api("/api/v1/work/submit", method: :post, body: { item: item, base: base, files: files }, as: as, headers: dry ? { "X-Banco-Dry-Run" => "1" } : {})
  end

  # An item revision that passed validation, written by @author (static, 3 instances).
  def passed_revision(key = "eq-1")
    submit(key, F.files_for(F.static_item, "generator.mjs" => GENERATOR), as: @author)
    assert_response :accepted, json.inspect
    perform_enqueued_jobs
    revision = ItemRevision.find(json["revision_id"])
    assert_equal "passed", revision.status, revision.latest_validation&.codes_json
    revision
  end

  def checklist(evidence_prefix = "Controllato sull'istanza")
    (1..11).map { |i| { "id" => i, "result" => "pass", "evidence" => "#{evidence_prefix} numero #{i}: nessun difetto trovato qui." } }
  end

  def review_doc(revision, findings: [], checklist: nil)
    { "schema" => "banco.review/1", "schema_version" => 1, "revision" => revision.id.to_s, "checklist" => checklist || self.checklist, "findings" => findings }
  end

  def finding(severity: "blocker", quote: "Risolvi $x+2=9$.", **rest)
    { "severity" => severity, "field" => "instances/0/display/stem_it", "quote" => quote,
      "problem_it" => "La consegna ammette due risposte.", "fix_it" => "Aggiungi un dato che escluda la seconda." }.merge(rest.transform_keys(&:to_s))
  end

  def review(revision, doc, as: @reviewer, dry: false)
    api("/api/v1/revisions/#{revision.id}/review", method: :post, body: { review: doc }, as: as, headers: dry ? { "X-Banco-Dry-Run" => "1" } : {})
  end

  def dispose!(finding, disposition, reason = "ok")
    Decision.create!(kind: "dispose_finding", subject: @subject, payload_json: JSON.generate(finding_id: finding.id, disposition: disposition, reason_it: reason),
                     request_id: SecureRandom.hex(4), teacher_login: "teacher", remote_addr: "127.0.0.1")
  end

  # ---- sessions and the providers ---------------------------------------------------------

  test "banco session new: a role, the agent and the model; the family comes from providers.yml" do
    api("/api/v1/sessions", method: :post, body: { role: "reviewer", agent: "omp", model: "gpt-5.2" })
    assert_response :created
    record_example "session new", "created"
    assert_equal "openai", json["family"]
    assert_equal "reviewer", AgentSession.find(json["id"]).role

    api("/api/v1/sessions", method: :post, body: { role: "operator", agent: "x", model: "y" })
    assert_equal "E-FILES", json["code"]
    api("/api/v1/sessions", method: :post, body: { role: "author", agent: "", model: "y" })
    assert_equal "E-FILES", json["code"]
  end

  test "the grader runs on Claude only: other families are E-PROVIDER-NOT-ALLOWED, at creation and at use" do
    api("/api/v1/sessions", method: :post, body: { role: "grader", agent: "omp", model: "gpt-5.2" })
    assert_response :unprocessable_entity
    assert_equal "E-PROVIDER-NOT-ALLOWED", json["code"]
    api("/api/v1/sessions", method: :post, body: { role: "grader", agent: "claude-code", model: "claude-sonnet-5-5" })
    assert_response :created
    # A row made some other way is still refused where the student's text is read.
    stray = AgentSession.create!(label: "t", role: "grader", agent: "omp", model: "gemini-3")
    api("/api/v1/submissions/pending", as: stray)
    assert_equal "E-PROVIDER-NOT-ALLOWED", json["code"]
  end

  test "a reviewer on the author's model is E-PROVIDER-NOT-ALLOWED; a Sonnet on an Opus item is fine (Q8-bis)" do
    revision = passed_revision
    same_model = session!(:reviewer, "claude-opus-5-5")
    review(revision, review_doc(revision), as: same_model)
    assert_response :unprocessable_entity
    assert_equal "E-PROVIDER-NOT-ALLOWED", json["code"]
    assert_match(/different model/, json["message"])
    record_example "review submit", "provider-not-allowed"
    api("/api/v1/revisions/#{revision.id}/review", as: same_model)
    assert_equal "E-PROVIDER-NOT-ALLOWED", json["code"]
    # Case and a provider prefix do not make it another model.
    prefixed = session!(:reviewer, "Anthropic/Claude-Opus-5-5")
    review(revision, review_doc(revision), as: prefixed)
    assert_equal "E-PROVIDER-NOT-ALLOWED", json["code"]
    assert_equal 0, ItemReview.count

    sonnet = session!(:reviewer, "claude-sonnet-5-5-review")
    review(revision, review_doc(revision), as: sonnet)
    assert_response :created, json.inspect
    assert_equal 1, ItemReview.count
  end

  test "a session is bound to the token that created it; another token's session is refused (D-071)" do
    api("/api/v1/sessions", method: :post, body: { role: "reviewer", agent: "omp", model: "claude-sonnet-5-5" })
    assert_response :created
    mine = AgentSession.find(json["id"])
    assert_equal @token.split("_")[1], mine.token_id
    other = ApiToken.issue!(role: "agent_claude", label: "other")
    revision = passed_revision
    get_review = ->(token) { on(:api, "/api/v1/revisions/#{revision.id}/review", headers: { "Authorization" => "Bearer #{token}", "X-Banco-Session" => mine.id.to_s }) }
    get_review.call(@token)
    assert_response :ok, json.inspect
    get_review.call(other)
    assert_response :unprocessable_entity
    assert_equal "E-SESSION", json["code"]
    assert_match(/another token/, json["message"])
  end

  test "token roles map to session roles: agent_claude all, agent_omp no grader, ci none" do
    open = lambda do |token, role|
      on(:api, "/api/v1/sessions", method: :post, headers: { "Authorization" => "Bearer #{token}" },
         params: { role: role, agent: "x", model: "claude-sonnet-5-5" }, as: :json)
    end
    claude = ApiToken.issue!(role: "agent_claude", label: "c")
    omp = ApiToken.issue!(role: "agent_omp", label: "o")
    ci = ApiToken.issue!(role: "ci", label: "ci")
    %w[author verifier reviewer solver grader].each do |role|
      open.call(claude, role)
      assert_response :created, "agent_claude #{role}: #{json.inspect}"
    end
    %w[author verifier reviewer solver].each do |role|
      open.call(omp, role)
      assert_response :created, "agent_omp #{role}: #{json.inspect}"
    end
    open.call(omp, "grader")
    assert_response :unprocessable_entity
    assert_equal "E-SESSION-ROLE", json["code"]
    %w[author verifier reviewer solver grader].each do |role|
      open.call(ci, role)
      assert_response :unprocessable_entity, "ci #{role}"
      assert_equal "E-SESSION-ROLE", json["code"]
    end
    # Use is checked too: a grader session row made for an omp token is refused at use.
    omp_id = omp.split("_")[1]
    stray = AgentSession.create!(label: "t", role: "grader", agent: "x", model: "claude-sonnet-5-5", token_id: omp_id)
    on(:api, "/api/v1/submissions/pending", headers: { "Authorization" => "Bearer #{omp}", "X-Banco-Session" => stray.id.to_s })
    assert_equal "E-SESSION-ROLE", json["code"]
  end

  test "a command that needs a session says so: E-SESSION without one, E-SESSION-ROLE with the wrong role" do
    revision = passed_revision
    api("/api/v1/revisions/#{revision.id}/review", method: :post, body: { review: {} })
    assert_equal "E-SESSION", json["code"]
    api("/api/v1/revisions/#{revision.id}/review", as: @solver)
    assert_equal "E-SESSION-ROLE", json["code"]
    api("/api/v1/work/submit", method: :post, body: { item: "x", base: nil, files: { "item.json" => "{}" } })
    assert_equal "E-SESSION", json["code"]
    api("/api/v1/work/submit", method: :post, body: { item: "x", base: nil, files: { "item.json" => "{}" } }, as: @reviewer)
    assert_equal "E-SESSION-ROLE", json["code"]
  end

  test "review open reads without a session (D-158); a bad header is still refused, submit still needs a session" do
    revision = passed_revision
    api("/api/v1/revisions/#{revision.id}/review")
    assert_response :ok, json.inspect
    assert_equal revision.id, json["revision_id"]
    api("/api/v1/revisions/#{revision.id}/review", headers: { "X-Banco-Session" => "Errore: boh" })
    assert_equal "E-SESSION", json["code"]
    api("/api/v1/revisions/#{revision.id}/solve")
    assert_equal "E-SESSION", json["code"]
  end

  # ---- verify: who may write it, what the verifier sees ----------------------------------------

  test "verify.mjs from the author is 422 E-VERIFY-AUTHOR, in a submit and in a dry run; nothing is stored" do
    before = ItemRevision.count
    submit("eq-1", F.files_for(F.static_item, "generator.mjs" => GENERATOR, "verify.mjs" => VERIFY), as: @author)
    assert_response :unprocessable_entity
    assert_equal "E-VERIFY-AUTHOR", json["code"]
    assert_equal "verify.mjs", json["field"]
    record_example "work submit", "verify-from-author"
    submit("eq-1", F.files_for(F.static_item, "generator.mjs" => GENERATOR, "verify.mjs" => VERIFY), as: @author, dry: true)
    assert_equal "E-VERIFY-AUTHOR", json["code"]
    assert_equal before, ItemRevision.count
  end

  test "only a verifier session may change verify.mjs; an author's resubmission carries it forward unchanged" do
    first = passed_revision
    submit("eq-1", { "verify.mjs" => VERIFY }, as: @verifier, base: first.id)
    assert_response :accepted, json.inspect
    second = ItemRevision.find(json["revision_id"])
    assert_equal @verifier.id, second.file_sessions["verify.mjs"]
    assert_equal @author.id, second.file_sessions["item.json"]

    submit("eq-1", { "item.json" => JSON.generate(F.static_item("expected_seconds" => 70)) }, as: @author, base: second.id)
    assert_response :accepted
    third = ItemRevision.find(json["revision_id"])
    assert_equal VERIFY, third.other_files["verify.mjs"]
    assert_equal @verifier.id, third.file_sessions["verify.mjs"]
    assert_equal @author.id, third.file_sessions["item.json"]

    # Changing it is the verifier's again; the author sending a different one is refused.
    submit("eq-1", { "verify.mjs" => "export function verify() { return { ok: false }; }" }, as: @author, base: third.id)
    assert_equal "E-VERIFY-AUTHOR", json["code"]
    # The same text as the carried one is not a change.
    submit("eq-1", { "item.json" => third.body_json, "verify.mjs" => VERIFY }, as: @author, base: third.id)
    assert_response :ok
    assert_equal true, json["replayed"]
  end

  test "the verifier's view never has generator.mjs; a verifier cannot send anything but verify.mjs" do
    first = passed_revision
    secret = "export function generate() { return {}; }"
    assert_equal secret, first.other_files["generator.mjs"]
    api("/api/v1/work/items/eq-1?role=verifier", as: @verifier)
    assert_response :ok
    record_example "work open", "verifier"
    assert_equal "verifier", json["role"]
    assert_not_includes json["files"].keys, "generator.mjs"
    assert_not_includes response.body, "function generate"

    # The session decides the view, whatever the query says.
    api("/api/v1/work/items/eq-1", as: @verifier)
    assert_equal "verifier", json["role"]
    assert_not_includes response.body, "function generate"
    api("/api/v1/work/items/eq-1?role=author", as: @verifier)
    assert_equal "E-SESSION-ROLE", json["code"]
    api("/api/v1/work/items/eq-1?role=verifier")
    assert_equal "E-SESSION", json["code"]
    assert_not_includes response.body, "function generate"

    submit("eq-1", { "item.json" => JSON.generate(F.static_item("expected_seconds" => 70)) }, as: @verifier, base: first.id)
    assert_equal "E-SESSION-NOT-INDEPENDENT", json["code"]
  end

  test "E-SESSION-NOT-INDEPENDENT: a session that already holds another role on the item" do
    first = passed_revision
    # A verifier id that is also in the author's files (what a mix-up would look like).
    ItemRevision.create!(item: first.item, seq: 2, base_revision_id: first.id, body_json: first.body_json, files_json: first.files_json,
                         file_sessions_json: JSON.generate("item.json" => @verifier.id, "generator.mjs" => @author.id))
    submit("eq-1", { "verify.mjs" => VERIFY }, as: @verifier, base: ItemRevision.last.id)
    assert_equal "E-SESSION-NOT-INDEPENDENT", json["code"]
    api("/api/v1/work/items/eq-1?role=verifier", as: @verifier)
    assert_equal "E-SESSION-NOT-INDEPENDENT", json["code"]
  end

  # ---- the expert review ---------------------------------------------------------------------

  test "review open: item text, instances with answers, the 11 points; never generator.mjs" do
    revision = passed_revision
    api("/api/v1/revisions/#{revision.id}/review", as: @reviewer)
    assert_response :ok
    record_example "review open", "opened"
    assert_equal 11, json["checklist"].size
    assert_equal 3, json["instances"].size
    assert_equal "7", json["instances"].first["answer"]
    assert_equal 1, json["instances"].first["instance"]
    assert json["programme_lines"].is_a?(Array)
    assert_not_includes response.body, "function generate"
  end

  test "an invented quote is 422 E-QUOTE-NOT-FOUND; a real one is stored as a finding" do
    revision = passed_revision
    review(revision, review_doc(revision, findings: [ finding(quote: "Una frase che non c'è") ]))
    assert_response :unprocessable_entity
    assert_equal "E-QUOTE-NOT-FOUND", json["code"]
    assert_equal "/findings/0/quote", json["field"]
    record_example "review submit", "quote-not-found"
    assert_equal 0, ItemReview.count + ReviewFinding.count

    # A quote that exists, but in another instance than the finding names.
    review(revision, review_doc(revision, findings: [ finding(quote: "Risolvi $x+4=13$.", instance: 1) ]))
    assert_equal "E-QUOTE-NOT-FOUND", json["code"]
    review(revision, review_doc(revision, findings: [ finding(instance: 9) ]))
    assert_equal "E-QUOTE-NOT-FOUND", json["code"]

    review(revision, review_doc(revision, findings: [ finding(instance: 1) ]), dry: true)
    assert_response :ok
    assert_equal 0, ItemReview.count

    review(revision, review_doc(revision, findings: [ finding(instance: 1), finding(severity: "minor", quote: "Risolvi l'equazione e scrivi il valore di $x$.") ]))
    assert_response :created, json.inspect
    record_example "review submit", "created"
    assert_equal({ "blocker" => 1, "minor" => 1 }, json["counts"])
    assert_equal false, json["approvable"]
    assert_equal 2, ReviewFinding.where(source: "review").count
    assert_equal @reviewer.id, ItemReview.last.agent_session_id
  end

  test "a bare 'all verified' is E-REVIEW-EMPTY" do
    revision = passed_revision
    stock = (1..11).map { |i| { "id" => i, "result" => "pass", "evidence" => "Tutto verificato" } }
    review(revision, review_doc(revision, checklist: stock))
    assert_response :unprocessable_entity
    assert_equal "E-REVIEW-EMPTY", json["code"]
    assert_includes json["message"].to_s + json.to_s, "stock phrase"
    short = checklist.each_with_index.map { |c, i| i == 3 ? c.merge("evidence" => "tutto ok davvero") : c }
    review(revision, review_doc(revision, checklist: short))
    assert_equal "E-REVIEW-EMPTY", json["code"]
    assert_includes json.to_s, "3 words, at least 4 needed"
    same = checklist.map { |c| c.merge("evidence" => "Ho controllato la chiave su tutte le istanze.") }
    review(revision, review_doc(revision, checklist: same))
    assert_equal "E-REVIEW-EMPTY", json["code"]
    failed = checklist.each_with_index.map { |c, i| i.zero? ? c.merge("result" => "fail") : c }
    review(revision, review_doc(revision, checklist: failed))
    assert_equal "E-REVIEW-EMPTY", json["code"]
    assert_equal 0, ItemReview.count
    review(revision, review_doc(revision, checklist: checklist.first(10)))
    assert_equal "E-SCHEMA", json["code"]
  end

  test "a review needs the latest revision, and one that passed" do
    revision = passed_revision
    other = ItemRevision.create!(item: revision.item, seq: 2, base_revision_id: revision.id, body_json: revision.body_json, file_sessions_json: "{}")
    review(revision, review_doc(revision))
    assert_response :conflict
    assert_equal "E-STALE-BASE", json["code"]
    review(other, review_doc(other))
    assert_equal "E-ITEM-NOT-PASSED", json["code"]
    review(revision, review_doc(other).merge("revision" => "999"), as: @reviewer)
    assert_equal "E-STALE-BASE", json["code"]
  end

  test "a second round uses a session that did not see the first" do
    revision = passed_revision
    review(revision, review_doc(revision))
    assert_response :created
    # The author fixes; the same reviewer may not review again, nor even open it.
    submit("eq-1", { "item.json" => JSON.generate(F.static_item("expected_seconds" => 70)) }, as: @author, base: revision.id)
    perform_enqueued_jobs
    second = ItemRevision.find(json["revision_id"])
    review(second, review_doc(second))
    assert_equal "E-SESSION-NOT-INDEPENDENT", json["code"]
    api("/api/v1/revisions/#{second.id}/review", as: @reviewer)
    assert_equal "E-SESSION-NOT-INDEPENDENT", json["code"]

    fresh = session!(:reviewer, "gemini-3-pro")
    review(second, review_doc(second), as: fresh)
    assert_response :created, json.inspect
    # The author, the verifier and the solver cannot review their own item either.
    assert_equal 2, ItemReview.count
  end

  test "a session of one role on an item cannot take another on it" do
    revision = passed_revision
    BlindSolve.create!(item_revision: revision, agent_session: @reviewer, answers_json: "[]", results_json: "[]")
    review(revision, review_doc(revision))
    assert_response :unprocessable_entity
    assert_equal "E-SESSION-NOT-INDEPENDENT", json["code"]
    assert_match(/already acted as solver/, json["message"])
  end

  # ---- the gate: approvable? ------------------------------------------------------------------

  test "approvable? needs a review, a blind solve and every blocker or major finding disposed by the teacher" do
    revision = passed_revision
    assert_equal false, Review::Gate.approvable?(revision)
    assert_includes Review::Gate.check(revision).reasons, "no expert review on this revision"

    review(revision, review_doc(revision, findings: [ finding(instance: 1), finding(severity: "minor", quote: "Risolvi l'equazione e scrivi il valore di $x$.") ]))
    assert_response :created
    api("/api/v1/revisions/#{revision.id}/solve", method: :post, as: @solver,
        body: { solve: { schema: "banco.solve/1", schema_version: 1, revision: revision.id.to_s, answers: [ { instance: 1, answer: "7" }, { instance: 2, answer: "9" }, { instance: 3, answer: "16" } ] } })
    assert_response :created, json.inspect

    gate = Review::Gate.check(revision.reload)
    assert_equal false, gate.approvable, "an undisposed blocker keeps the gate shut"
    blocker = ReviewFinding.find_by!(severity: "blocker")
    assert_equal [ blocker.id ], gate.open_findings
    assert Review::Gate.worked?(revision)

    dispose!(blocker, "fix_requested", "da correggere")
    assert_equal false, Review::Gate.approvable?(revision), "a fix request keeps it shut: a new revision is needed"
    dispose!(blocker, "dismissed", "la consegna è chiara")
    assert_equal true, Review::Gate.approvable?(revision), "the minor finding needs no disposition"
    assert_equal "dismissed", blocker.reload.disposition

    # A failed validation or a new revision is not covered by an old review.
    ItemValidation.create!(item_revision: revision, seq: 99, status: "failed", codes_json: "[]")
    assert_equal false, Review::Gate.approvable?(revision.reload)
  end

  test "findings are append-only and no route disposes of them" do
    revision = passed_revision
    review(revision, review_doc(revision, findings: [ finding(instance: 1) ]))
    f = ReviewFinding.last
    assert_raises(ActiveRecord::StatementInvalid) { f.update!(severity: "minor") }
    assert_raises(ActiveRecord::StatementInvalid) { f.destroy }
    assert_raises(ActiveRecord::StatementInvalid) { ItemReview.last.update!(brief_sha256: "x") }
    api("/api/v1/revisions/#{revision.id}/findings/#{f.id}", method: :post, body: { disposition: "dismissed" })
    assert_response :not_found
  end

  test "SubjectStage: awaiting_teacher only when every pinned revision has a review and a blind solve" do
    revision = passed_revision
    blueprint = BlueprintRevision.create!(subject: @subject, skill_graph_revision: @graph, seq: 1, body_json: JSON.generate("entries" => [ { "items" => [ revision.id.to_s ] } ], "descent" => []))
    assert_equal false, SubjectStage.send(:review_done?, @subject, blueprint)
    review(revision, review_doc(revision))
    assert_equal false, SubjectStage.send(:review_done?, @subject, blueprint)
    api("/api/v1/revisions/#{revision.id}/solve", method: :post, as: @solver,
        body: { solve: { schema: "banco.solve/1", schema_version: 1, revision: revision.id.to_s, answers: [ { instance: 1, answer: "7" }, { instance: 2, dont_know: true }, { instance: 3, answer: "16" } ] } })
    assert_response :created, json.inspect
    assert_equal true, SubjectStage.send(:review_done?, @subject, blueprint)
  end

  # ---- the blind solve ------------------------------------------------------------------------

  test "solve open shows the instances as the student sees them: no key, no errors, no solution" do
    revision = passed_revision
    api("/api/v1/revisions/#{revision.id}/solve", as: @solver)
    assert_response :ok
    record_example "solve open", "opened"
    assert_equal "number", json["component"]
    assert_equal 3, json["instances"].size
    assert_equal({ "stem_it" => "Risolvi $x+2=9$." }, json["instances"].first["display"])
    body = response.body
    assert_not_includes body, "sign_error"
    assert_not_includes body, '"answer"'
    assert_not_includes body, "Togli 2"
    assert_not_includes body, "must_accept"
  end

  test "solve submit: the server grades; each disagreement is a blocker E-BLIND-SOLVE-MISMATCH" do
    revision = passed_revision
    answers = [ { instance: 1, answer: "7" }, { instance: 2, answer: "17" }, { instance: 3, answer: "21" } ]
    api("/api/v1/revisions/#{revision.id}/solve", method: :post, as: @solver,
        body: { solve: { schema: "banco.solve/1", schema_version: 1, revision: revision.id.to_s, answers: answers } })
    assert_response :created, json.inspect
    record_example "solve submit", "mismatches"
    assert_equal 2, json["mismatches"]
    findings = ReviewFinding.where(source: "blind_solve").order(:instance)
    assert_equal [ 2, 3 ], findings.map(&:instance)
    assert_equal [ "blocker" ], findings.map(&:severity).uniq
    assert_equal [ "E-BLIND-SOLVE-MISMATCH" ], findings.map(&:code).uniq
    assert_includes findings.first.quote, "Risolvi $x+4=13$."
    assert_equal false, Review::Gate.approvable?(revision)
    assert_equal @solver.id, BlindSolve.last.agent_session_id
  end

  test "solve submit: dont_know is a major finding; an unreadable answer, a missing instance and a second round are refused" do
    revision = passed_revision
    path = "/api/v1/revisions/#{revision.id}/solve"
    doc = ->(answers) { { solve: { schema: "banco.solve/1", schema_version: 1, revision: revision.id.to_s, answers: answers } } }
    api(path, method: :post, as: @solver, body: doc.([ { instance: 1, answer: "7" }, { instance: 2, answer: "0.5" }, { instance: 3, answer: "16" } ]))
    assert_equal "E-FILES", json["code"]
    assert_equal "answers/2", json["field"]
    api(path, method: :post, as: @solver, body: doc.([ { instance: 1, answer: "7" } ]))
    assert_equal "E-FILES", json["code"]
    api(path, method: :post, as: @solver, body: doc.([ { instance: 1 }, { instance: 2, answer: "9" }, { instance: 3, answer: "16" } ]))
    assert_equal "E-SCHEMA", json["code"]
    assert_equal 0, BlindSolve.count

    api(path, method: :post, as: @solver, body: doc.([ { instance: 1, dont_know: true }, { instance: 2, answer: "9" }, { instance: 3, answer: "16" } ]))
    assert_response :created, json.inspect
    assert_equal [ "major" ], ReviewFinding.where(source: "blind_solve").map(&:severity)
    api(path, method: :post, as: @solver, body: doc.([ { instance: 1, answer: "7" }, { instance: 2, answer: "9" }, { instance: 3, answer: "16" } ]))
    assert_equal "E-SESSION-NOT-INDEPENDENT", json["code"]

    same_model = session!(:solver, "claude-opus-5-5")
    api(path, method: :post, as: same_model, body: doc.([ { instance: 1, answer: "7" }, { instance: 2, answer: "9" }, { instance: 3, answer: "16" } ]))
    assert_equal "E-PROVIDER-NOT-ALLOWED", json["code"]
    api("/api/v1/revisions/#{revision.id}/solve", as: @reviewer)
    assert_equal "E-SESSION-ROLE", json["code"]
  end

  test "choice, ordering, matching and fraction answers are graded by the student's graders" do
    body = JSON.parse(File.read(Rails.root.join("test/fixtures/content/item/good/choice-static.json")))
    instance = body["instances"].first
    subject = Subject.find_or_create_by!(key: body["subject"]) { |s| s.name_it = "x"; s.position = 5 }
    item = Item.create!(subject: subject, key: "choice-1", kind: body["kind"])
    rev = ItemRevision.create!(item: item, seq: 1, body_json: body.to_json, file_sessions_json: JSON.generate("item.json" => @author.id), author_session: @author)
    ItemValidation.create!(item_revision: rev, seq: 1, status: "passed", codes_json: "[]")
    ItemInstance.create!(item_revision: rev, seed: 1, display_json: instance["display"].to_json, answer_json: instance["answer"].to_json,
                         errors_json: Array(instance["errors"]).to_json, fingerprint: SecureRandom.hex(32))
    path = "/api/v1/revisions/#{rev.id}/solve"
    api(path, as: @solver)
    assert_equal "choice", json["component"]
    wrong = instance["display"]["options"].map { |o| o["id"] }.find { |id| id != instance["answer"] }
    api(path, method: :post, as: @solver, body: { solve: { schema: "banco.solve/1", schema_version: 1, revision: rev.id.to_s, answers: [ { instance: 1, answer: wrong } ] } })
    assert_response :created, json.inspect
    assert_equal 1, json["mismatches"]
  end
end
