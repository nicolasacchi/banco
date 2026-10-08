# Phase 1b (S1): the practice ledger, apart from the diagnosis ledger (attempts.context has a
# CHECK that SQLite changes only by rebuilding a ledger table). Append-only like every
# primary table; serve closure and skill states are derived from these rows.
class CreatePracticeLedgerTables < ActiveRecord::Migration[8.1]
  def change
    create_table :practice_serves do |t|
      t.references :student, null: false, foreign_key: true
      t.references :topic_revision, null: false, foreign_key: true
      t.string :skill_key, null: false
      t.references :item_instance, null: false, foreign_key: true
      t.string :reason, null: false
      t.references :parent_serve, foreign_key: { to_table: :practice_serves }
      t.string :error_code
      t.integer :seed, null: false
      t.text :shown_order_json
      t.text :id_map_json
      t.string :rules_version, null: false
      t.datetime :created_at, null: false
      t.index %i[student_id skill_key id]
      t.index %i[student_id item_instance_id]
      t.check_constraint "reason IN ('next','prova_questo','after_solution','reseen')", name: "practice_serves_reason"
      t.check_constraint "(reason = 'prova_questo') = (error_code IS NOT NULL)", name: "practice_serves_error_code"
      t.check_constraint "reason NOT IN ('prova_questo','after_solution') OR parent_serve_id IS NOT NULL", name: "practice_serves_parent"
    end

    create_table :practice_attempts do |t|
      t.references :student, null: false, foreign_key: true
      t.references :practice_serve, null: false, foreign_key: true
      t.integer :try_number, null: false
      t.string :client_attempt_id, null: false
      t.text :raw, null: false
      t.string :source, null: false
      t.integer :hints_before, null: false
      t.boolean :aided, null: false
      t.datetime :answered_at, null: false
      t.datetime :created_at, null: false
      t.index %i[practice_serve_id try_number], unique: true
      t.index :client_attempt_id, unique: true
      t.check_constraint "try_number BETWEEN 1 AND 3", name: "practice_attempts_try_number"
      t.check_constraint "source IN ('text','mathlive','button')", name: "practice_attempts_source"
      t.check_constraint "hints_before >= 0", name: "practice_attempts_hints_before"
    end

    create_table :practice_gradings do |t|
      t.references :practice_attempt, null: false, foreign_key: true
      t.integer :seq, null: false
      t.string :verdict, null: false
      t.text :error_codes_json
      t.text :form_violations_json
      t.text :normalized
      t.string :method
      t.string :grader, null: false
      t.string :grader_version, null: false
      t.string :ce_version
      t.string :source, null: false
      t.datetime :created_at, null: false
      t.index %i[practice_attempt_id seq], unique: true
      t.check_constraint "source IN ('sync','retry')", name: "practice_gradings_source"
      t.check_constraint "method IS NULL OR method IN ('exact','float')", name: "practice_gradings_method"
    end

    create_table :practice_events do |t|
      t.references :student, null: false, foreign_key: true
      t.string :kind, null: false
      t.references :practice_serve, foreign_key: true
      t.references :topic_revision, foreign_key: true
      t.references :lesson_revision, foreign_key: true
      t.text :payload_json, null: false
      t.datetime :at, null: false
      t.datetime :created_at, null: false
      t.check_constraint "kind IN ('lesson_opened','lesson_solution_shown','hint_shown','solution_shown')", name: "practice_events_kind"
      t.check_constraint "kind NOT IN ('hint_shown','solution_shown') OR practice_serve_id IS NOT NULL", name: "practice_events_serve"
      t.check_constraint "kind NOT IN ('lesson_opened','lesson_solution_shown') OR (lesson_revision_id IS NOT NULL AND topic_revision_id IS NOT NULL)", name: "practice_events_lesson"
    end

    create_table :student_questions do |t|
      t.references :student, null: false, foreign_key: true
      t.string :client_question_id, null: false
      t.references :topic_revision, foreign_key: true
      t.references :lesson_revision, foreign_key: true
      t.references :practice_serve, foreign_key: true
      t.string :section
      t.integer :exercise
      t.text :text_it
      t.datetime :created_at, null: false
      t.index :client_question_id, unique: true
      t.check_constraint "section IS NULL OR section IN ('why','idea','example','mistakes','try','solutions','book','summary','practice')", name: "student_questions_section"
      t.check_constraint "text_it IS NULL OR length(text_it) BETWEEN 1 AND 300", name: "student_questions_text_length"
    end

    reversible do |dir|
      dir.up do
        %i[practice_serves practice_attempts practice_gradings practice_events student_questions].each { |t| Banco::AppendOnly.install(connection, t) }
      end
    end
  end
end
