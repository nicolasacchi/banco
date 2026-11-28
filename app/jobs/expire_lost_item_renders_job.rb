# The item shot requests that no job answers (D-408): a `queued` row, the latest of its revision, older than item_render.queued_stale_minutes, with no job left in
# Solid Queue, is answered with an `error` row (Items::ShotRequest.expire_lost), so that the status of the revision says it and `banco item shots --wait` asks again
# instead of waiting for a job that does not exist. Recurring (config/recurring.yml); one query for the jobs, one insert for each lost request.
class ExpireLostItemRendersJob < ApplicationJob
  queue_as :default

  def perform = Items::ShotRequest.expire_lost
end
