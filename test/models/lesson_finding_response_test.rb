require "test_helper"

# D-313: the author's answers to the findings of a lesson review are append-only and check their own shape; a
# finding is named by its review and its place in the review's list (LessonFindings).
class LessonFindingResponseTest < ActiveSupport::TestCase
  setup do
    subject = Subject.create!(key: "lfr", name_it: "Lfr", position: 1)
    lesson = Lesson.create!(subject: subject, key: "ripasso.lfr.demo", kind: "ripasso")
    @revision = LessonRevision.create!(lesson: lesson, seq: 1, source_md: "x", source_sha256: "a" * 64, body_json: "{}", rules_version: "9", warnings_json: "[]")
    @newer = LessonRevision.create!(lesson: lesson, seq: 2, source_md: "y", source_sha256: "b" * 64, body_json: "{}", rules_version: "9", warnings_json: "[]")
    reviewer = AgentSession.create!(label: "r", role: "reviewer", agent: "t", model: "gpt-5.2")
    findings = [ { severity: "major", card: 2, quote: "q", problem_it: "p", fix_it: "f" }, { severity: "minor", card: 0, quote: "q", problem_it: "p", fix_it: "f" } ]
    @review = LessonReview.create!(lesson_revision: @revision, agent_session: reviewer, checklist_json: "[]", recomputed_json: "[]", findings_json: JSON.generate(findings))
    @session = AgentSession.create!(label: "t", role: "author", agent: "t", model: "m")
  end

  def build(**attrs)
    LessonFindingResponse.new({ lesson_review: @review, finding_n: 1, agent_session: @session, stance: "lesson_right", note_it: "La lezione è giusta." }.merge(attrs))
  end

  test "lesson_right has no revision and fixed needs one" do
    assert build.save
    assert build(stance: "fixed", lesson_revision: @newer).save
    assert_raises(ActiveRecord::StatementInvalid) { build(stance: "fixed").save(validate: false) }
    assert_raises(ActiveRecord::StatementInvalid) { build(lesson_revision: @newer).save(validate: false) }
  end

  test "the stance, the position and the note length are checked by the database" do
    assert_raises(ActiveRecord::StatementInvalid) { build(stance: "item_right").save(validate: false) }
    assert_raises(ActiveRecord::StatementInvalid) { build(finding_n: 0).save(validate: false) }
    assert_raises(ActiveRecord::StatementInvalid) { build(finding_n: 31).save(validate: false) }
    assert_raises(ActiveRecord::StatementInvalid) { build(note_it: "").save(validate: false) }
    assert_raises(ActiveRecord::StatementInvalid) { build(note_it: "a" * 701).save(validate: false) }
    assert build(note_it: "a" * 700).save
  end

  test "rows are never updated or deleted" do
    row = build.tap(&:save!)
    assert_raises(ActiveRecord::StatementInvalid) { row.update_columns(note_it: "Altro.") }
    assert_raises(ActiveRecord::StatementInvalid) { LessonFindingResponse.where(id: row.id).delete_all }
  end

  test "an id names one finding of one review, and the latest response of it wins" do
    build.save!
    last = build(stance: "fixed", lesson_revision: @newer).tap(&:save!)
    build(finding_n: 2).save!
    entry = LessonFindings.find("L#{@review.id}-1")
    assert_equal [ "L#{@review.id}-1", 1, "major", 2, last ], [ entry.id, entry.n, entry.severity, entry.card, entry.response ]
    assert_equal [ "L#{@review.id}-1", "L#{@review.id}-2" ], LessonFindings.entries([ @review ]).map(&:id)
    [ "L#{@review.id}-3", "L#{@review.id}-0", "L0-1", "#{@review.id}", "L#{@review.id}", "x" ].each { |id| assert_nil LessonFindings.find(id), id }
  end
end
