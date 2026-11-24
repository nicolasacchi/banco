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

  # Opens the lesson render host in `page` as Validation::LessonRenderRunner does: a load can end before the host's modules ran (a module request that a busy
  # harness listener answered late or not at all leaves `window.bancoLessonRender` undefined, with no exception), so the page is loaded again, up to `attempts`
  # times, until the host defines it. When it never does, the error says what the page's console and network said, so the cause can be read.
  def open_lesson_host(page, url, attempts: 3, wait: 20)
    seen = []
    page.command("Network.enable")
    page.on("Network.loadingFailed") { |p| seen << "request failed (#{p['errorText']}#{p['blockedReason'] ? ", #{p['blockedReason']}" : ''})" }
    page.on("Network.responseReceived") { |p| seen << "#{p.dig('response', 'status')} #{p.dig('response', 'url')}" if p.dig("response", "status").to_i >= 400 && !p.dig("response", "url").to_s.end_with?("favicon.ico") }
    page.on("Runtime.exceptionThrown") { |p| seen << "exception: #{p.dig('exceptionDetails', 'exception', 'description') || p.dig('exceptionDetails', 'text')}" }
    page.on("Runtime.consoleAPICalled") { |p| seen << "console.#{p['type']}: #{p['args'].to_a.map { |a| a['value'] || a['description'] }.join(' ')}" if %w[error assert].include?(p["type"]) }
    attempts.times do
      page.go_to(url)
      deadline = Process.clock_gettime(Process::CLOCK_MONOTONIC) + wait
      loop do
        return page if page.evaluate("typeof window.bancoLessonRender !== 'undefined'")
        break if Process.clock_gettime(Process::CLOCK_MONOTONIC) >= deadline

        sleep 0.25
      end
    end
    raise "the lesson render host did not define bancoLessonRender in #{attempts} loads of #{url}: #{seen.uniq.first(10).join('; ').presence || 'nothing in the console or the network'}"
  end

  # The harness token for files staged in this process (a dry run's way).
  def stage_token(files)
    id = Validation::Harness::Staging.put(files)
    Validation::Harness.issue("stage", id)
  end
end
