module Items
  # A request for the shots of an item revision (D-336, `POST /api/v1/item-revisions/:id/shots`, `banco item shots`): appends a `queued` row and enqueues
  # RenderItemRevisionJob, once. No second job while one is pending (a `queued` row younger than item_render.queued_stale_minutes with nothing after it,
  # forced or not) nor when a render (a verdict) of the current host exists, unless `force`; a verdict of an older host is asked again; a lost job (a `queued` row left too long) and an `error` are asked again freely. The row and
  # the check of the rows before it are one transaction, so two requests at once enqueue one job.
  class ShotRequest
    Result = Struct.new(:enqueued, :row, keyword_init: true)

    def self.call(revision, force: false, now: Time.current) = new(revision, force: force, now: now).call

    def initialize(revision, force:, now:)
      @revision = revision
      @force = force
      @now = now
    end

    def call
      row = nil
      ItemRender.transaction do
        latest = ItemRender.latest_for(@revision)
        return Result.new(enqueued: false, row: latest) unless needed?(latest)

        row = ItemRender.create!(item_revision: @revision, status: "queued", rules_version: Validation::Rules.version.to_s, harness_version: Validation::Harness.item_version,
                                 result_json: JSON.generate("force" => @force), shots_json: "[]")
      end
      RenderItemRevisionJob.perform_later(@revision.id, row.id)
      Result.new(enqueued: true, row: row)
    end

    # Whether a request enqueues a job now: nothing yet, Chrome that could not be reached, a lost job (a fresh queued row is a job pending, forced or
    # not: no second one), a verdict made by an older host, CSS or templates, or a forced request of a revision that has a verdict.
    def needed?(latest)
      return true if latest.nil? || latest.status == "error"
      return stale?(latest) if latest.status == "queued"

      @force || latest.harness_version != Validation::Harness.item_version
    end

    def self.stale?(row, now: Time.current) = row.status == "queued" && row.created_at < now - Validation::Rules.get(:item_render, :queued_stale_minutes).minutes

    private

    def stale?(row) = self.class.stale?(row, now: @now)
  end
end
