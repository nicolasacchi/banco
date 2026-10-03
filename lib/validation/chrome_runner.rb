# frozen_string_literal: true

require "ferrum"
require "resolv"

module Validation
  # The one door to Chrome (A-02). Agent code runs only in a browser; this is the
  # browser. Every use (validation, dry run, preview, health) goes through
  # with_lock, an flock on tmp/chrome.lock shared by every process of the host, so
  # at most one run drives Chrome at a time.
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
      # A local Chrome resolves nothing but the loopback harness listener.
      "host-resolver-rules" => "MAP * ~NOTFOUND, EXCLUDE 127.0.0.1"
    }.freeze

    CHROME_CANDIDATES = %w[google-chrome chromium chromium-browser chrome-headless-shell].freeze

    class << self
      # Runs the block holding the shared lock. wait: seconds to wait for it;
      # try: true does not wait and raises Busy.
      def with_lock(wait: 900, try: false)
        FileUtils.mkdir_p(File.dirname(LOCK_PATH.call))
        File.open(LOCK_PATH.call, File::RDWR | File::CREAT, 0o600) do |file|
          raise Busy, "Chrome is busy" unless lock(file, wait: wait, try: try)

          yield
        ensure
          file.flock(File::LOCK_UN) unless file.closed?
        end
      end

      # Under the lock: connects, reaps orphan contexts, yields a Session, and
      # disposes whatever the session still owns. Chrome trouble is Unavailable.
      def session(wait: 900, try: false)
        with_lock(wait: wait, try: try) do
          session = Session.new(connect)
          begin
            session.reap
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

      def lock(file, wait:, try:)
        return file.flock(File::LOCK_EX | File::LOCK_NB) ? true : false if try

        deadline = Process.clock_gettime(Process::CLOCK_MONOTONIC) + wait
        loop do
          return true if file.flock(File::LOCK_EX | File::LOCK_NB)
          return false if Process.clock_gettime(Process::CLOCK_MONOTONIC) >= deadline

          sleep 0.2
        end
      end

      def connect
        host = ENV["BANCO_CHROME_HOST"].presence
        host ? connect_remote(host) : local_browser
      rescue Resolv::ResolvError, SocketError => e
        raise Unavailable, "cannot resolve #{ENV['BANCO_CHROME_HOST']}: #{e.message}"
      rescue Ferrum::Error, Errno::ECONNREFUSED, NoMethodError => e
        raise Unavailable, "cannot reach Chrome: #{e.class}: #{e.message}"
      end

      def connect_remote(host)
        ip = Resolv.getaddress(host)
        Ferrum::Browser.new(url: "http://#{ip}:#{ENV.fetch('BANCO_CHROME_PORT', '9222')}", timeout: 30)
      end

      def local_browser
        @local = nil if @local_pid != Process.pid || !local_alive?
        @local ||= begin
          path = chrome_path or raise Unavailable, "no Chrome to launch: set BROWSER_PATH"
          options = FLAGS.dup
          options["no-sandbox"] = nil if ENV["BANCO_CHROME_NO_SANDBOX"] == "1"
          @local_pid = Process.pid
          at_exit { @local&.quit if @local_pid == Process.pid }
          Ferrum::Browser.new(browser_path: path, headless: true, ignore_default_browser_options: true,
                              browser_options: options, process_timeout: 90, timeout: 30)
        end
      end

      def local_alive?
        @local.nil? || (@local.version && true)
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
