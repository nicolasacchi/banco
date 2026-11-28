# D-407: free writing. The student writes a text of his own on a topic that pins a writing task (an item of kind short_answer with a word range) and
# sends it; the teacher corrects it with a decision of the kind `correct_writing` (the person's words, never the API's, firm rule 1). One append-only
# row per text sent: a new version is a new row. The text is the student's own words and is never indexed by search. `client_writing_id` makes the send
# idempotent; the item revision and the topic revision are what he was shown, derived by the server and never taken from the browser.
class CreateWritingSubmissions < ActiveRecord::Migration[8.1]
  def change
    create_table :writing_submissions do |t|
      t.references :student, null: false, foreign_key: true
      t.references :topic_revision, null: false, foreign_key: true
      t.references :item_revision, null: false, foreign_key: true
      t.string :client_writing_id, null: false
      t.text :text, null: false
      t.integer :word_count, null: false
      t.datetime :created_at, null: false
      t.index :client_writing_id, unique: true
      t.index %i[student_id item_revision_id id], name: "index_writing_submissions_on_student_and_item"
      t.check_constraint "length(text) BETWEEN 1 AND 4000", name: "writing_submissions_text_length"
      t.check_constraint "word_count >= 1", name: "writing_submissions_word_count"
    end

    reversible do |dir|
      dir.up { Banco::AppendOnly.install(connection, :writing_submissions) }
    end
  end
end
