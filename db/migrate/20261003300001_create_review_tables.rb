# M6: who did what to an item (A-04), the expert review and the blind solve with
# their findings (A-05), and the grade proposals of the evening loop (B-06).
#
# Everything is append-only (firm rule 4). A finding is never edited: the teacher's
# disposition of it is a decision row (kind dispose_finding), and a grade proposal
# counts only after a decision row confirms it (kind confirm_grade). Both kinds are
# written by the teacher's pages (M9); nothing on the API listener creates them.
class CreateReviewTables < ActiveRecord::Migration[8.1]
  TABLES = %i[item_reviews blind_solves review_findings grade_proposals].freeze

  def change
    # The declared agent and model of a session; the model's family comes from
    # config/banco/providers.yml.
    add_column :agent_sessions, :agent, :string
    add_column :agent_sessions, :model, :string

    create_table :item_reviews do |t|
      t.references :item_revision, null: false, foreign_key: true
      t.references :agent_session, null: false, foreign_key: true
      t.text :checklist_json, null: false
      t.string :brief_sha256
      t.datetime :created_at, null: false
    end

    # results_json: one entry per instance {instance, verdict (agree|disagree|dont_know), ...}.
    create_table :blind_solves do |t|
      t.references :item_revision, null: false, foreign_key: true
      t.references :agent_session, null: false, foreign_key: true
      t.text :answers_json, null: false
      t.text :results_json, null: false
      t.string :brief_sha256
      t.datetime :created_at, null: false
    end

    # source review: item_review_id is set; source blind_solve: blind_solve_id is set,
    # code is E-BLIND-SOLVE-MISMATCH.
    create_table :review_findings do |t|
      t.references :item_revision, null: false, foreign_key: true
      t.string :source, null: false
      t.references :item_review, foreign_key: true
      t.references :blind_solve, foreign_key: true
      t.string :severity, null: false
      t.string :code
      t.integer :instance
      t.string :field, null: false
      t.text :quote, null: false
      t.text :problem_it, null: false
      t.text :fix_it, null: false
      t.datetime :created_at, null: false
      t.check_constraint "source IN ('review','blind_solve')", name: "review_findings_source"
      t.check_constraint "severity IN ('blocker','major','minor')", name: "review_findings_severity"
    end

    # points_json: [{point_id, score, quote, rationale_it}] with the rubric weights
    # as they were; total and max_total are computed by the server.
    create_table :grade_proposals do |t|
      t.references :attempt, null: false, foreign_key: true
      t.references :agent_session, null: false, foreign_key: true
      t.text :points_json, null: false
      t.text :missing_it
      t.integer :total, null: false
      t.integer :max_total, null: false
      t.float :threshold, null: false
      t.boolean :meets_threshold, null: false
      t.string :brief_sha256
      t.datetime :created_at, null: false
    end

    reversible do |dir|
      dir.up { TABLES.each { |table| Banco::AppendOnly.install(connection, table) } }
    end
  end
end
