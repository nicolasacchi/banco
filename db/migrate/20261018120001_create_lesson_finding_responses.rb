# D-313: the author's answer to a finding of a lesson review, the lesson twin of finding_responses (D-220).
# A lesson review keeps its findings inline (lesson_reviews.findings_json) and the row never changes, so a
# finding is named by its review and its position in that list (finding_n, from 1): the id L<review>-<n>.
# Append-only like every primary table. A response never disposes of a finding: only the teacher decides
# (firm rule 2), when she approves the topic or sends the lesson back. stance lesson_right: the lesson is
# right, note_it is the short proof. stance fixed: a later revision of the same lesson fixes it
# (lesson_revision_id, checked by the API).
class CreateLessonFindingResponses < ActiveRecord::Migration[8.1]
  def change
    create_table :lesson_finding_responses do |t|
      t.references :lesson_review, null: false, foreign_key: true, index: false
      t.integer :finding_n, null: false
      t.references :agent_session, null: false, foreign_key: true
      t.string :stance, null: false
      t.references :lesson_revision, foreign_key: true
      t.text :note_it, null: false
      t.datetime :created_at, null: false
      t.index %i[lesson_review_id finding_n]
      t.check_constraint "finding_n BETWEEN 1 AND 30", name: "lesson_finding_responses_n"
      t.check_constraint "stance IN ('lesson_right','fixed')", name: "lesson_finding_responses_stance"
      t.check_constraint "(stance = 'fixed') = (lesson_revision_id IS NOT NULL)", name: "lesson_finding_responses_revision"
      t.check_constraint "length(note_it) BETWEEN 1 AND 700", name: "lesson_finding_responses_note_length"
    end

    reversible do |dir|
      dir.up { Banco::AppendOnly.install(connection, :lesson_finding_responses) }
    end
  end
end
