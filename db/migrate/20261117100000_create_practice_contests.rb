# D-339: «Fai controllare», the student sends a try she believes right to the teacher. One row per contested attempt (unique), with the comment
# the teacher reads (none in the teacher's preview, D-309). Append-only like every primary table: the try's outcome becomes `contested` by this
# row's existence (derived), the attempt and its grading are never changed.
class CreatePracticeContests < ActiveRecord::Migration[8.1]
  def change
    create_table :practice_contests do |t|
      t.references :student, null: false, foreign_key: true
      t.references :practice_serve, null: false, foreign_key: true
      t.references :practice_attempt, null: false, foreign_key: true, index: { unique: true }
      t.references :comment, foreign_key: true
      t.datetime :created_at, null: false
    end

    reversible do |dir|
      dir.up { Banco::AppendOnly.install(connection, :practice_contests) }
    end
  end
end
