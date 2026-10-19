require "test_helper"
require_relative "../support/arbiter_rows"

# D-222, D-316: the states of the third reviewer's opinion and what they allow. Only the first opinion counts.
class FindingOpinionTest < ActiveSupport::TestCase
  include ArbiterRows

  setup do
    subject = Subject.create!(key: "fo", name_it: "Fo", position: 1)
    item = Item.create!(subject: subject, key: "fo-1", kind: "diagnosis_item")
    revision = ItemRevision.create!(item: item, seq: 1, body_json: "{}", file_sessions_json: "{}")
    @finding = ReviewFinding.create!(item_revision: revision, source: "review", severity: "minor", field: "f", quote: "q", problem_it: "p", fix_it: "f")
  end

  def opinion = FindingAssessment.opinions_for([ @finding.id ])[@finding.id]

  test "no assessment: none" do
    assert_equal :none, opinion.state
    refute opinion.any?
    refute opinion.clear?
  end

  test "one opinion is enough: clear when it takes a side, and a minor finding gets its outcome" do
    assess!(@finding, "author_right", session: arbiter_session(FIRST_MODEL))
    assert_equal [ :clear, "author_right", "dismissed", :closed ], [ opinion.state, opinion.verdict, opinion.disposition, opinion.minor_outcome ]
  end

  test "finding_right: clear, fix requested, to fix" do
    assess!(@finding, "finding_right")
    assert_equal [ :clear, "fix_requested", :to_fix ], [ opinion.state, opinion.disposition, opinion.minor_outcome ]
  end

  test "unclear: nothing to follow, nothing decided" do
    assess!(@finding, "unclear")
    assert_equal [ :unclear, nil, nil, nil ], [ opinion.state, opinion.verdict, opinion.disposition, opinion.minor_outcome ]
  end

  test "an old second opinion alone is history: no opinion, no outcome (D-316)" do
    assess!(@finding, "finding_right", session: arbiter_session(OLD_SECOND_MODEL))
    assert_equal :none, opinion.state
    assert_nil opinion.first
    assert_nil opinion.minor_outcome
    assert_equal [ :second_opinion ], opinion.history.map(&:ignored_reason)
  end

  test "an old second opinion never changes a state, whatever it says (D-316)" do
    [ %w[author_right finding_right], %w[finding_right author_right], %w[unclear author_right], %w[finding_right unclear] ].each_with_index do |(a, b), i|
      finding = ReviewFinding.create!(item_revision: @finding.item_revision, source: "review", severity: "minor", field: "f", quote: "q#{i}", problem_it: "p", fix_it: "f")
      assess_with_old_second!(finding, a, b)
      op = FindingAssessment.opinions_for([ finding.id ])[finding.id]
      assert_equal a == "unclear" ? :unclear : :clear, op.state, [ a, b ].inspect
      assert_equal a, op.first.verdict
      assert_equal 1, op.history.size
      assert_equal b, op.history.first.verdict
      expected = { "author_right" => :closed, "finding_right" => :to_fix }[a]
      expected.nil? ? assert_nil(op.minor_outcome) : assert_equal(expected, op.minor_outcome)
    end
  end

  test "a newer assessment of the arbiter replaces its older one" do
    assess!(@finding, "author_right", session: arbiter_session(FIRST_MODEL))
    assess!(@finding, "finding_right", session: arbiter_session(FIRST_MODEL))
    assert_equal "finding_right", opinion.verdict
  end

  test "an assessment by another model gives no opinion" do
    assess!(@finding, "author_right", session: AgentSession.create!(label: "t", role: "arbiter", agent: "t", model: "other"))
    assert_equal :none, opinion.state
  end

  test "an opinion by a session on the model of the one that raised the finding does not count: the minor goes back to the teacher (D-316)" do
    reviewer = AgentSession.create!(label: "r", role: "reviewer", agent: "t", model: "claude-sonnet-5-5")
    review = ItemReview.create!(item_revision: @finding.item_revision, agent_session: reviewer, checklist_json: "[]")
    finding = ReviewFinding.create!(item_revision: @finding.item_revision, item_review: review, source: "review", severity: "minor", field: "f", quote: "r", problem_it: "p", fix_it: "f")
    arbiter = arbiter_session(FIRST_MODEL)
    assess!(finding, "author_right", session: arbiter)
    op = FindingAssessment.opinions_for([ finding.id ])[finding.id]
    assert_equal :closed, op.minor_outcome, "different models: it counts"
    AgentSessionCorrection.create!(agent_session: reviewer, model: FIRST_MODEL, reason: "the reviewer ran on Opus", request_id: "fo-1")
    op = FindingAssessment.opinions_for([ finding.id ])[finding.id]
    assert_equal :none, op.state
    assert_nil op.minor_outcome
    assert_equal [ :same_model_as_raiser ], op.history.map(&:ignored_reason)
    assert ReviewFinding.find(finding.id).opinion_slot_blocked?
  end
end
