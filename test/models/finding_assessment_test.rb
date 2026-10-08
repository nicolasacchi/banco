require "test_helper"
require_relative "../support/arbiter_rows"

# D-222: the arbiter's opinions are append-only and check their own shape; the effective opinion
# of a finding is the latest assessment of each of the two models.
class FindingAssessmentTest < ActiveSupport::TestCase
  include ArbiterRows

  setup do
    subject = Subject.create!(key: "fa", name_it: "Fa", position: 1)
    item = Item.create!(subject: subject, key: "fa-1", kind: "diagnosis_item")
    @revision = ItemRevision.create!(item: item, seq: 1, body_json: "{}", file_sessions_json: "{}")
    @finding = ReviewFinding.create!(item_revision: @revision, source: "review", severity: "major", field: "f", quote: "q", problem_it: "p", fix_it: "f")
    @first = arbiter_session(FIRST_MODEL)
    @second = arbiter_session(SECOND_MODEL)
  end

  def build(**attrs) = FindingAssessment.new({ review_finding: @finding, agent_session: @first, verdict: "author_right", note_it: "La chiave è giusta." }.merge(attrs))

  test "the verdict and the note length are checked by the database" do
    assert build.save
    %w[author_right finding_right unclear].each { |v| assert build(verdict: v).save, v }
    assert_raises(ActiveRecord::StatementInvalid) { build(verdict: "maybe").save(validate: false) }
    assert_raises(ActiveRecord::StatementInvalid) { build(note_it: "").save(validate: false) }
    assert_raises(ActiveRecord::StatementInvalid) { build(note_it: "a" * 501).save(validate: false) }
    assert build(note_it: "a" * 500).save
    refute build(verdict: "maybe").valid?
  end

  test "rows are never updated or deleted" do
    row = build.tap(&:save!)
    assert_raises(ActiveRecord::StatementInvalid) { row.update_columns(note_it: "Altro.") }
    assert_raises(ActiveRecord::StatementInvalid) { FindingAssessment.where(id: row.id).delete_all }
  end

  test "a row needs a finding and a session" do
    assert_raises(ActiveRecord::StatementInvalid) { build(review_finding_id: 999_999).save(validate: false) }
    assert_raises(ActiveRecord::StatementInvalid) { build(agent_session_id: 999_999).save(validate: false) }
  end

  test "the slot comes from the model of the session, nil for any other model" do
    assert_equal :first, build.tap(&:save!).slot
    assert_equal :second, build(agent_session: @second).tap(&:save!).slot
    assert_nil build(agent_session: AgentSession.create!(label: "t", role: "arbiter", agent: "t", model: "other")).slot
    assert_equal :second, Providers.opinion_slot("Anthropic/CLAUDE-HAIKU-4-5-20251001")
  end

  test "opinions_for keeps the latest assessment of each model and is one entry per finding" do
    other = ReviewFinding.create!(item_revision: @revision, source: "review", severity: "minor", field: "f", quote: "q", problem_it: "p", fix_it: "f")
    build(verdict: "unclear").save!
    latest_first = build(verdict: "finding_right").tap(&:save!)
    second = build(agent_session: @second, verdict: "finding_right").tap(&:save!)
    opinions = FindingAssessment.opinions_for([ @finding.id, other.id ])
    assert_equal [ latest_first, second ], opinions[@finding.id].given
    assert_equal :clear, opinions[@finding.id].state
    assert_equal :none, opinions[other.id].state
    assert_equal :clear, @finding.opinion.state
  end
end
