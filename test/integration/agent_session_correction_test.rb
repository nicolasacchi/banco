require "test_helper"
require "rake"
require_relative "../support/decision_world"
require_relative "../support/topic_world"
require_relative "../support/arbiter_rows"
require_relative "../support/page_world"

# D-316: the true model of a session. A correction is a new row (the ledger stays append-only); independence is
# derived at read time with the true model, so a review or a blind solve by a session whose true model equals an
# author's true model counts for no gate and the teacher's pages say «non indipendente». The operator writes
# corrections from the host console only.
class AgentSessionCorrectionTest < ActionDispatch::IntegrationTest
  include DecisionWorld
  include TopicWorld
  include ArbiterRows
  include PageWorld

  OPUS = "claude-opus-5-5".freeze
  SONNET = "claude-sonnet-5-5".freeze

  setup do
    build_decision_world
    @author = AgentSession.create!(label: "a", role: "author", agent: "omp", model: OPUS)
    # The workflow told its agents to declare Sonnet; they ran on Opus.
    @solver = AgentSession.create!(label: "s", role: "solver", agent: "omp", model: SONNET)
    @checker = AgentSession.create!(label: "r", role: "reviewer", agent: "omp", model: SONNET)
    @bystander = AgentSession.create!(label: "b", role: "reviewer", agent: "omp", model: SONNET)
    build_topic_world
    @item = Item.create!(subject: @subject, key: "prov-item-1", kind: "practice_item")
    body = { schema: "banco.item/1", schema_version: 1, kind: "practice_item", subject: "math", skill: "math.number", component: "number", level: 1, expected_seconds: 60 }
    @revision = ItemRevision.create!(item: @item, seq: 1, body_json: JSON.generate(body), file_sessions_json: "{}", author_session: @author)
    ItemValidation.create!(item_revision: @revision, seq: 1, status: "passed", codes_json: "[]")
    2.times do |i|
      ItemInstance.create!(item_revision: @revision, seed: i + 1, display_json: JSON.generate(stem_it: "prov #{i}"), answer_json: JSON.generate((i + 2).to_s), errors_json: "[]",
                           hints_json: JSON.generate([ "Uno", "Due", "Tre" ]), solution_json: JSON.generate(steps: [ { text_it: "Passo.", math: "$x$" } ], final: "$x$"),
                           fingerprint: Digest::SHA256.hexdigest("prov-#{i}"))
    end
    @review = ItemReview.create!(item_revision: @revision, agent_session: @checker, checklist_json: "[]")
    @solve = BlindSolve.create!(item_revision: @revision, agent_session: @solver, answers_json: "[]", results_json: "[]")
    @bystander_review = ItemReview.create!(item_revision: @revision, agent_session: @bystander, checklist_json: "[]")
  end

  def correct!(session, model = OPUS, reason: "the workflow ran on Opus")
    AgentSessionCorrection.create!(agent_session: session, model: model, reason: reason, request_id: SecureRandom.uuid)
  end

  def console(ids, model: OPUS, reason: "the workflow ran on Opus", confirm: false)
    AgentSessionCorrector.call(session_ids: ids, model: model, reason: reason, confirm: confirm, os_user: "operator")
  end

  # --- the table -------------------------------------------------------------------------------------------------

  test "the correction table refuses UPDATE and DELETE" do
    row = correct!(@checker)
    assert_raises(ActiveRecord::StatementInvalid) { row.update_columns(model: "x") }
    assert_raises(ActiveRecord::StatementInvalid) { row.delete }
    assert_raises(ActiveRecord::StatementInvalid) { AgentSessionCorrection.where(id: row.id).update_all(reason: "y") }
    assert_raises(ActiveRecord::StatementInvalid) { AgentSessionCorrection.where(id: row.id).delete_all }
    assert_raises(ActiveRecord::StatementInvalid) { ActiveRecord::Base.connection.execute("DELETE FROM agent_session_corrections") }
    assert AgentSessionCorrection.exists?(row.id)
  end

  test "a row needs a session, a model, a reason and a request id" do
    assert_raises(ActiveRecord::StatementInvalid) { AgentSessionCorrection.new(agent_session_id: 99_999, model: OPUS, reason: "why", request_id: "x").save(validate: false) }
    assert_raises(ActiveRecord::StatementInvalid) { AgentSessionCorrection.new(agent_session: @checker, model: " ", reason: "why", request_id: "x").save(validate: false) }
    assert_raises(ActiveRecord::StatementInvalid) { AgentSessionCorrection.new(agent_session: @checker, model: OPUS, reason: "", request_id: "x").save(validate: false) }
  end

  # --- the true model --------------------------------------------------------------------------------------------

  test "the true model is the latest correction, else the declared one; the declared one stays readable" do
    assert_equal [ SONNET, SONNET, false ], [ @checker.model, @checker.declared_model, @checker.corrected? ]
    correct!(@checker, OPUS, reason: "one")
    correct!(@checker, "claude-haiku-5-5", reason: "two")
    session = AgentSession.find(@checker.id)
    assert_equal [ "claude-haiku-5-5", SONNET, "anthropic" ], [ session.model, session.declared_model, session.family ]
    assert_equal({ id: session.id, role: "reviewer", agent: "omp", model: "claude-haiku-5-5", family: "anthropic", declared_model: SONNET }, session.to_h)
  end

  test "a correction touches no other session" do
    correct!(@checker)
    assert_equal SONNET, AgentSession.find(@bystander.id).model
    assert_equal SONNET, AgentSession.find(@solver.id).model
    assert_equal OPUS, AgentSession.find(@author.id).model
  end

  test "the arbiter and the findings read the true model" do
    reviewer = @checker
    review = ItemReview.create!(item_revision: @revision, agent_session: reviewer, checklist_json: "[]")
    finding = ReviewFinding.create!(item_revision: @revision, source: "review", item_review: review, severity: "minor", field: "stem", quote: "q", problem_it: "p", fix_it: "f")
    assert_nil Providers.refusal(arbiter_session(OPUS), finding: finding)
    correct!(reviewer)
    assert_match(/different model than the session that raised the finding/, Providers.refusal(arbiter_session(OPUS), finding: finding))
  end

  # --- independence, read when read -----------------------------------------------------------------------------

  test "the item gate counts a review and a solve only when the true model differs from every author's" do
    assert Review::Gate.check(@revision).approvable
    assert Review::Gate.worked?(@revision)
    correct!(@checker)
    assert Review::Gate.check(@revision).approvable, "another Sonnet reviewer filed a review that still counts"
    assert_equal [ @bystander_review.id ], @revision.counting_reviews.map(&:id)
    correct!(@solver)
    gate = Review::Gate.check(@revision)
    assert_not gate.approvable
    assert_includes gate.reasons.join, "no independent blind solve"
    assert_not_includes gate.reasons.join, "expert review"
    correct!(@bystander)
    gate = Review::Gate.check(@revision)
    assert_not gate.approvable
    assert_includes gate.reasons.join, "no independent expert review on this revision"
    assert_includes gate.reasons.join, "no independent blind solve on this revision"
    assert_not Review::Gate.worked?(@revision)
    assert_equal "claude-opus-5-5", ItemSessions.for(@item).sessions("author").sole.model
  end

  test "a correction of the author moves the reviews of the others" do
    assert Review::Gate.check(@revision).approvable
    correct!(@author, SONNET, reason: "the author ran on Sonnet")
    assert_equal [], @revision.counting_reviews, "all three reviewers declared Sonnet, and the author is Sonnet now"
    assert_not Review::Gate.check(@revision).approvable
  end

  test "a row of a session that declared no model is never held against anyone" do
    nobody = AgentSession.create!(label: "n", role: "reviewer")
    anonymous_author = AgentSession.create!(label: "n2", role: "author")
    item = Item.create!(subject: @subject, key: "prov-anon", kind: "practice_item")
    revision = ItemRevision.create!(item: item, seq: 1, body_json: "{}", file_sessions_json: "{}", author_session: anonymous_author)
    review = ItemReview.create!(item_revision: revision, agent_session: nobody, checklist_json: "[]")
    assert review.independent?
  end

  test "a lesson review by a session on an author's true model does not count for the topic gate" do
    author_revision = LessonRevision.create!(lesson: @lesson_revision.lesson, seq: @lesson_revision.lesson.revisions.maximum(:seq) + 1, source_md: "x", source_sha256: "0" * 64,
                                             body_json: @lesson_revision.body_json, rules_version: Validation::Rules.version.to_s, warnings_json: "[]", author_session: @author)
    LessonReview.create!(lesson_revision: author_revision, agent_session: @checker, checklist_json: "[]", recomputed_json: "[]", findings_json: "[]")
    topic = make_topic(author_revision, { "math.number" => [ @revision ] })
    reasons = -> { Approval::TopicGate.mechanical(topic).reasons.join("\n") }
    assert_not_includes reasons.call, "no review by an independent session"
    correct!(@checker)
    assert_includes reasons.call, "the lesson revision has no review by an independent session"
    assert_equal 1, author_revision.reviews.count, "the review is still in the ledger"
    assert_empty author_revision.counting_reviews
    stale, lesson_pin = Course::TopicStage.stale_pins(topic)
    assert_includes Course::TopicStage.reasons(topic, { "skills" => [ "math.number" ] }, stale, lesson_pin).join, "no review by an independent session"
  end

  test "the entry test's gate follows the item gate" do
    blueprint = BlueprintRevision.create!(subject: @subject, skill_graph_revision: @graph, author_session: @author, seq: @blueprint.seq + 1,
                                          body_json: JSON.generate(entries: [ { skill: "math.number", items: [ @revision.id ] } ]))
    AppEvent.create!(kind: "teacher_viewed_item", payload_json: { item_revision_id: @revision.id }.to_json)
    assert_not_includes Approval::BlueprintGate.check(blueprint, waive_preview: true).reasons.join, "is not approvable"
    correct!(@solver)
    assert_includes Approval::BlueprintGate.check(blueprint, waive_preview: true).reasons.join, "item revision #{@revision.id} is not approvable: no independent blind solve"
  end

  test "the page gate counts a review only when its session is independent of the page's authors" do
    page_revision = store_page!
    pass_page!(page_revision)
    reviewer = page_reviewer!
    PageReview.create!(page_revision: page_revision, agent_session: reviewer, checklist_json: "[]", findings_json: "[]")
    assert_nil Pages::Validations.gate_reason(page_revision, key: page_revision.page.key)
    correct!(reviewer, "claude-sonnet-5-5")
    assert_match(/has no review by an independent session/, Pages::Validations.gate_reason(PageRevision.find(page_revision.id), key: page_revision.page.key))
  end

  # --- the teacher's pages --------------------------------------------------------------------------------------

  test "the topic page shows the declared and the corrected model and marks a review that does not count «non indipendente»" do
    author_revision = LessonRevision.create!(lesson: @lesson_revision.lesson, seq: @lesson_revision.lesson.revisions.maximum(:seq) + 1, source_md: "x", source_sha256: "0" * 64,
                                             body_json: @lesson_revision.body_json, rules_version: Validation::Rules.version.to_s, warnings_json: "[]", author_session: @author)
    LessonReview.create!(lesson_revision: author_revision, agent_session: @checker, checklist_json: JSON.generate([ { id: 1, result: "pass", evidence: "ok" } ]), recomputed_json: "[]",
                         findings_json: JSON.generate([ { severity: "major", where: "example", problem_it: "Un rilievo che resta." } ]))
    make_topic(author_revision, { "math.number" => [ @revision ] })
    open_topic_page!(headers: TEACHER)
    assert_response :success
    assert_select "[data-lesson-review] [data-not-independent]", 0
    assert_select "[data-lesson-review] [data-review-model]", /Letta da claude-sonnet-5-5/
    correct!(@checker, OPUS, reason: "il flusso girava su Opus")
    open_topic_page!(headers: TEACHER)
    assert_select "[data-lesson-review] [data-review-model] [data-not-independent]", "non indipendente"
    assert_select "[data-lesson-review] [data-review-model]", /Letta da claude-opus-5-5 \(dichiarato: claude-sonnet-5-5, corretto dall'operatore: il flusso girava su Opus\)/
    assert_select "[data-lesson-review]", 1, "the review is still listed"
    assert_select "#step-approve", /La lezione non ha ancora la revisione di un altro agente/
  end

  test "the item card says who filed the review and the solve, and marks the ones that do not count" do
    topic = make_topic(@lesson_revision, { "math.number" => [ @revision ] })
    open_topic_page!(headers: TEACHER)
    assert_select "[data-review-by]", /Revisione: sessione #{@bystander.id}, modello claude-sonnet-5-5/
    assert_select "[data-not-independent]", 0
    correct!(@bystander)
    correct!(@solver)
    open_topic_page!(headers: TEACHER)
    assert_select "[data-review-by] [data-not-independent]", "non indipendente"
    assert_select "[data-blind-by] [data-not-independent]", "non indipendente"
    assert_select "[data-review-by]", /dichiarato: claude-sonnet-5-5, corretto dall'operatore/
    assert_equal topic.lesson, @lesson_revision.lesson
  end

  test "the findings of a session that no longer counts stay listed" do
    finding = ReviewFinding.create!(item_revision: @revision, item_review: @review, source: "review", severity: "major", field: "stem", quote: "q", problem_it: "Resta.", fix_it: "f")
    correct!(@checker)
    assert_equal [ finding.id ], @revision.findings.pluck(:id)
    assert_equal [ finding.id ], Review::Gate.check(@revision).open_findings
  end

  # --- the console task ------------------------------------------------------------------------------------------

  test "a dry run writes nothing and says what would change" do
    ReviewFinding.create!(item_revision: @revision, item_review: @review, source: "review", severity: "minor", field: "stem", quote: "q", problem_it: "p", fix_it: "f").tap do |minor|
      assess!(minor, "author_right")
      @minor = minor
    end
    assert_no_difference "AgentSessionCorrection.count" do
      result = console([ @checker.id ])
      assert result.ok
      assert_not result.recorded
      text = result.lines.join("\n")
      assert_includes text, "session #{@checker.id} (reviewer, omp): declared \"#{SONNET}\", true now \"#{SONNET}\", new \"#{OPUS}\""
      assert_includes result.changes[:stop_counting], "ItemReview #{@review.id}"
      assert_not_includes result.changes[:stop_counting], "ItemReview #{@bystander_review.id}"
      assert_includes result.changes[:minors_reopened], "finding #{@minor.id}"
    end
    assert_equal SONNET, AgentSession.find(@checker.id).model
  end

  test "the dry run names the gates that close" do
    result = console([ @checker.id, @bystander.id, @solver.id ])
    assert_includes result.changes[:gates_closed], "item prov-item-1 r1"
    assert_includes result.lines.join("\n"), "gates that close (approvable before, not after): 1"
  end

  test "CONFIRM records one row per session with the console provenance, and the model moves" do
    assert_difference "AgentSessionCorrection.count", 2 do
      result = console([ @checker.id, @solver.id ], confirm: true)
      assert result.recorded
    end
    rows = AgentSessionCorrection.order(:id).last(2)
    assert_equal [ @checker.id, @solver.id ].sort, rows.map(&:agent_session_id).sort
    assert_equal [ OPUS, OPUS ], rows.map(&:model)
    assert_equal [ "the workflow ran on Opus" ], rows.map(&:reason).uniq
    assert_equal [ "console" ], rows.map(&:remote_addr).uniq
    assert_equal [ "console" ], rows.map(&:groups).uniq
    assert_equal [ "operator" ], rows.map(&:os_user).uniq
    assert_equal "rake banco:correct_session", rows.first.request_path
    assert_equal 2, rows.map(&:request_id).uniq.size
    assert_equal [ OPUS, SONNET ], [ AgentSession.find(@checker.id).model, AgentSession.find(@bystander.id).model ]
    assert_not Review::Gate.check(@revision).approvable
  end

  test "a correction to the model the session already has is refused, and so is a bad request" do
    refused = console([ @checker.id ], model: SONNET)
    assert_not refused.ok
    assert_match(/already runs on/, refused.errors.join)
    assert_not console([ @author.id ], model: "Anthropic/CLAUDE-OPUS-5-5", confirm: true).ok, "case and a provider prefix do not make another model"
    correct!(@checker)
    assert_not console([ @checker.id ], confirm: true).ok, "the true model is the one compared"
    assert_not console([ 9_999_999 ]).ok
    assert_not console([ @checker.id, @checker.id ], model: "x").ok
    assert_not console([]).ok
    assert_not console([ @checker.id ], model: " ").ok
    assert_not console([ @checker.id ], model: "claude-haiku-5-5", reason: " ").ok
    assert_not console([ @checker.id, @solver.id ], model: OPUS, confirm: true).ok, "one refused session stops the whole request"
    assert_equal 1, AgentSessionCorrection.count
  end

  test "the rake task is a dry run unless CONFIRM=1" do
    Rails.application.load_tasks unless Rake::Task.task_defined?("banco:correct_session")
    task = Rake::Task["banco:correct_session"]
    env = { "SESSION" => "#{@checker.id},#{@solver.id}", "MODEL" => OPUS, "REASON" => "the workflow ran on Opus" }
    env.each { |k, v| ENV[k] = v }
    out, = capture_io { task.reenable; task.invoke }
    assert_match(/dry run, nothing written/, out)
    assert_equal 0, AgentSessionCorrection.count
    ENV["CONFIRM"] = "1"
    out, = capture_io { task.reenable; task.invoke }
    assert_match(/recorded 2 correction\(s\) via console/, out)
    assert_equal 2, AgentSessionCorrection.count
  ensure
    (env.keys + [ "CONFIRM" ]).each { |k| ENV.delete(k) }
  end

  # --- no door --------------------------------------------------------------------------------------------------

  test "no route reaches a correction" do
    names = Rails.application.routes.routes.map { |r| [ r.path.spec.to_s, r.defaults[:controller].to_s, r.defaults[:action].to_s ].join(" ") }
    assert_empty names.grep(/correct(?!ions\b.*teacher)/i).reject { |n| n.include?("teacher/corrections") }, "no route may write a session correction"
    assert_empty names.grep(/agent_session|session_correction/i)
    sessions = names.select { |n| n.include?("api/v1/sessions") }
    assert_equal [ "/api/v1/sessions api/v1/sessions create" ], sessions.map { |n| n.sub("(.:format)", "") }, "the only session route creates a session"
  end

  test "the API and the CLI contract have no correction command, and a request to one finds nothing" do
    contract = Rails.root.join("contract/commands.json").read
    assert_no_match(/correct_session|session_correction|agent_session_correction/, contract)
    token = ApiToken.issue!(role: "agent_claude", label: "prov")
    headers = { "Authorization" => "Bearer #{token}", "X-Banco-Session" => @checker.id.to_s }
    [ "/api/v1/sessions/#{@checker.id}/corrections", "/api/v1/sessions/#{@checker.id}/correct", "/api/v1/session_corrections" ].each do |path|
      %i[post put patch].each do |verb|
        on(:api, path, method: verb, headers: headers, params: { model: OPUS, reason: "I am Opus" })
        assert_response :not_found, "#{verb} #{path}"
      end
    end
    %i[post put patch].each do |verb|
      on(:web, "/teacher/sessions/#{@checker.id}/correct", method: verb, headers: TEACHER, remote_addr: EDGE)
      assert_response :not_found
    end
    assert_equal 0, AgentSessionCorrection.count
    assert_equal SONNET, AgentSession.find(@checker.id).model
  end
end
