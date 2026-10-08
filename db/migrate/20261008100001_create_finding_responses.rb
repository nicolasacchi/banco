# D-220: the author's answer to a finding (blocker or major) of a review or a blind solve.
# Append-only like every primary table. A response never disposes of a finding: only the
# teacher does (firm rule 2); it tells the teacher what the author thinks and what it did.
# stance item_right: the item is right, note_it is the short proof. stance fixed: a later
# revision of the same item fixes it (item_revision_id, checked by the API).
class CreateFindingResponses < ActiveRecord::Migration[8.1]
  def change
    create_table :finding_responses do |t|
      t.references :review_finding, null: false, foreign_key: true
      t.references :agent_session, null: false, foreign_key: true
      t.string :stance, null: false
      t.references :item_revision, foreign_key: true
      t.text :note_it, null: false
      t.datetime :created_at, null: false
      t.check_constraint "stance IN ('item_right','fixed')", name: "finding_responses_stance"
      t.check_constraint "(stance = 'fixed') = (item_revision_id IS NOT NULL)", name: "finding_responses_revision"
      t.check_constraint "length(note_it) BETWEEN 1 AND 700", name: "finding_responses_note_length"
    end

    reversible do |dir|
      dir.up { Banco::AppendOnly.install(connection, :finding_responses) }
    end
  end
end
