# Comments anywhere (C1, D-304): what the student says about a place in the app, and what happens to it. Two
# append-only tables like every primary table: `comments` (one row per comment, written by the student's page) and
# `comment_events` (reply, read, resolved, reopened, sent_back by the teacher or the console; reply_seen by the
# student). The state of a comment is derived from its events, never stored. No model in the path and no API route
# reads either table (firm rule 1; the agents never read a minor's words).
class CreateComments < ActiveRecord::Migration[8.1]
  def change
    create_table :comments do |t|
      t.references :student, null: false, foreign_key: true
      t.string :client_comment_id, null: false
      t.boolean :trial, null: false, default: false
      t.string :reason, null: false
      t.text :text_it
      t.string :page_path, null: false
      t.string :page_kind, null: false
      t.string :anchor
      t.text :selected_text
      t.references :subject, foreign_key: true
      t.references :topic_revision, foreign_key: true
      t.references :lesson_revision, foreign_key: true
      t.integer :card
      t.references :practice_serve, foreign_key: true
      t.references :diagnosis_run, foreign_key: true
      t.integer :served_event_id
      t.references :item_instance, foreign_key: true
      t.references :item_revision, foreign_key: true
      t.references :blueprint_revision, foreign_key: true
      t.integer :viewport_width
      t.integer :viewport_height
      t.string :theme
      t.string :text_size
      t.datetime :created_at, null: false
      t.index :client_comment_id, unique: true
      t.index %i[student_id id]
      t.check_constraint "reason IN ('not_understood','error','not_working','like','other')", name: "comments_reason"
      t.check_constraint "page_kind IN ('today','subjects','subject','topic','lesson','practice','diagnosis','warmup','sitting','results','settings','search','comments')", name: "comments_page_kind"
      t.check_constraint "text_it IS NULL OR length(text_it) BETWEEN 1 AND 500", name: "comments_text_length"
      t.check_constraint "selected_text IS NULL OR length(selected_text) BETWEEN 1 AND 300", name: "comments_selected_length"
      t.check_constraint "anchor IS NULL OR length(anchor) BETWEEN 1 AND 200", name: "comments_anchor_length"
    end

    create_table :comment_events do |t|
      t.references :comment, null: false, foreign_key: true
      t.string :kind, null: false
      t.string :origin, null: false
      t.string :actor, null: false
      t.text :text_it
      t.string :remote_addr, null: false, default: ""
      t.string :request_id
      t.text :payload_json, null: false, default: "{}"
      t.datetime :created_at, null: false
      t.index %i[comment_id id]
      t.index :request_id, unique: true, where: "request_id IS NOT NULL"
      t.check_constraint "kind IN ('reply','read','resolved','reopened','sent_back','reply_seen')", name: "comment_events_kind"
      t.check_constraint "origin IN ('web','console','student')", name: "comment_events_origin"
      t.check_constraint "kind <> 'reply' OR (text_it IS NOT NULL AND length(text_it) BETWEEN 1 AND 2000)", name: "comment_events_reply_text"
      t.check_constraint "(kind = 'reply_seen') = (origin = 'student')", name: "comment_events_seen_by_student"
    end

    reversible do |dir|
      dir.up do
        Banco::AppendOnly.install(connection, :comments)
        Banco::AppendOnly.install(connection, :comment_events)
      end
    end
  end
end
