module Grading
  # What a grader needs to know about one served instance: the item's declared
  # rules (banco.item/1) plus the instance's own answer and error values. Built
  # from the stored rows (from_instance) or from a plain hash (the shared test
  # vectors use banco.item/1 field names).
  class Spec
    ATTRIBUTES = %i[component subject skill answer errors form form_skill accent_policy spelling_policy
                    paradigm_forms accept unit allow_dot display profile case_sensitive].freeze

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
        case_sensitive: h["case_sensitive"]
      )
    end

    # The item rules come from the revision body (item.json), the answer, errors
    # and display from the instance.
    def self.from_instance(instance)
      body = JSON.parse(instance.item_revision.body_json)
      return testlet_from_instance(instance, body) if body["kind"] == "testlet"

      from_hash(body.merge(
        "component" => (body["kind"] == "short_answer" ? "short_answer" : body["component"]),
        "answer" => JSON.parse(instance.answer_json),
        "errors" => instance.errors_json.present? ? JSON.parse(instance.errors_json) : [],
        "display" => JSON.parse(instance.display_json)
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
                                         "display" => shown ? shown["display"] : {})) ]
      end
      spec
    end

    def initialize(component:, subject: nil, skill: nil, answer: nil, errors: nil, form: nil, form_skill: nil,
                   accent_policy: nil, spelling_policy: nil, paradigm_forms: nil, accept: nil, unit: nil,
                   allow_dot: nil, display: nil, profile: nil, case_sensitive: nil)
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
      # banco.item/1 has no field to declare case sensitivity (decision D-032), so
      # this is false for every stored item; the attribute is the seam for a later
      # schema version.
      @case_sensitive = case_sensitive == true
    end

    # Error catalogue values of the instance: [[code, value], ...].
    def error_values
      errors.map { |e| [ e["code"], e["value"] ] }
    end
  end
end
