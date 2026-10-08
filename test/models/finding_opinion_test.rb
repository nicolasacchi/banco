require "test_helper"
require_relative "../support/arbiter_rows"

# D-222: the states of the third reviewer's two opinions and what they allow.
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

  test "one opinion so far is waiting, whichever it is, and never clear" do
    assess!(@finding, "author_right", session: arbiter_session(FIRST_MODEL))
    assert_equal :waiting, opinion.state
    assert_nil opinion.verdict
    assert_nil opinion.disposition
    assert_nil opinion.minor_outcome
  end

  test "the second opinion alone is waiting too" do
    assess!(@finding, "finding_right", session: arbiter_session(SECOND_MODEL))
    assert_equal :waiting, opinion.state
    assert_nil opinion.first
  end

  test "both agree on a side: clear, with the disposition and the minor outcome" do
    assess_both!(@finding, "author_right")
    assert_equal [ :clear, "author_right", "dismissed", :closed ], [ opinion.state, opinion.verdict, opinion.disposition, opinion.minor_outcome ]
  end

  test "both say finding_right: clear, fix requested, to fix" do
    assess_both!(@finding, "finding_right")
    assert_equal [ :clear, "fix_requested", :to_fix ], [ opinion.state, opinion.disposition, opinion.minor_outcome ]
  end

  test "they differ: split, whatever the pair" do
    [ %w[author_right finding_right], %w[finding_right author_right], %w[unclear author_right], %w[finding_right unclear] ].each_with_index do |(a, b), i|
      finding = ReviewFinding.create!(item_revision: @finding.item_revision, source: "review", severity: "minor", field: "f", quote: "q#{i}", problem_it: "p", fix_it: "f")
      assess_both!(finding, a, b)
      op = FindingAssessment.opinions_for([ finding.id ])[finding.id]
      assert_equal :split, op.state, [ a, b ].inspect
      assert_nil op.disposition
      assert_nil op.minor_outcome
    end
  end

  test "both unclear: unclear, nothing to follow" do
    assess_both!(@finding, "unclear")
    assert_equal [ :unclear, nil, nil, nil ], [ opinion.state, opinion.verdict, opinion.disposition, opinion.minor_outcome ]
  end

  test "a newer assessment of a model replaces its older one" do
    assess_both!(@finding, "author_right", "finding_right")
    assert_equal :split, opinion.state
    assess!(@finding, "finding_right", session: arbiter_session(FIRST_MODEL))
    assert_equal :clear, opinion.state
    assert_equal "finding_right", opinion.verdict
  end

  test "an assessment by another model gives no opinion" do
    assess!(@finding, "author_right", session: AgentSession.create!(label: "t", role: "arbiter", agent: "t", model: "other"))
    assert_equal :none, opinion.state
  end
end
