module Validation
  # Validates one stored page revision in the server's Chrome and appends what it found as a page_validations row (D-290, SPEC B7).
  # Outside any transaction while Chrome works; one insert after. Infrastructure trouble is raised, and the job records it as an
  # `error` row (never a pass) and retries.
  class PageValidationCheck
    LOCK_WAIT_SECONDS = 600

    def initialize(revision, kit: Pages::Kit.versions.last, attempt: 1)
      @revision = revision
      @kit = kit
      @attempt = attempt
    end

    def call
      result = ChromeRunner.session(wait: LOCK_WAIT_SECONDS) do |session|
        PageRunner.new(session, revision: @revision, kit: @kit).call
      end
      append(status: result.status, chrome_version: result.chrome_version, shots: result.shots,
             result: { "errors" => result.errors, "warnings" => result.warnings, "seeds" => result.seeds, "elapsed_seconds" => result.elapsed, "resources" => result.resources })
    end

    def record_error(error)
      append(status: "error", chrome_version: nil, shots: [], result: { "errors" => [], "message" => "#{error.class}: #{error.message}".first(300) })
    end

    private

    def append(status:, chrome_version:, shots:, result:)
      PageValidation.create!(page_revision: @revision, kit_version: @kit, status: status, harness_version: Harness.page_version, chrome_version: chrome_version,
                             attempt: @attempt, result_json: JSON.generate(result), shots_json: JSON.generate(shots))
    end
  end
end
