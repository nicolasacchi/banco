module Validation
  # `banco work submit --dry-run`: the same phases as the job, in the request, and
  # nothing kept: no item, no revision, no validation row, no instance, no queued job.
  # The files are staged in memory for the harness (the page of the run reads them by
  # a token that names the stage) and dropped after. Chrome is taken with a bounded wait
  # (BANCO_DRY_RUN_CHROME_WAIT seconds, default 25, so a dry run queues behind a short
  # validation): when it is still busy ChromeRunner::Busy is raised and the API answers
  # 409 E-CHROME-BUSY.
  module DryRun
    module_function

    def call(subject, files, verify_inherited: false)
      stage = Harness::Staging.put(files)
      ItemRunner.new(files: files, context: CourseContext.for(subject), harness_token: Harness.issue("stage", stage),
                     chrome: { wait: chrome_wait }, verify_inherited: verify_inherited).call
    ensure
      Harness::Staging.drop(stage) if stage
    end

    def chrome_wait = Float(ENV.fetch("BANCO_DRY_RUN_CHROME_WAIT", 25))
  end
end
