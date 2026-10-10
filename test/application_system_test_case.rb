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

class ApplicationSystemTestCase < ActiveSupport::TestCase
  include Capybara::DSL
  include Capybara::Minitest::Assertions

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
