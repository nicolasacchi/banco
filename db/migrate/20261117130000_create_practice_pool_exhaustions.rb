# D-348: the day a student found no exercise left that she had not seen on a skill, so the teacher can write more (practice/5: the selector no longer
# serves a seen one on its own). One row per student, topic revision and skill (unique); the first time only. Append-only like every primary table.
class CreatePracticePoolExhaustions < ActiveRecord::Migration[8.1]
  def change
    create_table :practice_pool_exhaustions do |t|
      t.references :student, null: false, foreign_key: true
      t.references :topic_revision, null: false, foreign_key: true
      t.string :skill_key, null: false
      t.datetime :created_at, null: false
      t.index %i[student_id topic_revision_id skill_key], unique: true, name: "index_practice_pool_exhaustions_on_student_revision_skill"
    end

    reversible do |dir|
      dir.up { Banco::AppendOnly.install(connection, :practice_pool_exhaustions) }
    end
  end
end
