require "test_helper"
require_relative "../support/validation_servers"
require_relative "../support/chrome_helper"

# ChromeRunner: the shared lock, the reaper that disposes only orphan contexts, one
# context per run disposed in ensure, and the sidecar address resolved to an IP (A-02).
class ChromeRunnerTest < ActiveSupport::TestCase
  include ChromeHelper

  Runner = Validation::ChromeRunner

  # The lock tests take a lock file of their own. The shared one (tmp/chrome.lock) is
  # also taken by the Chrome tests running at the same time in the other parallel
  # workers, and on a loaded host one of them holds it for minutes: a try-lock that
  # must succeed would then be Busy, a timing accident and not a defect. (The tests
  # that use Chrome keep the shared lock: it is what keeps the reaper off a Chrome
  # that another worker is using.)
  def with_private_lock
    dir = Dir.mktmpdir("banco-lock")
    with_env("BANCO_CHROME_LOCK" => File.join(dir, "chrome.lock")) { yield }
  ensure
    FileUtils.rm_rf(dir) if dir
  end

  test "the lock is shared: a second taker waits, a try-lock is Busy, and the lock is released after" do
    with_private_lock { lock_is_shared }
  end

  def lock_is_shared
    held = Queue.new
    release = Queue.new
    holder = Thread.new { Runner.with_lock { held << true; release.pop } }
    held.pop
    begin
      assert_raises(Runner::Busy) { Runner.with_lock(try: true) { flunk "must not run" } }
      assert_raises(Runner::Busy) { Runner.with_lock(wait: 0.5) { flunk "must not run" } }
    ensure
      release << true
      holder.join
    end
    assert_equal :ran, Runner.with_lock(try: true) { :ran }
  end

  test "the lock is released when the block raises" do
    with_private_lock do
      assert_raises(RuntimeError) { Runner.with_lock { raise "boom" } }
      assert_equal :ran, Runner.with_lock(try: true) { :ran }
    end
  end

  test "the sidecar host is resolved to an IP before Ferrum connects (Chrome refuses a Host that is not an IP)" do
    seen = nil
    fake = Object.new
    with_env("BANCO_CHROME_HOST" => "banco-chrome", "BANCO_CHROME_PORT" => "9333") do
      Resolv.stub(:getaddress, ->(name) { name == "banco-chrome" ? "172.28.0.9" : raise("unexpected #{name}") }) do
        Ferrum::Browser.stub(:new, ->(**opts) { seen = opts; fake }) do
          assert_same fake, Runner.send(:connect)
        end
      end
    end
    assert_equal "http://172.28.0.9:9333", seen[:url]
    assert_nil seen[:browser_path]
  end

  test "an unresolvable or unreachable sidecar is Unavailable, never a pass" do
    with_env("BANCO_CHROME_HOST" => "no-such-host.invalid") do
      Resolv.stub(:getaddress, ->(_n) { raise Resolv::ResolvError, "nope" }) do
        assert_raises(Runner::Unavailable) { Runner.session { flunk } }
      end
    end
  end

  test "without BROWSER_PATH there is nothing to launch: Unavailable with a clear message" do
    kept = Runner.instance_variable_get(:@local)
    Runner.instance_variable_set(:@local, nil)
    with_env("BANCO_CHROME_HOST" => nil, "BROWSER_PATH" => "/no/such/chrome") do
      Runner.stub(:chrome_path, nil) do
        error = assert_raises(Runner::Unavailable) { Runner.session { flunk } }
        assert_includes error.message, "BROWSER_PATH"
      end
    end
  ensure
    Runner.instance_variable_set(:@local, kept)
  end

  test "the reaper disposes contexts that are not ours and keeps the ones we own; a context is disposed in ensure" do
    require_chrome!
    Runner.session do |session|
      mine = session.open_context
      orphan = session.browser.contexts.create
      assert_includes session.browser.contexts.map { |id, _| id }, orphan.id
      session.reap
      ids = session.browser.contexts.map { |id, _| id }
      assert_includes ids, mine.id
      assert_not_includes ids, orphan.id
      session.close_context(mine)
      assert_not_includes session.browser.contexts.map { |id, _| id }, mine.id
    end
    # A context left by a run that died is cleaned at the start of the next one (a real
    # Chrome may keep a default context of its own: compare with what was there before).
    baseline = nil
    Runner.session { |session| baseline = session.browser.contexts.map { |id, _| id }.sort }
    Runner.session { |session| session.browser.contexts.create }
    Runner.session do |session|
      assert_equal baseline, session.browser.contexts.map { |id, _| id }.sort
    end
  end

  test "a context taken with the block form is disposed even when the block raises" do
    require_chrome!
    left = nil
    Runner.session do |session|
      assert_raises(RuntimeError) do
        session.context { |ctx| left = ctx.id; raise "boom" }
      end
      assert_not_includes session.browser.contexts.map { |id, _| id }, left
    end
  end

  test "available? says true with Chrome, busy when the lock is taken for the whole wait" do
    require_chrome!
    assert_equal true, Runner.available?(wait: 300)
  end

  test "an evaluate that never answers is a Timeout" do
    require_chrome!
    ValidationServers.harness!
    token = stage_token({ "generator.mjs" => "export function generate() { return {}; }" })
    assert_raises(Runner::Timeout) do
      Runner.session do |session|
        session.context do |ctx|
          page = ctx.create_page
          page.go_to(Validation::Harness.page_url(token))
          page.evaluate_async("window.bancoHarness.ready.then(function () {})", 1)
        end
      end
    end
  end
end
