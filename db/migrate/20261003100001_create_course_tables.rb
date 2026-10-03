# Course content: programme sources and lines, reference texts, subjects, graph
# and blueprint revisions, items and their revisions, validations and instances.
# All append-only (decisions B-07, B-08, X-01, E-09).
class CreateCourseTables < ActiveRecord::Migration[8.1]
  TABLES = %i[subjects syllabus_sources syllabus_lines reference_texts skill_graph_revisions
              items item_revisions item_validations item_instances blueprint_revisions].freeze

  def change
    create_table :subjects do |t|
      t.string :key, null: false, index: { unique: true }
      t.string :name_it, null: false
      t.integer :position, null: false
      t.datetime :created_at, null: false
    end

    create_table :syllabus_sources do |t|
      t.string :key, null: false, index: { unique: true }
      t.integer :line_count, null: false
      t.string :sha256, null: false, limit: 64
      t.datetime :created_at, null: false
    end

    # One row per physical line (newline-terminated). origin: pdf = content of the
    # original document, transcript = transcriber scaffolding (never cited),
    # operator = lines added by the operator. parts_json holds the sub-line
    # addresses ("A1", "A2", ...) for table rows and bulleted lines.
    create_table :syllabus_lines do |t|
      t.references :syllabus_source, null: false, foreign_key: true
      t.integer :number, null: false
      t.text :text, null: false
      t.string :origin, null: false
      t.string :marker
      t.text :parts_json
      t.datetime :created_at, null: false
      t.index %i[syllabus_source_id number], unique: true
      t.check_constraint "origin IN ('pdf','transcript','operator')", name: "syllabus_lines_origin"
    end

    create_table :reference_texts do |t|
      t.string :key, null: false, index: { unique: true }
      t.string :title, null: false
      t.string :source_url, null: false
      t.string :sha256, null: false, limit: 64
      t.text :body, null: false
      t.datetime :created_at, null: false
    end

    create_table :skill_graph_revisions do |t|
      t.references :subject, null: false, foreign_key: true
      t.integer :seq, null: false
      t.text :body_json, null: false
      t.integer :author_session_id
      t.string :brief_sha256
      t.datetime :created_at, null: false
      t.index %i[subject_id seq], unique: true
    end

    create_table :items do |t|
      t.references :subject, null: false, foreign_key: true
      t.string :key, null: false, index: { unique: true }
      t.string :kind, null: false
      t.datetime :created_at, null: false
    end

    # file_sessions {file name => agent session id} records who authored each file
    # (grader_is_author and the disjoint-session rule, E-09).
    create_table :item_revisions do |t|
      t.references :item, null: false, foreign_key: true
      t.integer :seq, null: false
      t.integer :base_revision_id
      t.text :body_json, null: false
      t.integer :author_session_id
      t.text :file_sessions_json
      t.string :brief_sha256
      t.datetime :created_at, null: false
      t.index %i[item_id seq], unique: true
    end

    # Validation outcomes are rows of their own: a revision never changes.
    create_table :item_validations do |t|
      t.references :item_revision, null: false, foreign_key: true
      t.integer :seq, null: false
      t.string :status, null: false
      t.text :codes_json
      t.datetime :created_at, null: false
      t.index %i[item_revision_id seq], unique: true
    end

    create_table :item_instances do |t|
      t.references :item_revision, null: false, foreign_key: true
      t.integer :seed
      t.text :display_json, null: false
      t.text :answer_json, null: false
      t.text :errors_json
      t.text :solution_json
      t.string :fingerprint, null: false, limit: 64
      t.datetime :created_at, null: false
      t.index %i[item_revision_id fingerprint]
    end

    create_table :blueprint_revisions do |t|
      t.references :subject, null: false, foreign_key: true
      t.references :skill_graph_revision, null: false, foreign_key: true
      t.integer :seq, null: false
      t.text :body_json, null: false
      t.integer :author_session_id
      t.string :brief_sha256
      t.datetime :created_at, null: false
      t.index %i[subject_id seq], unique: true
    end

    reversible do |dir|
      dir.up { TABLES.each { |table| Banco::AppendOnly.install(connection, table) } }
    end
  end
end
