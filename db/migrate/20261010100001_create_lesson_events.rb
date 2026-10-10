# Rich lessons (R3, A11): the lesson's own ledger, apart from practice_events (whose kind CHECK SQLite changes only
# by rebuilding the table, D-228). Every kind the spec foresees is in the CHECK from the start, so a later release adds
# a writer, never a table rebuild; release 1 writes card_seen and check_answered only. Append-only like every primary
# table. student_questions gains the card the question was asked on (ALTER TABLE ADD COLUMN: no rebuild, the
# append-only triggers stay).
class CreateLessonEvents < ActiveRecord::Migration[8.1]
  def change
    create_table :lesson_events do |t|
      t.references :student, null: false, foreign_key: true
      t.references :topic_revision, null: false, foreign_key: true
      t.references :lesson_revision, null: false, foreign_key: true
      t.string :kind, null: false
      t.integer :card
      t.integer :block
      t.integer :page_revision_id
      t.text :payload_json, null: false
      t.string :grader_version
      t.string :client_event_id
      t.datetime :at, null: false
      t.datetime :created_at, null: false
      t.index %i[student_id lesson_revision_id kind id], name: "index_lesson_events_on_student_revision_kind"
      t.index %i[student_id client_event_id], unique: true, where: "client_event_id IS NOT NULL", name: "index_lesson_events_on_client_event"
      t.check_constraint "kind IN ('card_seen','check_answered','more_opened','steps_shown','lesson_printed','page_opened','page_event','page_failed')", name: "lesson_events_kind"
      t.check_constraint "kind NOT IN ('card_seen','check_answered') OR card IS NOT NULL", name: "lesson_events_card"
      t.check_constraint "kind <> 'check_answered' OR (block IS NOT NULL AND grader_version IS NOT NULL)", name: "lesson_events_check"
    end

    add_column :student_questions, :card, :integer

    reversible do |dir|
      dir.up { Banco::AppendOnly.install(connection, :lesson_events) }
    end
  end
end
