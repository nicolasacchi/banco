# Rich lessons R4 (D-249, A12): the render check of a lesson/2 revision in the server's Chrome. One append-only row per
# attempt that ended (passed, failed) or could not run (error: Chrome down, the host not answering; never a pass).
# shots_json lists the screenshots stored by content (storage/lesson_shots/<sha256>.webp); the files may be purged
# later, the rows stay.
class CreateLessonRenders < ActiveRecord::Migration[8.1]
  def change
    create_table :lesson_renders do |t|
      t.references :lesson_revision, null: false, foreign_key: true
      t.string :status, null: false
      t.string :rules_version
      t.string :harness_version, null: false
      t.string :chrome_version
      t.integer :attempt
      t.text :result_json, null: false
      t.text :shots_json, null: false
      t.datetime :created_at, null: false
      t.index %i[lesson_revision_id id]
      t.check_constraint "status IN ('passed','failed','error')", name: "lesson_renders_status"
    end

    reversible do |dir|
      dir.up { Banco::AppendOnly.install(connection, :lesson_renders) }
    end
  end
end
