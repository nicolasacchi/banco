require "test_helper"
require "capybara/dsl"
require "capybara/minitest"
require "capybara/cuprite"

# Ferrum waits after a click for the page it opens to finish loading, and on Chrome
# 154 (the CI runner's) that wait never ends although the page has loaded, so every
# click that navigates times out. The constant is read when a click is made, so it
# can be set here whenever Ferrum was loaded. Capybara's retrying finders do the
# waiting instead.
Ferrum::Mouse.send(:remove_const, :CLICK_WAIT)
Ferrum::Mouse.const_set(:CLICK_WAIT, 0.0)

# The same wait is made after every navigation (Page#go_to, so every `visit`), and it never ends on the runner's Chrome 154 and 155 either:
# the first, initial main frame stays in the state :canceled and never reaches :stopped_loading, so Ferrum's "all frames idle" never
# holds and each visit waited the whole 30 s command timeout before carrying on (then swallowed, as pending_connection_errors is off).
# That was about 60 to 90 s per test and four hours for the system step (it is 9 minutes with the Playwright shell). The wait is switched
# off here and replaced by the one it meant: the document of the main frame is complete (a probe on the runner showed it is, 0.1 s after
# the call).
Ferrum::Page.send(:remove_const, :GOTO_WAIT)
Ferrum::Page.const_set(:GOTO_WAIT, 0.0)

module VisitWaitsForDocument
  DOCUMENT_WAIT_SECONDS = 30

  def visit(*args)
    result = begin
      super
    rescue Ferrum::StatusError => e
      # An error status with an empty body (a 403 or a 404 of the app) is reported by Chrome as a failed navigation; the tests read the
      # status (page.status_code) and the page, as they did while the wait above timed out before this check was reached.
      raise unless e.message.include?("ERR_HTTP_RESPONSE_CODE_FAILURE")
    end
    wait_for_document
    result
  end

  private

  def wait_for_document
    deadline = Process.clock_gettime(Process::CLOCK_MONOTONIC) + DOCUMENT_WAIT_SECONDS
    loop do
      state = begin
        page.evaluate("document.readyState")
      rescue Ferrum::NoExecutionContextError, Ferrum::NodeNotFoundError, Ferrum::BrowserError
        nil # the new document has no execution context yet
      end
      return if state == "complete" || Process.clock_gettime(Process::CLOCK_MONOTONIC) >= deadline

      sleep 0.02
    end
  end
end
Capybara::Cuprite::Browser.prepend(VisitWaitsForDocument)

# System tests drive a real Chrome through Cuprite. BROWSER_PATH points at the
# Playwright headless shell locally and at the runner's Chrome in CI.
#
# Flags are curated: Ferrum's defaults are ignored because they include
# disable-web-security and disable-dev-shm-usage, which hide real problems.
CHROME_FLAGS = {
  "headless" => nil,
  "disable-gpu" => nil,
  "hide-scrollbars" => nil,
  "mute-audio" => nil,
  "no-first-run" => nil,
  "no-default-browser-check" => nil,
  "disable-background-networking" => nil,
  "disable-extensions" => nil,
  "disable-sync" => nil,
  "disable-breakpad" => nil,
  "force-color-profile" => "srgb",
  "password-store" => "basic",
  "use-mock-keychain" => nil,
  "remote-allow-origins" => "*"
}.freeze

# The server's Capybara Puma binds WEB_PORT, so the listener tag (local port of
# the accepted socket) sees the web listener, like production.
Capybara.server_port = Banco::Listeners.ports.fetch(:web)
Capybara.server_host = "127.0.0.1"
Capybara.server = :puma, { Silent: true }

Capybara.register_driver(:banco_cuprite) do |app|
  options = CHROME_FLAGS.dup
  options["no-sandbox"] = nil if ENV["BANCO_CHROME_NO_SANDBOX"] == "1"
  Capybara::Cuprite::Driver.new(
    app,
    browser_path: ENV["BROWSER_PATH"],
    ignore_default_browser_options: true,
    browser_options: options,
    process_timeout: 60,
    timeout: 30,
    # Real Chrome can keep a speculative connection open (favicon, preconnect);
    # tests assert on responses and content, not on network idleness.
    pending_connection_errors: false,
    window_size: [ 1280, 900 ]
  )
end

# The host is often heavily loaded: pages that fetch their items need patience.
Capybara.default_max_wait_time = 10

# The system tests share one Capybara server on WEB_PORT, so they never run in parallel processes (they would all
# bind the same port). Rails parallelizes a run of more than 50 tests; the system suite has outgrown that.
ActiveSupport::TestCase.parallelize(workers: :number_of_processors, threshold: Float::INFINITY)

# A system test that has not finished in this long is stopped and reported by name: a stuck Chrome is one failed test with its name, not a
# step that sits for hours (the slowest test takes about 35 s on the runner).
class SystemTestHang < Exception # not a StandardError, so that no rescue in a test or a helper swallows it
end

class ApplicationSystemTestCase < ActiveSupport::TestCase
  include Capybara::DSL
  include Capybara::Minitest::Assertions

  TEST_TIMEOUT_SECONDS = Integer(ENV.fetch("BANCO_SYSTEM_TEST_TIMEOUT", "300"))

  def run
    Timeout.timeout(TEST_TIMEOUT_SECONDS, SystemTestHang, "#{self.class}##{name} took more than #{TEST_TIMEOUT_SECONDS} s: the browser or the server did not answer") { super }
  end

  setup do
    skip "BROWSER_PATH is not set (no Chrome to drive)" if ENV["BROWSER_PATH"].to_s.empty?
    skip "BROWSER_PATH #{ENV['BROWSER_PATH']} is not executable" unless File.executable?(ENV["BROWSER_PATH"])
    Capybara.current_driver = :banco_cuprite
    Capybara.app = Rails.application
    # Every test starts with an empty cookie jar. On the CI runner's Chrome the reset between
    # tests did not always empty it: the student-device cookie that one test sets (D-08) then
    # switched off the decision buttons of the tests that came after it.
    page.driver.clear_cookies
    # The browser is shared by every test and many resize it (phone widths): each test starts at the driver's size, so that
    # a narrow window left by another test (and the order the seed picks) never changes the layout under test.
    page.driver.resize(1280, 900)
  end

  teardown do
    page.driver.clear_cookies
    Capybara.reset_sessions!
    Capybara.use_default_driver
  end
end
