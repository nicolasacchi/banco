require "test_helper"
require_relative "../support/validation_servers"
require_relative "../support/chrome_helper"

# The harness and the Chrome phase: generators run only in the browser, from a
# page with no cookie and no secret, in two fresh contexts (A-02).
class ChromePhaseTest < ActiveSupport::TestCase
  include ChromeHelper

  GENERATOR = <<~JS.freeze
    export function generate(seed, rng) {
      const a = rng.int(2, 9);
      const b = rng.int(2, 9);
      return {
        display: { stem_it: "Quanto fa $" + a + "+" + b + "$?" },
        answer: String(a + b),
        errors: [{ code: "subtracts", value: String(a - b) }],
        solution: { steps: [{ text_it: "Somma i numeri." }], final: String(a + b) }
      };
    }
  JS

  VERIFY = <<~JS.freeze
    export function verify(instance) {
      const m = instance.display.stem_it.match(/\\$(\\d+)\\+(\\d+)\\$/);
      return { ok: String(Number(m[1]) + Number(m[2])) === String(instance.answer) };
    }
  JS

  setup { require_chrome! }

  def run_phase(files, verify: false, seeds: 1..20)
    token = stage_token(files)
    Validation::ChromeRunner.session do |session|
      phase = Validation::ChromePhase.new(session, token: token, verify: verify)
      begin
        result = phase.generate_all(seeds)
        yield phase, result if block_given?
        result
      ensure
        phase.close
      end
    end
  end

  test "a deterministic generator gives the same canonical output in two fresh contexts" do
    result = run_phase({ "generator.mjs" => GENERATOR })
    assert_equal 20, result.rows.size
    assert(result.rows.all?(&:ok))
    assert_empty result.nondeterministic
    out = result.rows.first.output
    assert_equal %w[answer display errors solution], out.keys.sort
    assert_match(/\AQuanto fa/, out["display"]["stem_it"])
  end

  test "verify runs in the page on instances" do
    run_phase({ "generator.mjs" => GENERATOR, "verify.mjs" => VERIFY }, verify: true) do |phase, result|
      assert result.verify_loaded
      jobs = result.rows.first(3).flat_map do |row|
        out = row.output
        [ { id: "ok#{row.seed}", instance: out }, { id: "bad#{row.seed}", instance: out.merge("answer" => "0") } ]
      end
      verdict = phase.verify(jobs)
      assert(verdict.select { |id, _| id.start_with?("ok") }.values.all? { |v| v["ok"] })
      assert(verdict.select { |id, _| id.start_with?("bad") }.values.none? { |v| v["ok"] })
    end
  end

  test "Math.random, Date and crypto throw inside the page" do
    {
      "Math.random()" => "Math.random",
      "new Date()" => "Date",
      "crypto.getRandomValues(new Uint8Array(2))" => "crypto",
      "performance.now()" => "performance.now"
    }.each do |expr, name|
      source = "export function generate(seed, rng) { const x = #{expr}; return { display: {}, answer: 1 }; }"
      result = run_phase({ "generator.mjs" => source }, seeds: 1..2)
      assert_not result.rows.first.ok, expr
      assert_includes result.rows.first.error, name
    end
  end

  test "a generator that depends on the clock differs between contexts" do
    # performance.now is stubbed, but a mark still carries the real time.
    source = "export function generate(seed, rng) { return { display: { stem_it: 'x' + performance.mark('a').startTime }, answer: 1 }; }"
    result = run_phase({ "generator.mjs" => source }, seeds: 1..5)
    assert_not_empty result.nondeterministic
  end

  test "a generator that throws on a seed is a row with the message, not an abort" do
    source = "export function generate(seed, rng) { if (seed % 2 === 0) throw new Error('even'); return { display: {}, answer: seed }; }"
    result = run_phase({ "generator.mjs" => source }, seeds: 1..4)
    assert_equal [ true, false, true, false ], result.rows.map(&:ok)
    assert_equal "even", result.rows[1].error
  end

  test "a module that does not load is reported as a load error" do
    result = run_phase({ "generator.mjs" => "export function generate( {" }, seeds: 1..2)
    assert_includes result.load_error, "generator.mjs did not load"
    result = run_phase({ "generator.mjs" => "export const x = 1;" }, seeds: 1..2)
    assert_includes result.load_error, "does not export generate"
  end

  test "a slow generate call is flagged and stops the run" do
    source = "export function generate(seed, rng) { let s = 0; for (let i = 0; i < 4e8; i++) s += i; return { display: {}, answer: s }; }"
    Validation::Rules.with(generator: { generate_timeout_ms: 5 }) do
      result = run_phase({ "generator.mjs" => source }, seeds: 1..10)
      assert result.timed_out
      assert_equal 1, result.rows.size
      assert result.rows.first.timeout
    end
  end

  test "the page cannot open a connection and holds no cookie" do
    token = stage_token({ "generator.mjs" => GENERATOR })
    Validation::ChromeRunner.session do |session|
      session.context do |ctx|
        page = ctx.create_page
        page.go_to(Validation::Harness.page_url(token))
        page.evaluate_async("window.bancoHarness.ready.then(arguments[0])", 20)
        probe = "fetch('#{ValidationServers.url(:harness)}/lib/rng.mjs').then(() => arguments[0]('allowed'), () => arguments[0]('blocked'))"
        assert_equal "blocked", page.evaluate_async(probe, 10)
        assert_equal "", page.evaluate("document.cookie")
      end
    end
  end
end
