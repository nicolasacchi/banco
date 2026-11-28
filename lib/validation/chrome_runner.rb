# frozen_string_literal: true

require "ferrum"
require "resolv"

module Validation
  # The one door to Chrome (A-02). Agent code runs only in a browser; this is the
  # browser. Every use (validation, dry run, preview, health) goes through
  # with_lock, which takes one of SLOTS flocks (tmp/chrome.lock, tmp/chrome.lock.1)
  # shared by every process of the host, so at most SLOTS runs drive Chrome at a
  # time (two since D-402: with twelve authors a lesson render waited twenty minutes
  # behind the one before it; three since D-408, the third for the item shots, which have a
  # queue lane of their own and so never wait behind the lesson renders). Each run has its own browser context; what two runs
  # must not share is handled here: a local Chrome is launched for each slot, and the
  # reaper (below) works only when no other slot is in use, so it never disposes the
  # context of a run that is drawing. The queue's two lanes that drive Chrome, `chrome` and `chrome_shots` (config/queue.yml),
  # have as many threads between them as there are slots.
  #
  # Production: the banco-chrome sidecar (chromedp/headless-shell on the internal
  # network). BANCO_CHROME_HOST is a name; it is resolved to an IP right before
  # Ferrum connects, because Chrome refuses a Host header that is not an IP
  # (spike). Each run gets its own browser context, disposed in ensure. Contexts
  # that a crashed run left behind (Browser#quit does not dispose them on a remote
  # Chrome) are disposed by the reaper at the start of the next run: only those
  # this process does not own.
  #
  # Test, development and CI: a local Chrome (BROWSER_PATH) launched by Ferrum
  # with ignore_default_browser_options and curated flags (never
  # disable-web-security), kept for the life of the process.
  class ChromeRunner
    class Error < StandardError; end
    # Another run holds the lock (a dry run answers 409 E-CHROME-BUSY).
    class Busy < Error; end
    # Chrome cannot be reached or launched, or it died: the validation is status error.
    class Unavailable < Error; end
    # A call into the page did not answer in time.
    class Timeout < Error; end

    LOCK_PATH = -> { ENV["BANCO_CHROME_LOCK"].presence || Rails.root.join("tmp/chrome.lock").to_s }
    # How many runs may drive Chrome at once, and so how many threads the Chrome lanes have between them (test/validation/chrome_runner_test.rb says they agree).
    SLOTS = 3

    FLAGS = {
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
      "remote-allow-origins" => "*",
      # A local Chrome resolves nothing but the loopback harness listener; the pages validation mount is the same listener under
      # the name banco-pages-internal (D-290), which the sidecar resolves on banco-internal.
      "host-resolver-rules" => "MAP banco-pages-internal 127.0.0.1, MAP * ~NOTFOUND, EXCLUDE 127.0.0.1"
    }.freeze

    CHROME_CANDIDATES = %w[google-chrome chromium chromium-browser chrome-headless-shell].freeze

    class << self
      # The lock file of a slot: the shared one for slot 0, the same name and the slot's number for the others.
      def slot_path(slot) = slot.zero? ? LOCK_PATH.call : "#{LOCK_PATH.call}.#{slot}"

      # Runs the block holding one slot of the shared lock (yielding its number). wait: seconds to wait for a free slot;
      # try: true does not wait and raises Busy.
      def with_lock(wait: 900, try: false)
        FileUtils.mkdir_p(File.dirname(LOCK_PATH.call))
        files = Array.new(SLOTS) { |slot| File.open(slot_path(slot), File::RDWR | File::CREAT, 0o600) }
        slot = lock_any(files, wait: wait, try: try)
        raise Busy, "Chrome is busy" unless slot

        begin
          yield slot
        ensure
          files[slot].flock(File::LOCK_UN) unless files[slot].closed?
        end
      ensure
        files&.each { |file| file.close unless file.closed? }
      end

      # Under a slot: connects, reaps orphan contexts, yields a Session, and
      # disposes whatever the session still owns. Chrome trouble is Unavailable.
      def session(wait: 900, try: false)
        with_lock(wait: wait, try: try) do |slot|
          session = Session.new(connect(slot))
          begin
            reap_when_alone(session, slot)
            yield session
          rescue Ferrum::TimeoutError, Ferrum::ScriptTimeoutError, Ferrum::PendingConnectionsError => e
            raise Timeout, e.message
          rescue Ferrum::JavaScriptError => e
            raise Timeout, e.message if e.message.to_s.include?("timed out promise")

            raise Unavailable, "#{e.class}: #{e.message}"
          rescue Ferrum::Error, Errno::ECONNREFUSED, Errno::ECONNRESET, IOError => e
            raise Unavailable, "#{e.class}: #{e.message}"
          ensure
            session.dispose_all
            session.release
          end
        end
      end

      # A Chrome of this host, for `banco health`: waits at most 30 s for the lock.
      def available?(wait: 30)
        session(wait: wait) { |s| s.version }
        true
      rescue Busy
        :busy
      rescue Error
        false
      end

      private

      # The number of the first slot this call can take, or nil (after the wait; at once with try).
      def lock_any(files, wait:, try:)
        deadline = Process.clock_gettime(Process::CLOCK_MONOTONIC) + wait
        loop do
          slot = files.index { |file| file.flock(File::LOCK_EX | File::LOCK_NB) }
          return slot if slot
          return nil if try || Process.clock_gettime(Process::CLOCK_MONOTONIC) >= deadline

          sleep 0.2
        end
      end

      # The reaper disposes every context this session does not own, so it runs only when no other slot is in use (it holds them all while it works, so
      # no other run starts in the meantime). A context a dead run left behind waits for the next quiet moment.
      def reap_when_alone(session, slot)
        others = (0...SLOTS).to_a - [ slot ]
        files = others.map { |other| File.open(slot_path(other), File::RDWR | File::CREAT, 0o600) }
        session.reap if files.all? { |file| file.flock(File::LOCK_EX | File::LOCK_NB) }
      ensure
        files&.each { |file| file.close unless file.closed? }
      end

      def connect(slot)
        host = ENV["BANCO_CHROME_HOST"].presence
        host ? connect_remote(host) : local_browser(slot)
      rescue Resolv::ResolvError, SocketError => e
        raise Unavailable, "cannot resolve #{ENV['BANCO_CHROME_HOST']}: #{e.message}"
      rescue Ferrum::Error, Errno::ECONNREFUSED, NoMethodError => e
        raise Unavailable, "cannot reach Chrome: #{e.class}: #{e.message}"
      end

      def connect_remote(host)
        ip = Resolv.getaddress(host)
        Ferrum::Browser.new(url: "http://#{ip}:#{ENV.fetch('BANCO_CHROME_PORT', '9222')}", timeout: 30)
      end

      # A local Chrome for each slot, kept for the life of the process (a fork starts again): two runs never share a browser.
      def local_browser(slot)
        if @local_pid != Process.pid || @locals.nil?
          @locals = {}
          @local_pid = Process.pid
        end
        @locals[slot] = nil unless local_alive?(@locals[slot])
        @locals[slot] ||= begin
          path = chrome_path or raise Unavailable, "no Chrome to launch: set BROWSER_PATH"
          options = FLAGS.dup
          options["no-sandbox"] = nil if ENV["BANCO_CHROME_NO_SANDBOX"] == "1"
          pid = Process.pid
          browser = Ferrum::Browser.new(browser_path: path, headless: true, ignore_default_browser_options: true,
                                        browser_options: options, process_timeout: 90, timeout: 30)
          at_exit { browser.quit if pid == Process.pid }
          browser
        end
      end

      def local_alive?(browser)
        browser.nil? || (browser.version && true)
      rescue StandardError
        false
      end

      def chrome_path
        configured = ENV["BROWSER_PATH"].presence
        return configured if configured && File.executable?(configured)

        CHROME_CANDIDATES.filter_map { |name| `command -v #{name} 2>/dev/null`.strip.presence }.first
      end
    end

    # One run's view of Chrome: contexts it created, and the reaper.
    class Session
      attr_reader :browser

      def initialize(browser)
        @browser = browser
        @owned = []
      end

      def version = browser.version.product

      # Disposes the contexts of runs that died (not ours). The lock is held, so
      # nobody else owns a live one. Asks Chrome which contexts exist (a context
      # with no page is not known to Ferrum) and disposes each one on its own: one
      # that cannot be disposed does not stop the others.
      def reap
        ids = browser.client.command("Target.getBrowserContexts")["browserContextIds"]
        (ids - @owned).each { |id| dispose_by_id(id) }
      rescue Ferrum::Error
        nil
      end

      # A fresh context (an incognito profile) for one page run, disposed after.
      def context
        ctx = open_context
        yield ctx
      ensure
        close_context(ctx)
      end

      def open_context
        ctx = browser.contexts.create
        @owned << ctx.id
        ctx
      end

      def close_context(ctx)
        return unless ctx

        ctx.dispose
      rescue StandardError
        nil
      ensure
        @owned.delete(ctx&.id)
      end

      def dispose_all
        @owned.dup.each { |id| dispose_by_id(id) }
        @owned.clear
      end

      def dispose_by_id(id)
        known = browser.contexts[id]
        known ? known.dispose : browser.client.command("Target.disposeBrowserContext", browserContextId: id)
      rescue Ferrum::Error
        nil
      end

      # A remote Chrome keeps running: only our connection goes away.
      def release
        browser.quit if ENV["BANCO_CHROME_HOST"].present?
      rescue StandardError
        nil
      end
    end
  end
end
