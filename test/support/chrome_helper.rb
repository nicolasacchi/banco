# Tests that drive the server's Chrome (validation, harness) run against a local
# Chrome launched through Validation::ChromeRunner (BROWSER_PATH; the runner's
# Chrome in CI). They skip, with a clear message, when there is none.
module ChromeHelper
  def require_chrome!
    path = ENV["BROWSER_PATH"].to_s
    skip "BROWSER_PATH is not set (no Chrome to drive)" if path.empty?
    skip "BROWSER_PATH #{path} is not executable" unless File.executable?(path)
    ValidationServers.harness!
  end

  # The harness token for files staged in this process (a dry run's way).
  def stage_token(files)
    id = Validation::Harness::Staging.put(files)
    Validation::Harness.issue("stage", id)
  end
end
