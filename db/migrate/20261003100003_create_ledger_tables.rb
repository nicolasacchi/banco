# The ledger: students, decisions with provenance, diagnosis runs and events,
# served items, attempts, gradings and application events (B-08, A-01, X-01, D-08).
class CreateLedgerTables < ActiveRecord::Migration[8.1]
  TABLES = %i[students decisions diagnosis_runs diagnosis_events item_served attempts
              attempt_gradings app_events].freeze

  def change
    create_table :students do |t|
      t.string :key, null: false, index: { unique: true }
      t.string :kind, null: false
      t.datetime :created_at, null: false
      t.check_constraint "kind IN ('student','preview')", name: "students_kind"
    end

    # Decisions are created only by DecisionRecorder (D-08); the provenance columns
    # let the nightly reconciliation match each row to a proxy access-log line.
    create_table :decisions do |t|
      t.string :kind, null: false
      t.references :subject, foreign_key: true
      t.references :student, foreign_key: true
      t.text :payload_json, null: false
      t.string :request_id, null: false
      t.string :teacher_login, null: false
      t.string :remote_addr, null: false
      t.datetime :created_at, null: false
      t.index :request_id, unique: true
    end

    create_table :diagnosis_runs do |t|
      t.references :student, null: false, foreign_key: true
      t.references :subject, null: false, foreign_key: true
      t.references :blueprint_revision, null: false, foreign_key: true
      t.integer :sequence, null: false
      t.string :seed_salt, null: false
      t.string :rules_version, null: false
      t.string :engine_version, null: false
      t.datetime :created_at, null: false
      t.index %i[student_id subject_id sequence], unique: true
    end

    create_table :diagnosis_events do |t|
      t.references :diagnosis_run, null: false, foreign_key: true
      t.integer :seq, null: false
      t.string :kind, null: false
      t.text :payload_json
      t.datetime :at, null: false
      t.datetime :created_at, null: false
      t.index %i[diagnosis_run_id seq], unique: true
    end

    # Detail of an item_served event: what was shown, in which order, and the
    # id map from shown ids back to the instance's ids (never sent to S).
    create_table :item_served do |t|
      t.references :diagnosis_event, null: false, foreign_key: true, index: { unique: true }
      t.references :item_instance, null: false, foreign_key: true
      t.string :skill_key, null: false
      t.text :shown_order_json
      t.text :id_map_json
      t.datetime :created_at, null: false
    end

    create_table :attempts do |t|
      t.references :student, null: false, foreign_key: true
      t.string :context, null: false
      t.references :served_event, foreign_key: { to_table: :diagnosis_events }, index: { unique: true }
      t.string :client_attempt_id, null: false, index: { unique: true }
      t.references :item_instance, null: false, foreign_key: true
      t.text :raw, null: false
      t.string :source, null: false
      t.datetime :answered_at, null: false
      t.datetime :created_at, null: false
      t.check_constraint "context IN ('diagnosis','teacher_preview','warmup')", name: "attempts_context"
    end

    # A grading is never edited: a retry appends a row with a higher seq. The
    # verdict of an attempt is its latest grading (A-01).
    create_table :attempt_gradings do |t|
      t.references :attempt, null: false, foreign_key: true
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
      t.index %i[attempt_id seq], unique: true
      t.check_constraint "source IN ('sync','retry')", name: "attempt_gradings_source"
      t.check_constraint "method IS NULL OR method IN ('exact','float')", name: "attempt_gradings_method"
    end

    create_table :app_events do |t|
      t.string :kind, null: false
      t.references :student, foreign_key: true
      t.text :payload_json
      t.datetime :created_at, null: false
    end

    reversible do |dir|
      dir.up { TABLES.each { |table| Banco::AppendOnly.install(connection, table) } }
    end
  end
end
