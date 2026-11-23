module Grading
  # What a grader needs to know about one served instance: the item's declared
  # rules (banco.item/1) plus the instance's own answer and error values. Built
  # from the stored rows (from_instance) or from a plain hash (the shared test
  # vectors use banco.item/1 field names).
  class Spec
    ATTRIBUTES = %i[component subject skill answer errors form form_skill accent_policy spelling_policy
                    paradigm_forms accept unit allow_dot display profile case_sensitive thousands contractions
                    prompt_stem item_texts].freeze

    attr_reader(*ATTRIBUTES)
    # A testlet only: {sub item id => Spec}, in the order of the item's sub_items.
    attr_accessor :sub_specs

    def self.from_hash(hash)
      h = hash.to_h.stringify_keys
      new(
        component: h["component"], subject: h["subject"], skill: h["skill"], answer: h["answer"],
        errors: h["errors"], form: h["form"], form_skill: h["form_skill"],
        accent_policy: h["accent_policy"], spelling_policy: h["spelling_policy"],
        paradigm_forms: h["paradigm_forms"], accept: h["accept"], unit: h["unit"],
        allow_dot: h["allow_dot"], display: h["display"], profile: h["profile"],
        case_sensitive: h["case_sensitive"], thousands: h["thousands"], contractions: h["contractions"],
        prompt_stem: h["prompt"].is_a?(Hash) ? h["prompt"]["stem_it"] : nil,
        item_texts: item_texts_of(h)
      )
    end

    # The words the student reads or is given with the item, as plain texts (D-386): both stems, the answer format, the solution.
    # A number answer may end with a unit word that one of them uses (Grading::Closed::Numbers).
    def self.item_texts_of(h)
      display = h["display"].is_a?(Hash) ? h["display"] : {}
      solution = h["solution"].is_a?(Hash) ? h["solution"] : {}
      steps = Array(solution["steps"]).map { |step| step.is_a?(Hash) ? step["text_it"] : nil }
      [ h.dig("prompt", "stem_it"), display["stem_it"], h["answer_format_it"], display["answer_format_it"], *steps, solution["final"] ].grep(String)
    rescue TypeError
      []
    end

    # The item rules come from the revision body (item.json), the answer, errors
    # and display from the instance.
    def self.from_instance(instance)
      body = JSON.parse(instance.item_revision.body_json)
      return testlet_from_instance(instance, body) if body["kind"] == "testlet"

      display = JSON.parse(instance.display_json)
      own_accept = instance.accept_json.present? ? JSON.parse(instance.accept_json) : []
      from_hash(body.merge(
        "accept" => Array(body["accept"]) + own_accept,
        "component" => (body["kind"] == "short_answer" ? "short_answer" : body["component"]),
        "answer" => JSON.parse(instance.answer_json),
        "errors" => instance.errors_json.present? ? JSON.parse(instance.errors_json) : [],
        "display" => display,
        "solution" => instance.solution_json.present? ? JSON.parse(instance.solution_json) : body["solution"],
        "unit" => display["unit"] || body["unit"]
      ))
    end

    # A testlet instance (decision D-047): display {"sub_items":[{"id","display"}]},
    # answer {sub id => key}, errors {sub id => [{code, value}]}. Each sub item is
    # graded as a Spec of its own, with the rules of its entry in body["sub_items"].
    def self.testlet_from_instance(instance, body)
      display = JSON.parse(instance.display_json)
      answers = JSON.parse(instance.answer_json)
      errors = instance.errors_json.present? ? JSON.parse(instance.errors_json) : {}
      spec = new(component: "testlet", skill: body["skill"], subject: body["subject"])
      spec.sub_specs = Array(body["sub_items"]).to_h do |sub|
        shown = Array(display["sub_items"]).find { |s| s["id"] == sub["id"] }
        [ sub["id"], from_hash(sub.merge("subject" => body["subject"], "answer" => answers[sub["id"]],
                                         "errors" => errors.is_a?(Hash) ? errors[sub["id"]] : [],
                                         "unit" => (shown && shown.dig("display", "unit")) || sub["unit"],
                                         "display" => shown ? shown["display"] : {})) ]
      end
      spec
    end

    def initialize(component:, subject: nil, skill: nil, answer: nil, errors: nil, form: nil, form_skill: nil,
                   accent_policy: nil, spelling_policy: nil, paradigm_forms: nil, accept: nil, unit: nil,
                   allow_dot: nil, display: nil, profile: nil, case_sensitive: nil, thousands: nil, contractions: nil, prompt_stem: nil, item_texts: nil)
      @component = component.to_s
      @subject = subject || skill.to_s.split(".").first
      @skill = skill
      @answer = answer
      @errors = Array(errors)
      @form = Array(form)
      @form_skill = form_skill
      @accent_policy = accent_policy || "strict"
      @spelling_policy = spelling_policy || "exact"
      @paradigm_forms = Array(paradigm_forms)
      @accept = Array(accept)
      @unit = unit
      @allow_dot = allow_dot == true
      @display = display || {}
      @profile = profile
      # number: a dot that groups exactly three digits before the decimal comma is read as a thousands separator (1.115,00 = 1115).
      @thousands = thousands == true
      # normalized_text: "en" expands the contractions of english/contractions on both sides before the comparison.
      @contractions = contractions.presence
      # The item's own stem (prompt.stem_it), shown above the instance's: the text a `___` blank may sit in (Grading::Frame).
      @prompt_stem = prompt_stem
      @item_texts = Array(item_texts)
      # banco.item/1 has no field to declare case sensitivity (decision D-032), so
      # this is false for every stored item; the attribute is the seam for a later
      # schema version.
      @case_sensitive = case_sensitive == true
    end

    # The math the student was shown in the stems (the item's and the instance's): what sits between `$` signs, or a stem that is
    # nothing but arithmetic («5+4», «12 : 3 − 1»). An answer written in full may repeat one of them on its left (D-362).
    # Texts, not trees: the grader that reads them (Closed::Equation, the checker) decides what is an expression.
    MATH_SEGMENT = /\$([^$]+)\$/
    ARITHMETIC_ONLY = %r{\A(?=.*\d)[\d\s+\-−*·×÷:/().,^√²³]+\z}

    def stem_expressions
      texts = [ prompt_stem, display.is_a?(Hash) ? display["stem_it"] : nil ].grep(String)
      found = texts.flat_map { |t| t.include?("$") ? t.scan(MATH_SEGMENT).flatten : (t.strip.match?(ARITHMETIC_ONLY) ? [ t ] : []) }
      found.map(&:strip).reject(&:empty?).uniq
    end

    # Error catalogue values of the instance: [[code, value], ...].
    def error_values
      errors.map { |e| [ e["code"], e["value"] ] }
    end
  end
end
