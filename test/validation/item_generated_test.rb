require "test_helper"
require_relative "../support/validation_servers"
require_relative "../support/chrome_helper"
require_relative "../support/validation_fixtures"

# Validation of generated items: the generator and verify run in Chrome (A-02, A-06).
class ItemGeneratedTest < ActiveSupport::TestCase
  include ChromeHelper
  F = ValidationFixtures

  setup { require_chrome! }

  def run_files(files)
    token = stage_token(files)
    Validation::ItemRunner.new(files: files, context: F.context, harness_token: token).call
  end

  def codes(result) = result.findings.map(&:code).uniq

  def gen(source) = F.generated_files(generator: source)

  test "the good generator passes: 24 clean seeds materialized, verify accepts them and rejects the wrong ones" do
    result = run_files(F.generated_files)
    assert_equal "passed", result.status, result.findings.map(&:to_h).inspect
    assert_equal 24, result.instances.size
    assert_equal result.instances.map { |i| i[:seed] }, result.instances.map { |i| i[:seed] }.sort
    assert_operator result.instances.map { |i| i[:fingerprint] }.uniq.size, :>=, 20
    assert_operator result.details[:clean], :>=, 24
    assert_match(/\A\h{64}\z/, result.instances_sha256)
    assert result.chrome_version.present?
  end

  test "exclude_params: a generated instance that shows an excluded value fails E-PROVA-A-PARAMS" do
    item = F.generated_item.merge("exclude_params" => [ "7" ])
    result = run_files(F.generated_files(item))
    assert_includes codes(result), "E-PROVA-A-PARAMS"
    ok = run_files(F.generated_files(F.generated_item.merge("exclude_params" => [ "9999" ])))
    assert_not_includes codes(ok), "E-PROVA-A-PARAMS"
  end

  test "E-VERIFY-MISSING: instances are materialized anyway" do
    result = run_files(F.generated_files(verify: nil))
    assert_equal [ "E-VERIFY-MISSING" ], codes(result)
    assert_equal "failed", result.status
    assert_equal 24, result.instances.size
  end

  test "E-VERIFY-STALE: a carried-forward verify.mjs that rejects (D-141)" do
    files = F.generated_files(verify: "export function verify(instance) { return { ok: false, reason_it: 'Vecchio.' }; }")
    result = Validation::ItemRunner.new(files: files, context: F.context, harness_token: stage_token(files), verify_inherited: true).call
    assert_equal [ "E-VERIFY-STALE" ], codes(result)
    assert_equal "failed", result.status
    assert_equal 24, result.instances.size
  end

  test "E-VERIFY-REJECTS: verify turns down clean seeds" do
    result = run_files(F.generated_files(verify: "export function verify(instance) { return { ok: false, reason_it: 'Non so.' }; }"))
    assert_equal [ "E-VERIFY-REJECTS" ], codes(result)
    assert_equal 24, result.instances.size
    detail = result.findings.find { |f| f.code == "E-VERIFY-REJECTS" }.detail
    assert_equal detail[:count], detail[:rejected_seeds].size
    assert_equal detail[:rejected_seeds].sort, detail[:reasons].values.flatten.sort
    assert_equal [ "Non so." ], detail[:reasons].keys
    assert_equal detail[:count], result.details.dig(:verify, :rejected)
    assert detail[:first_rejected].key?("display"), "the first rejected instance is shown"
    assert detail[:first_rejected].key?("answer")
    samples = detail[:rejected_samples]
    assert_equal [ detail[:count], 8 ].min, samples.size
    assert samples.all? { |x| x.key?("display") && x["reason"] == "Non so." && x.key?("in_stored_pool") }
  end

  test "E-VERIFY-REJECTS: a formula that is wrong in verify" do
    wrong = F::VERIFY.sub("Number(m[2]) - Number(m[1])", "Number(m[2]) + Number(m[1])")
    assert_includes codes(run_files(F.generated_files(verify: wrong))), "E-VERIFY-REJECTS"
  end

  test "E-VERIFY-VACUOUS: a verify that accepts everything" do
    result = run_files(F.generated_files(verify: "export function verify(instance) { return { ok: true }; }"))
    assert_equal [ "E-VERIFY-VACUOUS" ], codes(result)
  end

  test "E-VERIFY-REJECTS: a verify.mjs that does not load" do
    result = run_files(F.generated_files(verify: "export function verify( {"))
    assert(result.findings.any? { |f| f.code == "E-VERIFY-REJECTS" && f.detail[:rule] == "load" })
  end

  test "E-GEN-THROW: a generator that throws" do
    result = run_files(gen("export function generate(seed, rng) { throw new Error('boom'); }"))
    assert_includes codes(result), "E-GEN-THROW"
    assert_includes codes(result), "E-GEN-POOL"
    assert_empty result.instances
  end

  test "E-GEN-THROW: a module that does not load" do
    assert_includes codes(run_files(gen("export function generate( {"))), "E-GEN-THROW"
  end

  test "a generator that throws on a few seeds only is tolerated as problem seeds" do
    source = F::GENERATOR.sub("const a = rng.int(2, 40);", "const a = rng.int(2, 40); if (seed % 20 === 0) throw new Error('rare');")
    result = run_files(F.generated_files(generator: source))
    assert_equal "passed", result.status, result.findings.map(&:to_h).inspect
    assert_equal 10, result.details[:problem_seeds]
  end

  test "E-GEN-TIMEOUT: one generate call over the limit" do
    slow = F::GENERATOR.sub("const a = rng.int(2, 40);", "let s = 0; for (let i = 0; i < 4e8; i++) s += i; const a = rng.int(2, 40);")
    Validation::Rules.with(generator: { generate_timeout_ms: 5 }) do
      assert_includes codes(run_files(gen(slow))), "E-GEN-TIMEOUT"
    end
  end

  test "E-GEN-NONDETERMINISTIC: the output differs between two fresh contexts" do
    # A mark carries the real time (performance.now is stubbed; the lint does not see a property).
    source = F::GENERATOR.sub('"Risolvi $x+" + a', '"Risolvi (" + self.performance.mark("m").startTime + ") $x+" + a')
    assert_includes codes(run_files(gen(source))), "E-GEN-NONDETERMINISTIC"
  end

  test "E-GEN-SCHEMA: a wrong shape, and an output that is too large" do
    no_solution = "export function generate(seed, rng) { return { display: { stem_it: 'x' + seed }, answer: String(seed) }; }"
    assert_includes codes(run_files(gen(no_solution))), "E-GEN-SCHEMA"
    big = "export function generate(seed, rng) { return { display: { stem_it: 'x' + seed }, answer: 'a'.repeat(20000), errors: [], solution: { steps: [{ text_it: 'x' }], final: 'x' } }; }"
    result = run_files(gen(big))
    assert(result.findings.any? { |f| f.code == "E-GEN-SCHEMA" && f.detail[:rule] == "size" })
  end

  test "E-GEN-POOL: too few distinct displays" do
    few = F::GENERATOR.sub("const a = rng.int(2, 40);", "const a = 2 + (seed % 3);").sub("const c = a + rng.int(2, 60);", "const c = a + 7;")
    result = run_files(gen(few))
    assert(result.findings.any? { |f| f.code == "E-GEN-POOL" && f.detail[:distinct] })
  end

  test "tests.must_reject and blank are run on a generated item (E-ROUNDTRIP)" do
    item = F.generated_item
    item["tests"] = { "must_accept" => [], "must_reject" => [ "1" ], "blank" => "invalid" }
    files = F.generated_files(item)
    # "1" is the key only when a seed gives c - a = 1; the generator draws c - a from 2..61, so it is a clean reject
    assert_not_includes codes(run_files(files)), "E-ROUNDTRIP"
    item["tests"]["must_accept"] = [ "-999" ]
    result = run_files(F.generated_files(item))
    assert(result.findings.any? { |f| f.code == "E-ROUNDTRIP" && f.field.end_with?("tests/must_accept") }, result.findings.map(&:to_h).inspect)
  end

  test "E-DISPLAY-KEY: a generated display that carries a key" do
    source = F::GENERATOR.sub("display: { stem_it:", "display: { solution: 'x', stem_it:")
    assert_includes codes(run_files(gen(source))), "E-DISPLAY-KEY"
  end

  test "E-SOLUTION-IN-DISPLAY: the answer appears in a table of the display" do
    source = <<~JS
      export function generate(seed, rng) {
        const x = rng.int(100, 900);
        const a = rng.int(2, 40);
        return {
          display: { stem_it: "Risolvi $x+" + a + "=" + (x + a) + "$.", table: { header: ["Dato"], rows: [[String(x)]] } },
          answer: String(x),
          errors: [{ code: "sign_error", value: String(x + 2 * a) }],
          solution: { steps: [{ text_it: "Togli " + a + "." }], final: "x = " + x }
        };
      }
    JS
    result = run_files(gen(source))
    assert_includes codes(result), "E-SOLUTION-IN-DISPLAY"
    assert_includes codes(result), "E-GEN-POOL"
  end

  test "E-CODE-GLOBAL: a banned global never reaches Chrome" do
    result = run_files(gen("export function generate(seed, rng) { return Math.random(); }"))
    assert_equal [ "E-CODE-GLOBAL" ], codes(result)
    assert_empty result.instances
    assert_nil result.chrome_version
  end

  test "E-ERROR-NEVER-GENERATED and E-ROUNDTRIP on a generated item" do
    catalogue = F.generated_item["error_catalogue"] + [ { "code" => "never_seen", "description_it" => "Mai.", "message_it" => "Controlla.", "implicates" => [] } ]
    assert_includes codes(run_files(F.generated_files(F.generated_item("error_catalogue" => catalogue)))), "E-ERROR-NEVER-GENERATED"
    equal = F::GENERATOR.sub("value: String(c + a)", "value: String(c - a)")
    assert_includes codes(run_files(gen(equal))), "E-ROUNDTRIP"
  end
end
