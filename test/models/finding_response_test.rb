require "test_helper"

# D-220: the table of the author's answers is append-only and checks its own shape.
class FindingResponseTest < ActiveSupport::TestCase
  setup do
    subject = Subject.create!(key: "fr", name_it: "Fr", position: 1)
    item = Item.create!(subject: subject, key: "fr-1", kind: "diagnosis_item")
    @revision = ItemRevision.create!(item: item, seq: 1, body_json: "{}", file_sessions_json: "{}")
    @newer = ItemRevision.create!(item: item, seq: 2, body_json: "{}", file_sessions_json: "{}")
    @session = AgentSession.create!(label: "t", role: "author", agent: "t", model: "m")
    @finding = ReviewFinding.create!(item_revision: @revision, source: "review", severity: "major", field: "f", quote: "q", problem_it: "p", fix_it: "f")
  end

  def build(**attrs) = FindingResponse.new({ review_finding: @finding, agent_session: @session, stance: "item_right", note_it: "La chiave è giusta." }.merge(attrs))

  test "item_right has no revision and fixed needs one" do
    assert build.save
    assert build(stance: "fixed", item_revision: @newer).save
    assert_raises(ActiveRecord::StatementInvalid) { build(stance: "fixed").save(validate: false) }
    assert_raises(ActiveRecord::StatementInvalid) { build(item_revision: @newer).save(validate: false) }
  end

  test "the stance and the note length are checked by the database" do
    assert_raises(ActiveRecord::StatementInvalid) { build(stance: "maybe").save(validate: false) }
    assert_raises(ActiveRecord::StatementInvalid) { build(note_it: "").save(validate: false) }
    assert_raises(ActiveRecord::StatementInvalid) { build(note_it: "a" * 701).save(validate: false) }
    assert build(note_it: "a" * 700).save
  end

  test "rows are never updated or deleted" do
    row = build.tap(&:save!)
    assert_raises(ActiveRecord::StatementInvalid) { row.update_columns(note_it: "Altro.") }
    assert_raises(ActiveRecord::StatementInvalid) { FindingResponse.where(id: row.id).delete_all }
  end

  test "the latest response of a finding wins" do
    build.save!
    last = build(stance: "fixed", item_revision: @newer).tap(&:save!)
    assert_equal last, FindingResponse.latest_for([ @finding.id ])[@finding.id]
  end
end
