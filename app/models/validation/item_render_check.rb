module Validation
  # Draws the instances of one stored item revision in the server's Chrome and appends what it found as an item_renders row (D-336): the shots (by
  # content, in LessonShots' store), the findings per instance, the timings. Outside any transaction while Chrome works; one insert after. Infrastructure
  # trouble is raised, and the job records it as an `error` row (never a pass) and retries. The findings are an aid; no gate reads them.
  class ItemRenderCheck
    # The wait for the shared Chrome lock never depends on the revision budget.
    LOCK_WAIT_SECONDS = 300

    def initialize(revision, attempt: 1)
      @revision = revision
      @attempt = attempt
    end

    # A render that failed only on its time limits is drawn once more, in the same job, before `failed` is recorded: under load the limit, not the item,
    # was at fault. `render_attempts` in the result says how many times it was drawn.
    def call
      token = Harness.issue("irev", @revision.id)
      result = draw(token)
      renders = 1
      if result.timeout_only?
        Rails.logger.warn("item render of revision #{@revision.id} failed on its time limits only (#{result.elapsed} s); drawing it once more")
        result = draw(token)
        renders = 2
      end
      append(status: result.status, chrome_version: result.chrome_version, shots: result.shots,
             result: { "errors" => result.errors, "instances" => result.instances, "instances_total" => result.total, "viewport" => result.viewport,
                       "elapsed_seconds" => result.elapsed, "timings" => result.timings, "render_attempts" => renders })
    end

    def record_error(error)
      append(status: "error", chrome_version: nil, shots: [], result: { "errors" => [], "message" => "#{error.class}: #{error.message}".first(300) })
    end

    private

    def draw(token)
      budget = Rules.get(:item_render, :budget_seconds)
      ChromeRunner.session(wait: [ budget * 10, LOCK_WAIT_SECONDS ].max) do |session|
        ItemRenderRunner.new(session, revision: @revision, token: token).call
      end
    end

    def append(status:, chrome_version:, shots:, result:)
      ItemRender.create!(item_revision: @revision, status: status, rules_version: Rules.version.to_s, harness_version: Harness.item_version,
                         chrome_version: chrome_version, attempt: @attempt, result_json: JSON.generate(result), shots_json: JSON.generate(shots))
    end
  end
end
