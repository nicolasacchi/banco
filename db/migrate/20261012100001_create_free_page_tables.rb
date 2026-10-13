# Free pages, release 2 (D-289, SPEC B9): a page is its own content unit with revisions, like an item. All five tables are
# append-only (triggers). The bytes of a file live on disk in storage/pages/<sha256>, written once, never rewritten; the
# rows only name them. A validation row says which kit version it ran with: what was validated is what runs.
class CreateFreePageTables < ActiveRecord::Migration[8.1]
  def change
    create_table :pages do |t|
      t.string :key, null: false
      t.references :subject, null: false, foreign_key: true
      t.datetime :created_at, null: false
      t.index :key, unique: true
    end

    create_table :page_revisions do |t|
      t.references :page, null: false, foreign_key: true
      t.integer :seq, null: false
      t.references :base_revision, foreign_key: { to_table: :page_revisions }
      t.text :manifest_json, null: false
      t.string :bundle_sha256, null: false
      t.string :rules_version, null: false
      t.text :warnings_json, null: false
      t.references :author_session, foreign_key: { to_table: :agent_sessions }
      t.string :brief_sha256
      t.datetime :created_at, null: false
      t.index %i[page_id seq], unique: true
      t.index :bundle_sha256, unique: true
      t.check_constraint "length(bundle_sha256) = 64", name: "page_revisions_sha256_length"
    end

    create_table :page_files do |t|
      t.references :page_revision, null: false, foreign_key: true
      t.string :path, null: false
      t.string :sha256, null: false
      t.integer :bytes, null: false
      t.string :media_type, null: false
      t.datetime :created_at, null: false
      t.index %i[page_revision_id path], unique: true
      t.check_constraint "length(sha256) = 64", name: "page_files_sha256_length"
    end

    create_table :page_validations do |t|
      t.references :page_revision, null: false, foreign_key: true
      t.string :kit_version, null: false
      t.string :status, null: false
      t.string :harness_version, null: false
      t.string :chrome_version
      t.integer :attempt
      t.text :result_json, null: false
      t.text :shots_json, null: false
      t.datetime :created_at, null: false
      t.index %i[page_revision_id id]
      t.check_constraint "status IN ('passed','failed','error')", name: "page_validations_status"
    end

    create_table :page_reviews do |t|
      t.references :page_revision, null: false, foreign_key: true
      t.references :agent_session, null: false, foreign_key: true
      t.text :checklist_json, null: false
      t.text :findings_json, null: false
      t.string :brief_sha256
      t.datetime :created_at, null: false
      t.index %i[page_revision_id agent_session_id], unique: true
    end

    reversible do |dir|
      dir.up { %i[pages page_revisions page_files page_validations page_reviews].each { |t| Banco::AppendOnly.install(connection, t) } }
    end
  end
end
