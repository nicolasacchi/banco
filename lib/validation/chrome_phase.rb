# frozen_string_literal: true

module Validation
  # The Chrome phase of validation (A-02, A-06): the revision's generator.mjs and
  # verify.mjs run in a page of the harness listener, inside a fresh browser
  # context of a ChromeRunner::Session (the lock is held by the caller).
  #
  #   phase = ChromePhase.new(session, token: harness_token, verify: true)
  #   gen = phase.generate_all(1..200)        # context A, then context B for determinism
  #   ver = phase.verify(jobs)                # context A again (verify.mjs loaded)
  #   phase.close
  #
  # Nothing here judges: it returns what the page said. Validation::ItemRunner turns
  # it into findings.
  class ChromePhase
    Row = Struct.new(:seed, :ok, :json, :error, :ms, :timeout, keyword_init: true) do
      def output = ok ? JSON.parse(json) : nil
    end

    Generated = Struct.new(:rows, :nondeterministic, :load_error, :verify_error, :verify_loaded, :timed_out, keyword_init: true)

    READY_WAIT = 30
    DEFINED_WAIT = 20
    LOAD_ATTEMPTS = 3

    attr_reader :chrome_version

    def initialize(session, token:, generator: true, verify: false)
      @session = session
      @token = token
      @generator = generator
      @verify = verify
      @chrome_version = session.version
    end

    # Runs every seed in a first context and again in a second, fresh one; a seed
    # whose canonical output differs between the two is nondeterministic.
    def generate_all(seeds)
      list = seeds.to_a
      @ctx = @session.open_context
      @page, state = load_page(@ctx)
      return Generated.new(rows: [], nondeterministic: [], load_error: state["error"], verify_error: state["verify_error"], verify_loaded: false, timed_out: false) unless state["ok"]

      first, timed_out = run_batches(@page, list)
      second = []
      unless timed_out
        @session.context do |ctx|
          page, = load_page(ctx)
          second, = run_batches(page, list)
        end
      end
      nondeterministic = timed_out ? [] : first.zip(second).filter_map { |a, b| a.seed if b.nil? || a.ok != b.ok || (a.ok && a.json != b.json) }
      Generated.new(rows: first, nondeterministic: nondeterministic, load_error: nil, verify_error: state["verify_error"],
                    verify_loaded: state["verify"] == true, timed_out: timed_out)
    end

    # Loads the page of context A without generating (a static item with a verify.mjs).
    def open_for_verify
      @ctx ||= @session.open_context
      @page, state = load_page(@ctx)
      state
    end

    # jobs: [{id:, instance:}]; returns {id => {"ok" =>, "reason" =>, "threw" =>}}.
    def verify(jobs)
      out = {}
      jobs.each_slice(100) do |slice|
        rows = @page.evaluate_async("window.bancoHarness.verify(arguments[0]).then(arguments[1])", batch_wait, slice)
        rows.each { |row| out[row["id"]] = row }
      end
      out
    end

    def close
      @session.close_context(@ctx)
      @ctx = nil
    end

    private

    def batch_wait = Rules.get(:generator, :batch_timeout_seconds)

    def load_page(ctx)
      page = ctx.create_page
      url = Harness.page_url(@token, generator: @generator, verify: @verify)
      LOAD_ATTEMPTS.times do |attempt|
        page.go_to(url)
        break if harness_defined?(page)

        raise ChromeRunner::Unavailable, "the harness page did not define bancoHarness" if attempt == LOAD_ATTEMPTS - 1
      end
      state = page.evaluate_async("window.bancoHarness.ready.then(arguments[0])", READY_WAIT)
      [ page, state ]
    end

    # Under load the page can answer before its script has run: poll, bounded.
    def harness_defined?(page)
      deadline = Process.clock_gettime(Process::CLOCK_MONOTONIC) + DEFINED_WAIT
      loop do
        return true if page.evaluate("typeof window.bancoHarness !== 'undefined' && window.bancoHarness !== null")
        return false if Process.clock_gettime(Process::CLOCK_MONOTONIC) >= deadline

        sleep 0.25
      end
    end

    def run_batches(page, seeds)
      rows = []
      limit = Rules.get(:generator, :generate_timeout_ms)
      seeds.each_slice(Rules.get(:generator, :batch)) do |slice|
        result = page.evaluate_async("window.bancoHarness.generate(arguments[0], arguments[1]).then(arguments[2])", batch_wait, slice, limit)
        rows.concat(result.map { |r| Row.new(seed: r["seed"], ok: r["ok"], json: r["json"], error: r["error"], ms: r["ms"], timeout: r["timeout"]) })
        return [ rows, true ] if rows.last&.timeout
      end
      [ rows, false ]
    end
  end
end
