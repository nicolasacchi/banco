# D-337: what the student has typed in an exercise she has not answered yet, saved on the server as she types and when she leaves, so that
# reopening the exercise on any device puts it back. Append-only like every primary table: the latest row of a serve is its draft, and a raw of ""
# clears it. A draft is never a try: it is not graded and counts for nothing (practice/2).
class CreatePracticeDrafts < ActiveRecord::Migration[8.1]
  def change
    create_table :practice_drafts do |t|
      t.references :student, null: false, foreign_key: true
      t.references :practice_serve, null: false, foreign_key: true
      t.text :raw, null: false
      t.string :source
      t.datetime :created_at, null: false
      t.index %i[practice_serve_id id]
    end

    reversible do |dir|
      dir.up { Banco::AppendOnly.install(connection, :practice_drafts) }
    end
  end
end
