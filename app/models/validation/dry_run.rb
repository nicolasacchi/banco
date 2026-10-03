module Validation
  # `banco work submit --dry-run`: the same phases as the job, in the request, and
  # nothing kept: no item, no revision, no validation row, no instance, no queued job.
  # The files are staged in memory for the harness (the page of the run reads them by
  # a token that names the stage) and dropped after. Chrome is taken with a try-lock:
  # when it is busy ChromeRunner::Busy is raised and the API answers 409 E-CHROME-BUSY.
  module DryRun
    module_function

    def call(subject, files)
      stage = Harness::Staging.put(files)
      ItemRunner.new(files: files, context: CourseContext.for(subject), harness_token: Harness.issue("stage", stage),
                     chrome: { try: true }).call
    ensure
      Harness::Staging.drop(stage) if stage
    end
  end
end
