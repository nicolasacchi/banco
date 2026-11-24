module Teacher
  # Candidate grading vectors from the teacher's corrections (D-368): every `resolve_attempt` that made an answer right is a case the grader got wrong
  # when it was sent, so it is a case for `test/fixtures/grading/vectors.json` (the file Grading and the expression checker both run). The case is the one
  # file's own shape: `id`, `component`, `raw` (the student's answer, structured answers as JSON values, shown ids mapped back to the instance's own),
  # `item` (banco.item/1 field names plus the instance's `answer`, `errors` and `display`: the spec and the key) and `expect` (the verdict the teacher gave).
  # Read-only: it only builds the hashes; `bin/rails banco:grading:vectors` prints them and the operator pastes what he keeps. A vector already in the
  # file (by id) is left out, so a second run lists only what is new. Never real data in git: the operator reviews the words before pasting.
  #
  #   Teacher::GradingVectors.new(student).cases   # => [{ "id" => "resolved-practice-12", "component" => "normalized_text", "raw" => "...", ... }]
  class GradingVectors
    FILE = "test/fixtures/grading/vectors.json".freeze
    BODY_FIELDS = %w[subject skill form form_skill accent_policy spelling_policy paradigm_forms unit allow_dot profile case_sensitive thousands contractions].freeze
    STRUCTURED = %w[fraction ordering matching].freeze
    SKIPPED = %w[testlet short_answer].freeze

    def initialize(student = Student.official, file: Rails.root.join(FILE))
      @student = student
      @file = file
    end

    # The candidate cases, oldest correction first (practice tries, then the entry test's answers).
    def cases
      seen = existing_ids
      list = practice_cases + diagnosis_cases
      list.reject { |c| seen.include?(c["id"]) }.uniq { |c| c.except("id") }
    end

    private

    def existing_ids
      return Set.new unless File.exist?(@file)

      JSON.parse(File.read(@file)).fetch("cases").to_set { |c| c["id"] }
    end

    def practice_cases
      resolutions = Practice::Resolutions.for_student(@student.id)
      attempts = PracticeAttempt.where(student_id: @student.id, id: resolutions.keys).includes(practice_serve: { item_instance: { item_revision: :item } }).index_by(&:id)
      resolutions.sort_by { |id, r| [ r.decision_id, id ] }.filter_map do |id, resolution|
        attempt = attempts[id] or next
        serve = attempt.practice_serve
        build("practice", id, serve.item_instance, attempt.raw, attempt.source, serve.id_map_json, resolution.verdict, resolution.error_code)
      end
    end

    def diagnosis_cases
      decisions = Decision.where(kind: "resolve_attempt", student_id: @student.id).order(:id).filter_map do |decision|
        payload = JSON.parse(decision.payload_json)
        next if Practice::Resolutions.practice?(payload)

        [ payload["attempt_id"].to_i, payload["verdict"], payload["error_code"].presence ]
      end.to_h { |id, verdict, code| [ id, [ verdict, code ] ] } # the latest decision on an answer counts
      attempts = Attempt.where(student_id: @student.id, context: "diagnosis", id: decisions.keys).includes(item_instance: { item_revision: :item }).order(:id)
      served = ItemServed.where(diagnosis_event_id: attempts.map(&:served_event_id)).index_by(&:diagnosis_event_id)
      attempts.filter_map do |attempt|
        verdict, code = decisions.fetch(attempt.id)
        build("diagnosis", attempt.id, attempt.item_instance, attempt.raw, attempt.source, served[attempt.served_event_id]&.id_map_json, verdict, code)
      end
    end

    # nil unless the correction made the answer right (credit evidence) on a component that has a vector.
    def build(kind, id, instance, raw, source, id_map_json, verdict, error_code)
      spec = Grading::Spec.from_instance(instance)
      return nil if SKIPPED.include?(spec.component)
      return nil unless Diagnosis::Rules::V1::EVIDENCE.fetch(Grading::Evidence.key(verdict: verdict, spec: spec, error_codes: Array(error_code), method: nil)) == :C

      expect = { "verdict" => verdict }
      expect["error_codes"] = [ error_code ] if error_code
      vector = { "id" => "resolved-#{kind}-#{id}", "component" => spec.component, "raw" => canonical(spec.component, raw, id_map_json), "item" => item_of(instance) }
      vector["source"] = source if spec.component == "expression" && source.present?
      vector["expect"] = expect
      vector
    end

    # banco.item/1 field names of the item's body that the grader reads, with the instance's answer, errors and display (Grading::Spec.from_instance).
    def item_of(instance)
      body = JSON.parse(instance.item_revision.body_json)
      accept = Array(body["accept"]) + (instance.accept_json.present? ? JSON.parse(instance.accept_json) : [])
      item = body.slice(*BODY_FIELDS)
      item["accept"] = accept if accept.any?
      # the stem in every layer the item has: the grader's frame reads the target one (Items::Text), the display above holds both
      stems = Items::Text.pair(body["prompt"] || {}, "stem").transform_keys(&:to_s).select { |_, v| v.is_a?(String) }
      item["prompt"] = stems if stems.any?
      item["answer"] = JSON.parse(instance.answer_json)
      errors = instance.errors_json.present? ? JSON.parse(instance.errors_json) : []
      item["errors"] = errors if errors.any?
      item["display"] = JSON.parse(instance.display_json)
      item
    end

    # The answer as the vector files hold it: the ids the student was shown mapped back to the instance's own (a choice, an ordering, a matching),
    # a structured answer as the JSON value it stores.
    def canonical(component, raw, id_map_json)
      map = id_map_json.present? ? JSON.parse(id_map_json) : {}
      back = ->(id) { map.is_a?(Hash) ? map.fetch(id.to_s, id) : id }
      case component
      when "choice" then back.(raw.to_s.strip)
      when "ordering" then (list = parse(raw)).is_a?(Array) ? list.map { |id| back.(id) } : raw
      when "matching" then (pairs = parse(raw)).is_a?(Hash) ? pairs.to_h { |l, r| [ back.(l), r.to_s.empty? ? "" : back.(r) ] } : raw
      when "fraction" then parse(raw)
      else raw
      end
    end

    def parse(raw)
      value = JSON.parse(raw.to_s)
      value.is_a?(Hash) || value.is_a?(Array) ? value : raw
    rescue JSON::ParserError
      raw
    end
  end
end
