# frozen_string_literal: true

module Validation
  # The parts of an item that have instances of their own: the item itself, or each
  # sub-item of a testlet. A short answer has no unit (its one instance is the
  # prompt).
  module Units
    Unit = Struct.new(:path, :skill, :component, :body, :generator, :instances, keyword_init: true) do
      def catalogue_codes = Array(body["error_catalogue"]).map { |e| e["code"] }
      def forms = Array(body["form"])
      def accept = Array(body["accept"])
    end

    module_function

    def of(item)
      case item["kind"]
      when "diagnosis_item"
        [ unit("", item, item) ]
      when "testlet"
        Array(item["sub_items"]).each_with_index.map { |sub, i| unit("/sub_items/#{i}", sub, sub) }
      else
        []
      end
    end

    def unit(path, body, source)
      Unit.new(path: path, skill: body["skill"], component: body["component"], body: body,
               generator: source.key?("generator"), instances: source["instances"])
    end

    # The keys of a unit body the grader reads (Grading::Spec).
    SPEC_KEYS = %w[component skill form form_skill accent_policy spelling_policy paradigm_forms accept unit allow_dot profile case_sensitive].freeze

    def spec_for(unit, subject, instance, overrides = {})
      Grading::Spec.from_hash(unit.body.slice(*SPEC_KEYS).merge(
        "subject" => subject, "answer" => instance["answer"], "errors" => Array(instance["errors"]), "display" => instance["display"]
      ).merge(overrides))
    end
  end
end
