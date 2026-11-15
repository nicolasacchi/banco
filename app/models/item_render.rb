# One event of the shots of an item revision (D-336): append-only. `queued` is a request that enqueued the job, `passed` and `failed` are the verdicts of
# a render (failed: findings such as overflow, an aid for the reviewer; never a gate), `error` is Chrome that could not be reached. The latest row is
# what the API says. Rows are made by Items::ShotRequest (queued) and Validation::ItemRenderCheck (the others).
class ItemRender < ApplicationRecord
  belongs_to :item_revision

  VERDICTS = %w[passed failed].freeze

  def result = JSON.parse(result_json)
  def shots = JSON.parse(shots_json)
  def errors_list = Array(result["errors"])
  def verdict? = VERDICTS.include?(status)

  def self.latest_for(revision) = where(item_revision_id: revision.id).order(:id).last

  # The latest verdict row (passed or failed), or nil.
  def self.verdict_for(revision) = where(item_revision_id: revision.id, status: VERDICTS).order(:id).last
end
