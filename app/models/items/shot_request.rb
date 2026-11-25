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

    # A `queued` row nothing has answered for queued_stale_minutes is a lost job, unless its job is still waiting or running in the queue: with twenty
    # requests ahead of it a job waits longer than that, and a new request must not add a twentieth-and-first (D-402).
    def self.stale?(row, now: Time.current)
      row.status == "queued" && row.created_at < now - Validation::Rules.get(:item_render, :queued_stale_minutes).minutes && !job_pending?(row)
    end

    # How many other render requests wait before this one: the `queued` rows that are the latest of their revision, are not stale and are older than the row (the
    # job takes them in order). Item validations and lesson renders have a higher priority and run first; they are not counted. Cheap: one query, no Solid Queue.
    def self.ahead(row, now: Time.current)
      ItemRender.where(status: "queued").where("item_renders.id < ?", row.id).where("item_renders.created_at >= ?", now - Validation::Rules.get(:item_render, :queued_stale_minutes).minutes)
                .where("NOT EXISTS (SELECT 1 FROM item_renders later WHERE later.item_revision_id = item_renders.item_revision_id AND later.id > item_renders.id)").count
    end

    # Whether the job of this request (RenderItemRevisionJob with the revision and the row as arguments) is in Solid Queue and neither finished nor failed.
    # Without Solid Queue (test, development) nothing is known, and the age alone says.
    def self.job_pending?(row)
      return false unless ActiveJob::Base.queue_adapter_name == "solid_queue"

      SolidQueue::Job.where(class_name: RenderItemRevisionJob.name, finished_at: nil).where.missing(:failed_execution)
                     .where("arguments LIKE ?", "%\"arguments\":[#{row.item_revision_id.to_i},#{row.id.to_i}]%").exists?
    end

    private

    def stale?(row) = self.class.stale?(row, now: @now)
  end
end
