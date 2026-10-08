# Synthetic items, graphs and contexts for validation tests. Everything here is
# generic and invented: no student, no school, no real programme text.
module ValidationFixtures
  SKILL = "math.linear-equation-integer".freeze
  PREREQ = "math.integer-operations".freeze
  LINE1 = "operazioni con i numeri relativi".freeze

  def self.skill_row(key, label, scope: "studied", prereqs: [], taught: true, needed: true, errors: [], reason: nil)
    refs = []
    refs << { "source" => "prima-test", "line" => 1, "fragment" => "numeri relativi", "role" => "taught_in" } if taught
    refs << { "source" => "seconda-test", "line" => 1, "fragment" => "equazioni di primo grado", "role" => "needed_by" } if needed
    row = { "key" => key, "label_it" => label, "layer" => "core", "scope" => scope, "prerequisites" => prereqs, "refs" => refs, "errors" => errors }
    row["scope_reason_it"] = reason if reason
    row
  end

  # A small synthetic graph whose citations resolve against CourseRows' lines.
  GRAPH = {
    "schema" => "banco.skill_graph/1", "schema_version" => 1, "subject" => "math",
    "skills" => [
      skill_row("math.integer-operations", "Operazioni con i numeri interi", needed: false),
      skill_row("math.fractions-operations", "Operazioni con le frazioni", prereqs: [ "math.integer-operations" ], needed: false),
      skill_row("math.linear-equation-integer", "Equazioni lineari intere", prereqs: [ "math.integer-operations" ],
                errors: [ { "code" => "sign_error", "description_it" => "Sposta il termine senza cambiargli il segno.", "implicates" => [ "math.integer-operations" ] } ]),
      skill_row("math.percentages", "Percentuali", prereqs: [ "math.fractions-operations" ]),
      skill_row("math.factoring", "Scomposizione in fattori", scope: "not_in_prima", prereqs: [ "math.integer-operations" ], taught: false,
                reason: "Argomento non presente nel programma dell'anno precedente."),
      skill_row("math.decimal-operations", "Operazioni con i decimali", prereqs: [ "math.integer-operations" ])
    ],
    "excluded" => [ { "line" => 2, "reason_it" => "Riga di servizio." } ]
  }.freeze

  LINES = {
    "prima-test" => {
      1 => { text: "operazioni con i numeri relativi", origin: "pdf" },
      2 => { text: "PAGINA 2", origin: "transcript" }
    },
    "seconda-test" => {
      1 => { text: "equazioni di primo grado", origin: "pdf" }
    }
  }.freeze

  REFERENCE = { "ref-test" => "Il testo di prova dice che ogni cosa ha il suo posto.\nUna seconda riga di prova." }.freeze

  module_function

  def context(subject: "math", graph: GRAPH, extra_skills: {})
    skills = (graph ? graph["skills"].to_h { |s| [ s["key"], s ] } : {}).merge(extra_skills)
    Validation::Context.new(
      subject: subject,
      skill: ->(key) { skills[key] },
      graph_present: !graph.nil?,
      source_line: ->(source, number) { LINES.dig(source, number) },
      reference_body: ->(key) { REFERENCE[key] }
    )
  end

  def deep_merge(a, b)
    a.merge(b) { |_k, x, y| x.is_a?(Hash) && y.is_a?(Hash) ? deep_merge(x, y) : y }
  end

  def number_instance(a, c, stem: nil)
    {
      "display" => { "stem_it" => stem || "Risolvi $x+#{a}=#{c}$." },
      "answer" => (c - a).to_s,
      "errors" => [ { "code" => "sign_error", "value" => (c + a).to_s } ],
      "solution" => { "steps" => [ { "text_it" => "Togli #{a} da entrambi i lati." } ], "final" => "x = #{c - a}" }
    }
  end

  # A good static item: a number component with three instances.
  def static_item(overrides = {})
    base = {
      "schema" => "banco.item/1", "schema_version" => 1, "kind" => "diagnosis_item", "subject" => "math",
      "skill" => SKILL, "component" => "number",
      "prompt" => { "stem_it" => "Risolvi l'equazione e scrivi il valore di $x$." },
      "expected_seconds" => 60,
      "error_catalogue" => [
        { "code" => "sign_error", "description_it" => "Sposta il termine senza cambiargli il segno.",
          "message_it" => "Quando un termine passa dall'altra parte cambia segno. Rifai il passaggio.", "implicates" => [ PREREQ ] }
      ],
      "sources" => [ { "kind" => "inferred", "ref" => "prova", "fragment" => "equazioni di primo grado" } ],
      "instances" => [ number_instance(2, 9), number_instance(4, 13), number_instance(5, 21) ],
      "tests" => { "must_accept" => [ "7" ], "must_reject" => [ "11" ], "blank" => "invalid" }
    }
    deep_merge(base, overrides)
  end

  def files_for(item, extra = {})
    { "item.json" => JSON.generate(item) }.merge(extra)
  end

  # The generator of a good generated item: x + A = C, answer C - A.
  GENERATOR = <<~JS.freeze
    export function generate(seed, rng) {
      const a = rng.int(2, 40);
      const c = a + rng.int(2, 60);
      return {
        display: { stem_it: "Risolvi $x+" + a + "=" + c + "$." },
        answer: String(c - a),
        errors: [{ code: "sign_error", value: String(c + a) }],
        solution: { steps: [{ text_it: "Togli " + a + " da entrambi i lati." }], final: "x = " + (c - a) }
      };
    }
  JS

  VERIFY = <<~JS.freeze
    export function verify(instance) {
      const m = instance.display.stem_it.match(/x\\+(\\d+)=(\\d+)/);
      if (!m) return { ok: false, reason_it: "Testo non riconosciuto." };
      return { ok: String(Number(m[2]) - Number(m[1])) === String(instance.answer) };
    }
  JS

  def generated_item(overrides = {})
    item = static_item("tests" => { "must_accept" => [], "must_reject" => [], "blank" => "invalid" }).except("instances")
    deep_merge(item.merge("generator" => "generator.mjs"), overrides)
  end

  def generated_files(item = generated_item, generator: GENERATOR, verify: VERIFY)
    files = files_for(item, "generator.mjs" => generator)
    files["verify.mjs"] = verify if verify
    files
  end

  # A choice item: one key, the others coded distractors.
  def choice_instance(key_text, distractors, answer: "o1")
    options = [ { "id" => "o1", "text" => key_text } ] + distractors.each_with_index.map { |t, i| { "id" => "o#{i + 2}", "text" => t } }
    {
      "display" => { "stem_it" => "Quale valore risolve l'equazione?", "options" => options },
      "answer" => answer,
      "errors" => distractors.each_with_index.map { |_t, i| { "code" => "distractor_#{i + 1}", "value" => "o#{i + 2}" } },
      "solution" => { "steps" => [ { "text_it" => "Risolvi con calma." } ], "final" => key_text }
    }
  end

  def choice_item(overrides = {})
    codes = %w[distractor_1 distractor_2 distractor_3].map do |c|
      { "code" => c, "description_it" => "Un errore tipico.", "message_it" => "Controlla il passaggio.", "implicates" => [] }
    end
    base = static_item(
      "component" => "choice", "choice_only_reason_it" => "Il concetto e nuovo.",
      "error_catalogue" => codes,
      "instances" => [
        choice_instance("sette", %w[tredici nove undici]),
        choice_instance("otto", %w[quattro sei dieci])
      ],
      "tests" => { "must_accept" => [ "o1" ], "must_reject" => [ "o2" ], "blank" => "invalid" }
    )
    deep_merge(base, overrides)
  end

  HINTS = [ "Quale numero togli da entrambi i membri?", "Togli il termine noto dai due lati.", "Ora la $x$ resta da sola." ].freeze

  # A good static practice item (Phase 1b): the number item with 12 instances, a level and 3 hints.
  def practice_item(overrides = {}, count: 12)
    instances = (1..count).map { |n| number_instance(n + 1, 2 * n + 11) } # key n + 10, a different display each
    deep_merge(static_item("kind" => "practice_item", "level" => 1, "hints_it" => HINTS, "instances" => instances,
                           "tests" => { "must_accept" => [ "11" ], "must_reject" => [ "999" ], "blank" => "invalid" }), overrides)
  end

  def short_answer_item(overrides = {})
    deep_merge({
      "schema" => "banco.item/1", "schema_version" => 1, "kind" => "short_answer", "subject" => "math", "skill" => SKILL,
      "component" => "short_answer", "prompt" => { "stem_it" => "Spiega con parole tue come si risolve un'equazione." },
      "sources" => [ { "kind" => "inferred", "ref" => "prova", "fragment" => "equazioni" } ],
      "rubric" => { "points" => [ { "id" => "idea", "weight" => 2, "expected_it" => "Dice che si isola l'incognita." },
                                  { "id" => "check", "weight" => 1, "expected_it" => "Controlla il risultato." } ],
                    "model_answer_it" => "Si isola l'incognita con operazioni uguali ai due lati e si controlla il risultato." }
    }, overrides)
  end
end
