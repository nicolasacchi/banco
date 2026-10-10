module Validation
  # Renders one stored lesson/2 revision in the server's Chrome and appends what it found as a lesson_renders row
  # (D-249). Outside any transaction while Chrome works; one insert after. Infrastructure trouble is raised, and the
  # job records it as an `error` row (never a pass) and retries.
  class LessonRenderCheck
    # The wait for the shared Chrome lock never depends on the revision budget (a budget of 0 in a test must not mean "no wait").
    LOCK_WAIT_SECONDS = 300

    def initialize(revision, attempt: 1)
      @revision = revision
      @attempt = attempt
    end

    def call
      token = Harness.issue("lrev", @revision.id)
      result = ChromeRunner.session(wait: [ Rules.get(:lesson2, :render, :budget_seconds) * 10, LOCK_WAIT_SECONDS ].max) do |session|
        LessonRenderRunner.new(session, body: @revision.body, token: token).call
      end
      append(status: result.status, chrome_version: result.chrome_version, shots: result.shots,
             result: { "errors" => result.errors, "cards" => result.cards, "viewports" => result.viewports, "elapsed_seconds" => result.elapsed,
                       "exceptions" => result.exceptions })
    end

    def record_error(error)
      append(status: "error", chrome_version: nil, shots: [], result: { "errors" => [], "message" => "#{error.class}: #{error.message}".first(300) })
    end

    private

    def append(status:, chrome_version:, shots:, result:)
      LessonRender.create!(lesson_revision: @revision, status: status, rules_version: Rules.version.to_s, harness_version: Harness.lesson_version,
                           chrome_version: chrome_version, attempt: @attempt, result_json: JSON.generate(result), shots_json: JSON.generate(shots))
    end
  end
end
