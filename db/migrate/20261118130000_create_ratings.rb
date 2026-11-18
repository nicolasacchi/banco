# D-365: what the student thinks of an exercise or a lesson, a rating of 1 to 5 stars and a comment, both optional (one of the two at least).
# One append-only row per rating: a later rating of the same target by the same student is a new row and the current one is the latest
# (Rating.current). The target is named by its key AND by the revision the student was shown (item key + item revision of the served instance, or
# lesson key + lesson revision); an exercise also names the practice serve it was rated from. The teacher only reads it: no reply, no thread, no
# decision, nothing the engine, a gate or a grade reads. `trial` marks a trial student's row; the preview student and a guest never write one.
class CreateRatings < ActiveRecord::Migration[8.1]
  def change
    create_table :ratings do |t|
      t.references :student, null: false, foreign_key: true
      t.string :client_rating_id, null: false
      t.boolean :trial, null: false, default: false
      t.string :target_kind, null: false
      t.string :target_key, null: false
      t.references :subject, null: false, foreign_key: true
      t.references :topic_revision, null: false, foreign_key: true
      t.references :item_revision, foreign_key: true
      t.references :lesson_revision, foreign_key: true
      t.references :practice_serve, foreign_key: true
      t.integer :stars
      t.text :text_it
      t.string :language, null: false
      t.datetime :created_at, null: false
      t.index :client_rating_id, unique: true
      t.index %i[student_id target_kind target_key id], name: "index_ratings_on_student_and_target"
      t.index %i[target_kind target_key], name: "index_ratings_on_target"
      t.check_constraint "target_kind IN ('item','lesson')", name: "ratings_target_kind"
      t.check_constraint "stars IS NULL OR stars BETWEEN 1 AND 5", name: "ratings_stars"
      t.check_constraint "text_it IS NULL OR length(text_it) BETWEEN 1 AND 2000", name: "ratings_text_length"
      t.check_constraint "stars IS NOT NULL OR text_it IS NOT NULL", name: "ratings_something_said"
      t.check_constraint "language IN ('it','en')", name: "ratings_language"
      t.check_constraint "(target_kind = 'item') = (item_revision_id IS NOT NULL)", name: "ratings_item_revision"
      t.check_constraint "(target_kind = 'lesson') = (lesson_revision_id IS NOT NULL)", name: "ratings_lesson_revision"
      t.check_constraint "(target_kind = 'item') = (practice_serve_id IS NOT NULL)", name: "ratings_serve"
    end

    reversible do |dir|
      dir.up { Banco::AppendOnly.install(connection, :ratings) }
    end
  end
end
