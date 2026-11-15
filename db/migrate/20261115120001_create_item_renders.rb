# D-336: the shots of an item revision as the student sees it on a phone, drawn on demand in the server's Chrome. One append-only row per event
# of a request: `queued` (the request, one per request that enqueued the job), then the job's `passed` or `failed` (every instance drawn; `failed`
# means findings such as overflow, an aid for the reviewer and never a gate) or `error` (Chrome could not be reached; never a pass). shots_json lists
# the screenshots stored by content (storage/lesson_shots/<sha256>.webp, the lesson render check's store); the files may be purged later, the rows stay.
class CreateItemRenders < ActiveRecord::Migration[8.1]
  def change
    create_table :item_renders do |t|
      t.references :item_revision, null: false, foreign_key: true
      t.string :status, null: false
      t.string :rules_version
      t.string :harness_version, null: false
      t.string :chrome_version
      t.integer :attempt
      t.text :result_json, null: false
      t.text :shots_json, null: false
      t.datetime :created_at, null: false
      t.index %i[item_revision_id id]
      t.check_constraint "status IN ('queued','passed','failed','error')", name: "item_renders_status"
    end

    reversible do |dir|
      dir.up { Banco::AppendOnly.install(connection, :item_renders) }
    end
  end
end
