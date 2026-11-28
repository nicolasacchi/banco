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

  test "the lock has SLOTS places and is shared: a taker beyond them waits, a try-lock is Busy, and a place is free again after" do
    with_private_lock { lock_is_shared }
  end

  # Holds every slot but one with threads, then the last one: the next taker waits.
  def hold_slots(count)
    held = Queue.new
    release = Queue.new
    holders = Array.new(count) { Thread.new { Runner.with_lock { held << true; release.pop } } }
    count.times { held.pop }
    [ release, holders ]
  end

  def lock_is_shared
    release, holders = hold_slots(Runner::SLOTS - 1)
    assert_equal :ran, Runner.with_lock(try: true) { :ran }, "a place is left: a try-lock takes it"
    last_release, last = hold_slots(1)
    begin
      assert_raises(Runner::Busy) { Runner.with_lock(try: true) { flunk "must not run" } }
      assert_raises(Runner::Busy) { Runner.with_lock(wait: 0.5) { flunk "must not run" } }
    ensure
      last_release << true
      last.each(&:join)
    end
    assert_equal :ran, Runner.with_lock(try: true) { :ran }
  ensure
    holders&.each { release << true }
    holders&.each(&:join)
  end

  test "two takers hold different slots at once" do
    with_private_lock do
      slots = Queue.new
      release = Queue.new
      holders = Array.new(Runner::SLOTS) { Thread.new { Runner.with_lock { |slot| slots << slot; release.pop } } }
      taken = Array.new(Runner::SLOTS) { slots.pop }
      assert_equal (0...Runner::SLOTS).to_a, taken.sort
      Runner::SLOTS.times { release << true }
      holders.each(&:join)
    end
  end

  test "the Chrome lanes (`chrome` and `chrome_shots`) have as many threads between them as Chrome has slots, and no more (a thread past the slots would only wait on the lock)" do
    workers = YAML.safe_load(ERB.new(Rails.root.join("config/queue.yml").read).result, aliases: true).dig("production", "workers")
    lanes = workers.select { |w| (Array(w["queues"]) & %w[chrome chrome_shots]).any? }
    assert_equal 2, lanes.size
    assert_equal Runner::SLOTS, lanes.sum { |w| w["threads"] }
    assert(lanes.all? { |w| w["processes"] == 1 }, "the slots are shared by every process, but the browsers of a slot live in one")
  end

  test "the reaper runs only when no other slot is in use: it never disposes the context of a run that is drawing" do
    with_private_lock do
      reaped = []
      fake = Object.new
      fake.define_singleton_method(:reap) { reaped << :reap }
      Runner.with_lock do |slot|
        Runner.send(:reap_when_alone, fake, slot)
        assert_equal [ :reap ], reaped, "alone: reaps"
        release, holders = hold_slots(Runner::SLOTS - 1)
        begin
          Runner.send(:reap_when_alone, fake, slot)
          assert_equal [ :reap ], reaped, "another run in use: no second reap"
        ensure
          (Runner::SLOTS - 1).times { release << true }
          holders.each(&:join)
        end
      end
    end
  end

  test "two sessions run at once, each in a Chrome and a context of its own, and neither clobbers the other's page" do
    require_chrome!
    with_private_lock do
      both_in = Concurrent::CyclicBarrier.new(2)
      run = lambda do |name|
        Runner.session(wait: 60) do |session|
          session.context do |ctx|
            page = ctx.create_page
            page.go_to("about:blank")
            page.evaluate("document.title = #{name.to_json}")
            both_in.wait(60) || raise("the other session never came in: the two runs were serialized")
            [ name, page.evaluate("document.title"), session.browser.object_id ]
          end
        end
      end
      results = [ "first", "second" ].map { |n| Thread.new { run.call(n) } }.map(&:value)
      assert_equal [ %w[first first], %w[second second] ], results.map { |r| r.first(2) }
      assert_equal 2, results.map(&:last).uniq.size, "a Chrome for each slot"
    end
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
          assert_same fake, Runner.send(:connect, 0)
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
    kept = [ Runner.instance_variable_get(:@locals), Runner.instance_variable_get(:@local_pid) ]
    Runner.instance_variable_set(:@locals, {})
    Runner.instance_variable_set(:@local_pid, Process.pid)
    with_env("BANCO_CHROME_HOST" => nil, "BROWSER_PATH" => "/no/such/chrome") do
      Runner.stub(:chrome_path, nil) do
        error = assert_raises(Runner::Unavailable) { Runner.session { flunk } }
        assert_includes error.message, "BROWSER_PATH"
      end
    end
  ensure
    Runner.instance_variable_set(:@locals, kept[0])
    Runner.instance_variable_set(:@local_pid, kept[1])
  end

  test "the reaper disposes contexts that are not ours and keeps the ones we own; a context is disposed in ensure (our own are never disposed by it)" do
    require_chrome!
    # a lock of its own: the reaper runs only when no other run holds the other slot, and the shared lock is held by the parallel workers of the gate
    # (each process has a Chrome of its own, so nothing here can reach another worker's contexts)
    with_private_lock do
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
