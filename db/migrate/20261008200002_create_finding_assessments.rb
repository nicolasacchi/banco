# D-222: the arbiter's opinion on a finding (blocker, major or minor). Append-only like every
# primary table. An assessment never disposes of a finding: only the teacher does (firm rule 2);
# it tells the teacher who the third reviewer thinks is right and why. The latest one counts.
class CreateFindingAssessments < ActiveRecord::Migration[8.1]
  def change
    create_table :finding_assessments do |t|
      t.references :review_finding, null: false, foreign_key: true
      t.references :agent_session, null: false, foreign_key: true
      t.string :verdict, null: false
      t.text :note_it, null: false
      t.datetime :created_at, null: false
      t.check_constraint "verdict IN ('author_right','finding_right','unclear')", name: "finding_assessments_verdict"
      t.check_constraint "length(note_it) BETWEEN 1 AND 500", name: "finding_assessments_note_length"
    end

    reversible do |dir|
      dir.up { Banco::AppendOnly.install(connection, :finding_assessments) }
    end
  end
end
