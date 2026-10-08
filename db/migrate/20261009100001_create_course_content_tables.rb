# Phase 1b (S1): the course content. A lesson is the identity of a topic (its key is the
# topic key); revisions are immutable. All tables append-only like every primary table.
class CreateCourseContentTables < ActiveRecord::Migration[8.1]
  def change
    create_table :lessons do |t|
      t.references :subject, null: false, foreign_key: true
      t.string :key, null: false
      t.string :kind, null: false
      t.datetime :created_at, null: false
      t.index :key, unique: true
      t.check_constraint "kind IN ('ripasso','ponte','lezione')", name: "lessons_kind"
    end

    create_table :lesson_revisions do |t|
      t.references :lesson, null: false, foreign_key: true
      t.integer :seq, null: false
      t.references :base_revision, foreign_key: { to_table: :lesson_revisions }
      t.text :source_md, null: false
      t.string :source_sha256, null: false
      t.text :body_json, null: false
      t.string :rules_version, null: false
      t.text :warnings_json, null: false
      t.references :author_session, foreign_key: { to_table: :agent_sessions }
      t.string :brief_sha256
      t.datetime :created_at, null: false
      t.index %i[lesson_id seq], unique: true
      t.check_constraint "length(source_sha256) = 64", name: "lesson_revisions_sha256_length"
    end

    create_table :lesson_reviews do |t|
      t.references :lesson_revision, null: false, foreign_key: true
      t.references :agent_session, null: false, foreign_key: true
      t.text :checklist_json, null: false
      t.text :recomputed_json, null: false
      t.text :findings_json, null: false
      t.string :brief_sha256
      t.datetime :created_at, null: false
      t.index %i[lesson_revision_id agent_session_id], unique: true
    end

    create_table :course_revisions do |t|
      t.references :subject, null: false, foreign_key: true
      t.integer :seq, null: false
      t.references :skill_graph_revision, null: false, foreign_key: true
      t.text :body_json, null: false
      t.text :warnings_json, null: false
      t.references :author_session, foreign_key: { to_table: :agent_sessions }
      t.string :brief_sha256
      t.datetime :created_at, null: false
      t.index %i[subject_id seq], unique: true
    end

    create_table :topic_revisions do |t|
      t.references :lesson, null: false, foreign_key: true
      t.integer :seq, null: false
      t.references :course_revision, null: false, foreign_key: true
      t.references :lesson_revision, null: false, foreign_key: true
      t.text :body_json, null: false
      t.references :author_session, foreign_key: { to_table: :agent_sessions }
      t.string :brief_sha256
      t.datetime :created_at, null: false
      t.index %i[lesson_id seq], unique: true
    end

    reversible do |dir|
      dir.up do
        %i[lessons lesson_revisions lesson_reviews course_revisions topic_revisions].each { |t| Banco::AppendOnly.install(connection, t) }
      end
    end
  end
end
