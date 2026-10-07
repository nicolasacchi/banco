require "test_helper"
require_relative "../support/validation_servers"
require_relative "../support/chrome_helper"
require_relative "../support/validation_fixtures"

# Every E- code of the registry that M5 owns has a fixture that produces it (A-06),
# and so does every W- code. The good fixture passes with 24 instances. The codes of
# the independence and review stages (E-VERIFY-AUTHOR, E-SESSION-NOT-INDEPENDENT,
# E-QUOTE-NOT-FOUND, E-REVIEW-EMPTY, E-BLIND-SOLVE-MISMATCH, E-PROVIDER-NOT-ALLOWED,
# E-GRADE-POINT, E-GRADE-QUOTE) belong to M6 and later.
class CodeFixturesTest < ActiveSupport::TestCase
  include ChromeHelper
  F = ValidationFixtures

  OWNED_STAGES = %w[schema ruby chrome roundtrip verify blueprint].freeze
  LATER = %w[E-VERIFY-AUTHOR E-SESSION-NOT-INDEPENDENT].freeze

  def self.owned_codes
    Validation::Codes.all.select { |code, meta| OWNED_STAGES.include?(meta["stage"]) && !LATER.include?(code) }.keys
  end

  # ---- the helpers every case uses ---------------------------------------------------------------

  def item(overrides = {}) = F.static_item(overrides)

  def static_codes(doc, context: F.context, files: nil)
    Validation::ItemRunner.new(files: files || F.files_for(doc), context: context).call.findings.map(&:code).uniq
  end

  def chrome_codes(files, **opts)
    require_chrome!
    token = stage_token(files)
    Validation::ItemRunner.new(files: files, context: F.context, harness_token: token, **opts).call.findings.map(&:code).uniq
  end

  def gen(source, verify: F::VERIFY) = F.generated_files(generator: source, verify: verify)

  def graph_codes(&edit)
    doc = JSON.parse(JSON.generate(F::GRAPH))
    edit&.call(doc)
    context = Validation::Context.new(subject: "math", source_line: ->(s, n) { F::LINES.dig(s, n) })
    Validation::Rules.with(coverage: { prima_source: "prima-test" }) do
      Validation::GraphChecks.call(doc, subject: "math", context: context).map(&:code).uniq
    end
  end

  def skill(doc, key) = doc["skills"].find { |s| s["key"] == key }

  BP_SKILLS = %w[math.linear-equation-integer math.percentages math.factoring math.decimal-operations].freeze
  # Pinned revision ids of the fixture blueprint and the skill each one measures.
  BP_ITEMS = (BP_SKILLS + %w[math.integer-operations]).each_with_index.flat_map { |s, i| [ [ "r#{i}a", s ], [ "r#{i}b", s ] ] }.to_h.freeze

  def bp_info(id, passed: true)
    Validation::BlueprintChecks::ItemInfo.new(id: id, skills: [ BP_ITEMS.fetch(id) ], passed: passed,
                                              instances: (1..4).map { |i| { fingerprint: "#{id}-#{i}", low_guess: true } })
  end

  def blueprint_codes(items: nil, context: F.context, &edit)
    lookup = items || ->(id) { BP_ITEMS.key?(id) ? bp_info(id) : nil }
    doc = {
      "schema" => "banco.blueprint/1", "schema_version" => 1, "subject" => "math", "graph_revision_id" => "1",
      "entries" => BP_SKILLS.each_with_index.map { |s, i| { "skill" => s, "items" => [ "r#{i}a", "r#{i}b" ] } },
      "descent" => [ { "skill" => "math.integer-operations", "items" => [ "r4a", "r4b" ] },
                     { "skill" => "math.fractions-operations", "not_assessed_reason_it" => "Non misurabile." } ],
      "budget" => { "sitting_minutes" => 30, "sittings" => 2 }, "depends_on_subjects" => [], "calculator" => "no",
      "intro_note_it" => "Il test dura mezz'ora.", "not_measured_it" => "Non misura la geometria."
    }
    edit&.call(doc)
    Validation::BlueprintChecks.call(doc, graph: F::GRAPH, subject: "math", context: context, items: lookup).map(&:code).uniq
  end

  def choice_with(**) = F.choice_item(**)

  def long_sentence = "Risolvi l'equazione #{([ 'molto' ] * 30).join(' ')}."

  # ---- the table ----------------------------------------------------------------------------------------

  def good_instance_with(&edit)
    inst = F.number_instance(2, 9)
    edit.call(inst)
    item("instances" => [ inst, F.number_instance(4, 13) ], "tests" => { "must_accept" => [], "must_reject" => [], "blank" => "invalid" })
  end

  def matching_item(left, right, right_text: nil)
    answer = left.first(right.size - 1).to_h { |i| [ "l#{i}", "r#{i}" ] }
    inst = { "display" => { "stem_it" => "Abbina.", "left" => left.map { |i| { "id" => "l#{i}", "text" => "sinistra #{i}" } }, "right" => right.map { |i| { "id" => "r#{i}", "text" => (right_text && i == right.first ? right_text : "destra #{i}") } } },
             "answer" => answer, "errors" => [ { "code" => "swap", "value" => answer.to_a.reverse.to_h } ],
             "solution" => { "steps" => [ { "text_it" => "Abbina." } ], "final" => "fatto" } }
    item("component" => "matching", "instances" => [ inst, inst.merge("display" => inst["display"].merge("stem_it" => "Abbina ancora.")) ],
         "error_catalogue" => [ { "code" => "swap", "description_it" => "Scambio.", "message_it" => "Controlla.", "implicates" => [] } ],
         "tests" => { "must_accept" => [], "must_reject" => [], "blank" => "invalid" })
  end

  def expression_item(answers, error)
    insts = answers.each_with_index.map do |a, i|
      { "display" => { "stem_it" => "Semplifica l'espressione numero #{i}." }, "answer" => a, "errors" => [ { "code" => "slip", "value" => error } ],
        "solution" => { "steps" => [ { "text_it" => "Semplifica." } ], "final" => a } }
    end
    item("component" => "expression", "instances" => insts, "tests" => { "must_accept" => [], "must_reject" => [], "blank" => "invalid" },
         "error_catalogue" => [ { "code" => "slip", "description_it" => "Errore.", "message_it" => "Controlla.", "implicates" => [] } ])
  end

  CASES = {
    "E-SCHEMA" => -> { static_codes(item.except("sources")) },
    "E-GRAPH-CYCLE" => -> { graph_codes { |d| skill(d, "math.integer-operations")["prerequisites"] = [ "math.percentages" ] } },
    "E-SOURCE" => -> { graph_codes { |d| skill(d, "math.percentages")["refs"][0]["fragment"] = "una frase inventata" } },
    "E-SCOPE" => -> { graph_codes { |d| skill(d, "math.percentages").merge!("scope" => "middle_school", "scope_reason_it" => "Dalle medie.") } },
    "E-NEEDED-BY" => -> { graph_codes { |d| d["skills"] << F.skill_row("math.orphan", "Orfana", needed: false) } },
    "E-GRAPH-EDGE-UNAPPROVED" => -> { graph_codes { |d| skill(d, "math.percentages")["prerequisites"] << "italian.reading" } },
    "E-SKILL-UNKNOWN" => -> { static_codes(item("skill" => "math.nonexistent")) },
    "E-ASSET" => -> { static_codes(item, files: F.files_for(item, "assets/a.svg" => "<svg><script>1</script></svg>")) },
    "E-COMPOSITE" => lambda {
      catalogue = [ { "code" => "sign_error", "description_it" => "Segno.", "message_it" => "Controlla.", "implicates" => [ F::PREREQ, "math.factoring" ] } ]
      static_codes(item("error_catalogue" => catalogue))
    },
    "E-CODE-GLOBAL" => -> { static_codes(item, files: F.files_for(item, "generator.mjs" => "export function generate() { return Math.random(); }")) },
    "E-COMPONENT-NUMERIC" => -> { static_codes(expression_item([ "12", "15" ], "11")) },
    "E-EXPONENT-MULTIDIGIT" => -> { static_codes(expression_item([ "x^{12}+1", "x^{10}+2" ], "x^2")) },
    "E-DISPLAY-KEY" => -> { static_codes(good_instance_with { |i| i["display"]["correct"] = "7" }) },
    "E-SOLUTION-IN-DISPLAY" => lambda {
      static_codes(item("instances" => [ F.number_instance(25, 150).tap { |i| i["display"]["table"] = { "header" => [ "V" ], "rows" => [ [ "125" ] ] } }, F.number_instance(4, 13) ],
                        "tests" => { "must_accept" => [], "must_reject" => [], "blank" => "invalid" }))
    },
    "E-CHOICE-OPTIONS" => -> { static_codes(F.choice_item("instances" => [ F.choice_instance("sette", %w[tredici]), F.choice_instance("otto", %w[quattro]) ])) },
    "E-DISTRACTOR-UNCODED" => lambda {
      uncoded = F.choice_instance("sette", %w[tredici nove undici]).tap { |i| i["errors"].pop }
      static_codes(F.choice_item("instances" => [ uncoded, F.choice_instance("otto", %w[quattro sei dieci]) ]))
    },
    "E-OPTION-DUPLICATE" => -> { static_codes(F.choice_item("instances" => [ F.choice_instance("sette", %w[sette nove undici]), F.choice_instance("otto", %w[quattro sei dieci]) ])) },
    "E-MATCHING-SIZE" => -> { static_codes(matching_item([ 1, 2, 3 ], [ 1, 2, 3, 4 ])) },
    "E-MATCHING-RIGHT-MARKUP" => -> { static_codes(matching_item([ 1, 2, 3, 4 ], [ 1, 2, 3, 4, 5 ], right_text: "$x \\leq 2$")) },
    "W-ERROR-NOT-IN-GRAPH" => -> { static_codes(item("error_catalogue" => [ item["error_catalogue"].first.merge("code" => "brand_new_code") ])) },
    "W-FORM-SKILL-CLOSURE" => -> { static_codes(item("form_skill" => "math.fractions-operations", "form" => [ "reduced" ])) },
    "W-ACCEPT-ITEM-LEVEL" => lambda {
      inst = ->(key, wrong) { { "display" => { "stem_it" => "Scrivi #{wrong}." }, "errors" => [ { "code" => "sign_error", "value" => wrong } ], "answer" => key, "solution" => { "steps" => [ { "text_it" => "Isola l'incognita." } ], "final" => "fatto" } } }
      static_codes(item("component" => "normalized_text", "accept" => [ "un po'" ], "instances" => [ inst.("po'", "mai"), inst.("ha", "no") ],
                        "tests" => { "must_accept" => [ "po'" ], "must_reject" => [ "mai" ], "blank" => "invalid" }))
    },
    "E-ACCENT-POLICY" => -> { static_codes(item("accent_policy" => "strict")) },
    "E-PROVA-A-PARAMS" => -> { static_codes(item("sources" => [ { "kind" => "prova_a_structure", "ref" => "struttura", "fragment" => "esercizio" } ])) },
    "E-READ" => -> { static_codes(item("prompt" => { "stem_it" => long_sentence })) },
    "E-PHRASE" => -> { static_codes(item("prompt" => { "stem_it" => "Scrivi la risposta che cercano." })) },
    "E-MESSAGE" => -> { static_codes(item("error_catalogue" => [ item["error_catalogue"].first.merge("message_it" => "Uno. Due. Tre.") ])) },
    "E-QUOTE-REF" => -> { static_codes(item("prompt" => { "stem_it" => "Leggi.", "quote" => { "ref" => "nessuno", "text" => "x" } })) },
    "E-ROUNDTRIP" => lambda {
      same = F.number_instance(2, 9).tap { |i| i["errors"] = [ { "code" => "sign_error", "value" => "7" } ] }
      static_codes(item("instances" => [ same, F.number_instance(4, 13) ]))
    },
    "E-ERROR-NEVER-GENERATED" => lambda {
      static_codes(item("error_catalogue" => item["error_catalogue"] + [ { "code" => "never_seen", "description_it" => "Mai.", "message_it" => "Controlla.", "implicates" => [] } ]))
    },
    "E-ACCEPTS-RANDOM" => lambda {
      permissive = Grading::Result.new(verdict: "correct", grader: "closed")
      Grading.stub(:grade_spec, ->(_s, _r, **) { permissive }) { static_codes(item) }
    },
    "E-STEP-INCONSISTENT" => -> { static_codes(good_instance_with { |i| i["solution"]["final"] = "x = 9" }) },
    "E-GEN-NONDETERMINISTIC" => lambda {
      chrome_codes(gen(F::GENERATOR.sub('"Risolvi $x+" + a', '"Risolvi (" + self.performance.mark("m").startTime + ") $x+" + a')))
    },
    "E-GEN-THROW" => -> { chrome_codes(gen("export function generate(seed, rng) { throw new Error('boom'); }")) },
    "E-GEN-TIMEOUT" => lambda {
      slow = F::GENERATOR.sub("const a = rng.int(2, 40);", "let s = 0; for (let i = 0; i < 4e8; i++) s += i; const a = rng.int(2, 40);")
      Validation::Rules.with(generator: { generate_timeout_ms: 5 }) { chrome_codes(gen(slow)) }
    },
    "E-GEN-SCHEMA" => -> { chrome_codes(gen("export function generate(seed, rng) { return { display: { stem_it: 'x' + seed }, answer: String(seed) }; }")) },
    "E-GEN-POOL" => lambda {
      few = F::GENERATOR.sub("const a = rng.int(2, 40);", "const a = 2 + (seed % 3);").sub("const c = a + rng.int(2, 60);", "const c = a + 7;")
      chrome_codes(gen(few))
    },
    "E-VERIFY-MISSING" => -> { chrome_codes(F.generated_files(verify: nil)) },
    "E-VERIFY-REJECTS" => -> { chrome_codes(gen(F::GENERATOR, verify: "export function verify(instance) { return { ok: false }; }")) },
    "E-VERIFY-STALE" => lambda {
      chrome_codes(gen(F::GENERATOR, verify: "export function verify(instance) { return { ok: false }; }"), verify_inherited: true)
    },
    "E-VERIFY-VACUOUS" => -> { chrome_codes(gen(F::GENERATOR, verify: "export function verify(instance) { return { ok: true }; }")) },
    "E-POOL-REDO" => lambda {
      blueprint_codes { |d| d["entries"][0]["items"] = [ "r0a" ] }
    },
    "E-BLUEPRINT-ENTRIES" => -> { blueprint_codes { |d| d["entries"] = d["entries"].first(3) } },
    "E-ITEM-NOT-PASSED" => -> { blueprint_codes(items: ->(id) { BP_ITEMS.key?(id) ? bp_info(id, passed: id != "r1a") : nil }) },
    "E-BLUEPRINT-UNPINNED-DESCENT" => -> { blueprint_codes { |d| d["descent"].pop } },
    # Warnings.
    "W-SHORT-SKILL-CLOSED" => lambda {
      blueprint_codes(items: ->(id) { BP_ITEMS.key?(id) ? bp_info(id).tap { |i| i.kind = "short_answer" if id == "r0a" } : nil })
    },
    "W-STALE-PIN" => lambda {
      blueprint_codes(items: ->(id) { BP_ITEMS.key?(id) ? bp_info(id).tap { |i| i.latest_passed_id = "r0z" if id == "r0a" } : nil })
    },
    "W-RULES-OUTDATED" => lambda {
      blueprint_codes(items: ->(id) { BP_ITEMS.key?(id) ? bp_info(id).tap { |i| i.rules_version = "1" if id == "r0a" } : nil })
    },
    "W-TESTLET-MULTI-SKILL" => lambda {
      blueprint_codes(items: ->(id) { BP_ITEMS.key?(id) ? bp_info(id).tap { |i| i.testlet_skills = [ BP_ITEMS[id], "math.other" ] if id == "r0a" } : nil })
    },
    "W-GUEST-UNAPPROVED" => lambda {
      draft = Validation::Context.new(subject: "math", draft_skill: ->(k) { k == "italian.reading" ? { "key" => k } : nil })
      blueprint_codes(context: draft) { |d| d["entries"][0].merge!("skill" => "italian.reading", "guest_of_subject" => "italian") }
    },
    "W-IMPLICATE-PENDING" => lambda {
      base = F.context
      draft = Validation::Context.new(subject: "math", skill: base.method(:skill).to_proc, graph_present: true, source_line: ->(s, n) { base.source_line(s, n) },
                                      draft_skill: ->(k) { k == "chemistry.draft-skill" ? { "key" => k } : nil })
      static_codes(item("error_catalogue" => [ item["error_catalogue"][0].merge("implicates" => [ "chemistry.draft-skill" ]) ]), context: draft)
    },
    "W-ANSWER-IN-STEM" => -> { static_codes(item("instances" => [ F.number_instance(25, 150, stem: "Risolvi $x+25=150$ sapendo che il risultato e 125."), F.number_instance(4, 13) ], "tests" => { "must_accept" => [], "must_reject" => [], "blank" => "invalid" })) },
    "W-LONGEST-CORRECT" => -> { static_codes(F.choice_item("instances" => (1..4).map { |i| F.choice_instance("una risposta molto lunga numero #{i}", %w[uno due tre]) })) },
    "W-ERROR-UNREACHABLE" => lambda {
      display = { "stem_it" => "Abbina.", "left" => (1..4).map { |i| { "id" => "l#{i}", "text" => "sinistra #{i}" } },
                  "right" => (1..5).map { |i| { "id" => "r#{i}", "text" => "destra #{i}" } } }
      inst = { "display" => display, "answer" => { "l1" => "r1", "l2" => "r2", "l3" => "r3", "l4" => "r4" },
               "errors" => [ { "code" => "sign_error", "value" => { "l1" => "r2", "l2" => "r2", "l3" => "r3", "l4" => "r4" } } ],
               "solution" => { "steps" => [ { "text_it" => "Abbina." } ], "final" => "fatto" } }
      static_codes(item("component" => "matching", "instances" => [ inst, inst.merge("display" => display.merge("stem_it" => "Abbina ancora.")) ],
                        "tests" => { "must_accept" => [], "must_reject" => [], "blank" => "invalid" }))
    },
    "W-GULPEASE" => -> { static_codes(item("prompt" => { "stem_it" => ([ "Paradigmaticamente incontrovertibilmente costituzionalizzabile" ] * 9).join(" ") + "." })) },
    "W-PASSAGE-READABILITY" => lambda {
      passage = ([ "Paradigmaticamente incontrovertibilmente costituzionalizzabile" ] * 9).join(" ") + "."
      subs = (1..5).map { |i| item.slice("skill", "component", "prompt", "error_catalogue", "instances", "tests").merge("id" => "q#{i}") }
      static_codes({ "schema" => "banco.item/1", "schema_version" => 1, "kind" => "testlet", "subject" => "math", "skill" => F::SKILL, "passage_it" => passage,
                     "expected_seconds" => 300, "sub_items" => subs, "sources" => item["sources"] })
    },
    "E-TESTLET-SKILLS" => lambda {
      subs = (1..5).map { |i| item.slice("skill", "component", "prompt", "error_catalogue", "instances", "tests").merge("id" => "q#{i}") }
      subs[1] = subs[1].merge("skill" => F::PREREQ)
      static_codes({ "schema" => "banco.item/1", "schema_version" => 1, "kind" => "testlet", "subject" => "math", "skill" => F::SKILL, "passage_it" => "Un testo breve e chiaro.",
                     "expected_seconds" => 300, "sub_items" => subs, "sources" => item["sources"] })
    },
    "W-ABSOLUTE" => -> { static_codes(item("prompt" => { "stem_it" => "Il risultato e sempre positivo." })) },
    "W-NEGATIVE-STEM" => -> { static_codes(item("prompt" => { "stem_it" => "Quale frase non e corretta?" })) },
    "W-DECIMAL-POINT" => -> { static_codes(item("prompt" => { "stem_it" => "Il prezzo e 3.5 euro." })) },
    "W-SELF-CERT" => -> { static_codes(item("prompt" => { "stem_it" => "Ho verificato il calcolo." })) },
    "W-SCOPE-MARKER" => lambda {
      doc = JSON.parse(JSON.generate(F::GRAPH))
      context = Validation::Context.new(subject: "math", source_line: ->(s, n) { (l = F::LINES.dig(s, n)) && s == "prima-test" ? l.merge(block_marker: "★") : l })
      Validation::Rules.with(coverage: { prima_source: "prima-test" }) { Validation::GraphChecks.call(doc, subject: "math", context: context).map(&:code).uniq }
    },
    "W-REF-OTHER-SUBJECT" => lambda {
      doc = JSON.parse(JSON.generate(F::GRAPH))
      lines = { 1 => "Italiano", 2 => "Italiano", 3 => "Storia" }
      %w[math.integer-operations math.fractions-operations math.linear-equation-integer].each_with_index do |key, i|
        doc["skills"].find { |s| s["key"] == key }["refs"][0].merge!("line" => i + 1, "fragment" => F::LINES.dig("seconda-test", 1)[:text])
      end
      context = Validation::Context.new(subject: "math", source_line: ->(_s, _n) { { text: F::LINES.dig("seconda-test", 1)[:text], origin: "pdf" } },
                                        source_section: ->(_s, n) { lines[n] })
      Validation::GraphChecks.call(doc, subject: "math", context: context).map(&:code).uniq
    },
    "W-GRAPH-READABILITY" => lambda {
      doc = JSON.parse(JSON.generate(F::GRAPH))
      doc["skills"][0]["errors"] = [ { "code" => "long_one", "description_it" => ("parola " * 30).strip + ".", "implicates" => [] } ]
      Validation::GraphChecks.call(doc, subject: "math", context: F.context).map(&:code).uniq
    },
    "W-GRAPH-DEFERRED-APPROVED" => lambda {
      doc = JSON.parse(JSON.generate(F::GRAPH))
      doc["skills"][0]["deferred_prerequisites"] = [ { "skill" => "italian.reading", "reason_it" => "Serve la lettura." } ]
      context = Validation::Context.new(subject: "math", source_line: ->(src, n) { F::LINES.dig(src, n) }, approved_skill: ->(k) { k == "italian.reading" ? { "key" => k } : nil })
      Validation::GraphChecks.call(doc, subject: "math", context: context).map(&:code).uniq
    },
    "W-TESTLET-LEAK" => lambda {
      long = "il contratto e annullabile per incapacita"
      subs = (1..5).map do |n|
        key = n == 1 ? long : "chiave numero #{n} del tutto diversa"
        ds = n == 2 ? [ long, "nove", "undici" ] : %w[tredici nove undici]
        F.choice_item.slice("skill", "component", "prompt", "error_catalogue", "tests", "choice_only_reason_it").merge(
          "id" => "q#{n}", "instances" => Array.new(3) { F.choice_instance(key, ds) }
        )
      end
      static_codes({ "schema" => "banco.item/1", "schema_version" => 1, "kind" => "testlet", "subject" => "math", "skill" => F::SKILL,
                     "passage_it" => "Un breve testo di prova.", "expected_seconds" => 300, "sub_items" => subs,
                     "sources" => [ { "kind" => "inferred", "ref" => "prova", "fragment" => "x" } ] })
    },
    "W-MESSAGE-GIVES-KEY" => lambda {
      leaky = F.choice_item
      leaky["instances"][0] = F.choice_instance("sette unita di massa", %w[tredici nove undici])
      leaky["error_catalogue"][0]["message_it"] = "Quindi la risposta e sette unita di massa."
      static_codes(leaky)
    },
    "W-CALCULATOR" => lambda {
      business = item("subject" => "business", "skill" => "business.invoice")
      static_codes(business, context: F.context(subject: "business", extra_skills: { "business.invoice" => { "key" => "business.invoice" } }))
    }
  }.freeze

  test "every code M5 owns has a fixture in the table" do
    expected = self.class.owned_codes + Validation::Codes.all.keys.grep(/\AW-/)
    assert_empty expected - CASES.keys, "codes without a fixture"
    assert_empty CASES.keys - Validation::Codes.all.keys, "fixtures for codes that are not in the registry"
  end

  CASES.each do |code, run|
    test "fixture for #{code} produces it" do
      assert_includes instance_exec(&run), code
    end
  end

  test "the good fixture passes with 24 instances" do
    require_chrome!
    files = F.generated_files
    result = Validation::ItemRunner.new(files: files, context: F.context, harness_token: stage_token(files)).call
    assert_equal "passed", result.status, result.findings.map(&:to_h).inspect
    assert_equal 24, result.instances.size
    assert_empty result.findings.errors
  end
end
