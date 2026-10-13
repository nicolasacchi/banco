require "test_helper"
require "minitest/mock"
require_relative "../support/decision_world"
require_relative "../support/multi_user"

# D-260: the operator's console attestation for approve_blueprint. The words waive exactly two requirements (every
# item opened in the preview; the test played to the end or confirmed as seen in full); every other one holds.
class ConsoleBlueprintAttestationTest < ActionDispatch::IntegrationTest
  include DecisionWorld
  include MultiUser

  WORDS = "Ho letto tutte le domande fuori dall'app."
  EVENT_KINDS = %w[teacher_viewed_item].freeze

  setup do
    build_decision_world
    # Reviewed and blind-solved, but never opened in the preview and never played or confirmed.
    @blueprint.pinned_item_revision_ids.each do |id|
      revision = ItemRevision.find(id)
      ItemReview.create!(item_revision: revision, agent_session: @session, checklist_json: "[]")
      BlindSolve.create!(item_revision: revision, agent_session: @session, answers_json: "[]", results_json: "[]")
    end
    @finding = ReviewFinding.create!(item_revision: @short, source: "review", severity: "major", field: "prompt", quote: "q", problem_it: "p", fix_it: "f")
    Decision.create!(kind: "dispose_finding", subject: @subject, payload_json: { finding_id: @finding.id, disposition: "dismissed", reason_it: "Va bene." }.to_json,
                     request_id: SecureRandom.uuid, teacher_login: "nik", groups: "banco-teacher", remote_addr: EDGE)
    approve_graph_row!
  end

  def attest(words: WORDS, confirm: true, kind: "approve_blueprint", revision: @blueprint, **extra)
    DecisionConsole.call(kind: kind, teacher: "nik", os_user: "operator", revision: revision.id, attest_it: words, confirm: confirm, **extra)
  end

  def refuses(reason, **args)
    assert_no_difference "Decision.count" do
      result = attest(**args)
      assert_not result.ok, "expected a refusal containing #{reason}"
      assert(result.errors.any? { |e| e.include?(reason) }, result.errors.inspect)
    end
  end

  test "without the words both preview requirements still refuse" do
    result = DecisionConsole.call(kind: "approve_blueprint", teacher: "nik", os_user: "operator", revision: @blueprint.id, confirm: true)
    assert_not result.ok
    assert(result.errors.any? { |e| e.include?("was not opened in the preview") })
    assert(result.errors.any? { |e| e.include?(Approval::BlueprintGate::NOT_PLAYED) })
  end

  test "with the words the approval is recorded with the attestation, no viewed event and no preview run" do
    assert_no_difference -> { AppEvent.where(kind: EVENT_KINDS).count } do
      assert_no_difference -> { DiagnosisRun.count } do
        assert_difference "Decision.where(kind: 'approve_blueprint').count", 1 do
          result = attest
          assert result.ok, result.errors.inspect
        end
      end
    end
    payload = JSON.parse(Decision.where(kind: "approve_blueprint").last.payload_json)
    assert_equal true, payload["attested"]
    assert_equal WORDS, payload["attest_it"]
    assert_equal %w[items_not_opened_in_preview test_not_played_or_confirmed], payload["waived"]
    assert_equal "console", payload["via"]
    assert_equal @blueprint.id, SubjectStage.approved_blueprint(@subject).id
    assert_equal WORDS, SubjectStage.blueprint_attestation(@subject)
  end

  test "a dry run writes nothing" do
    assert_no_difference "Decision.count" do
      result = attest(confirm: false)
      assert result.ok
      assert_not result.recorded
      assert_equal true, result.payload["attested"]
    end
  end

  test "blank or oversized words are refused" do
    [ "", "   ", "x" * 1001 ].each { |bad| refuses("ATTEST_IT", words: bad) }
    assert attest(words: "x" * 1000, confirm: false).ok
  end

  test "any other kind refuses the words" do
    assert_no_difference "Decision.count" do
      result = attest(kind: "approve_skill_graph", subject: "math")
      assert_not result.ok
      assert_includes result.errors.first, "only for approve_topic and approve_blueprint"
    end
  end

  test "the recorder refuses the words from a web request" do
    assert_raises(DecisionRecorder::Invalid) do
      DecisionRecorder.new(Object.new, "approve_blueprint", { revision_id: @blueprint.id, attest_it: WORDS }.with_indifferent_access).send(:attestation)
    end
  end

  test "the graph revision must still be the approved one" do
    other = SkillGraphRevision.create!(subject: @subject, seq: @graph.seq + 1, body_json: @graph.body_json)
    approve_graph_row!(@subject, other)
    refuses("is not approved")
  end

  test "guest skills must be in an approved graph" do
    Approval::BlueprintGate.stub(:unapproved_guests, [ "other.skill" ]) { refuses("guest skill other.skill") }
  end

  test "a pinned item revision must exist" do
    @blueprint.stub(:pinned_item_revision_ids, [ @blueprint.pinned_item_revision_ids.first, 999_999 ]) do
      assert_includes Approval::BlueprintGate.check(@blueprint, waive_preview: true).reasons, "item revision 999999 does not exist"
    end
  end

  test "an item revision whose Review::Gate fails still refuses" do
    gate = Review::Gate::Result.new(approvable: false, reasons: [ "no blind solve on this revision" ], open_findings: [])
    Review::Gate.stub(:check, gate) { refuses("is not approvable") }
  end

  test "a blocker or major finding without the teacher's disposition still refuses" do
    ReviewFinding.create!(item_revision: @short, source: "review", severity: "blocker", field: "prompt", quote: "q2", problem_it: "p", fix_it: "f")
    refuses("without the teacher's disposition")
  end

  test "a sent-back revision still refuses" do
    Teacher::SendBacks.stub(:sent_back?, true) { refuses("sent this revision back") }
  end

  test "a stale pin still refuses" do
    Approval::BlueprintGate.stub(:stale_pins, [ { pinned: 1, latest: 2 } ]) { refuses("W-STALE-PIN") }
  end

  test "a multi-skill testlet still refuses" do
    Approval::BlueprintGate.stub(:multi_skill_testlets, [ { revision: 1, skills: %w[a b] } ]) { refuses("W-TESTLET-MULTI-SKILL") }
  end

  test "a test with no pinned item still refuses" do
    @blueprint.stub(:pinned_item_revision_ids, []) do
      assert_includes Approval::BlueprintGate.check(@blueprint, waive_preview: true).reasons, "the test pins no item"
    end
  end

  test "only the latest entry test can be approved" do
    BlueprintRevision.create!(subject: @subject, skill_graph_revision: @graph, seq: @blueprint.seq + 1, body_json: @blueprint.body_json)
    refuses("not the latest entry test")
  end

  test "the web path ignores the words and still wants the preview" do
    assert_no_difference "Decision.where(kind: 'approve_blueprint').count" do
      decide("/teacher/blueprint-revisions/#{@blueprint.id}/approve", { attest_it: WORDS, attested: true, waived: Approval::BlueprintGate::WAIVED })
    end
    assert_response :unprocessable_entity
    make_blueprint_approvable!
    decide("/teacher/blueprint-revisions/#{@blueprint.id}/approve", { attest_it: WORDS })
    payload = JSON.parse(Decision.where(kind: "approve_blueprint").last.payload_json)
    assert_not payload.key?("attested")
    assert_not payload.key?("attest_it")
    assert_nil SubjectStage.blueprint_attestation(@subject)
  end

  test "the test page says it was approved from the console, with the words" do
    attest
    on(:web, "/teacher/subjects/math/test", headers: TEACHER, remote_addr: EDGE)
    assert_response :success
    assert_select "#test-attested", "Approvato da console, senza aprire le domande in anteprima: «#{WORDS}»"
  end

  test "an ordinary approval shows no such line" do
    make_blueprint_approvable!
    assert DecisionConsole.call(kind: "approve_blueprint", teacher: "nik", os_user: "operator", revision: @blueprint.id, confirm: true).ok
    on(:web, "/teacher/subjects/math/test", headers: TEACHER, remote_addr: EDGE)
    assert_select "#test-attested", false
  end
end
