# frozen_string_literal: true

module Lessons
  # Grading of the inline questions of a lesson/2 (A9). The declared fields of a check are mapped to the spec the shared
  # graders take (Grading::Closed: choice, number, fraction, normalized_text, matching), with the id_map of the very
  # Diagnosis::Rekey call that shuffled this student's options; a span_select is graded as a set here. Grading stays pure
  # and shared; Grading::Recorder is not used and nothing counts for a skill state.
  #
  #   Lessons::Checks.grade(check, response, id_map, subject: "math") -> Graded
  #
  # +response+ is what the browser sent: a shown id (choice), a string (number, normalized_text), {"n","d","w"?}
  # (fraction), {shown left id => shown right id} (matching), [shown span ids] (span_select), at most 200 characters.
  module Checks
    MAX_RESPONSE = 200
    # verdict: "right" | "wrong" | "invalid"; code: the error code of the matched typical error (or the grader's slip);
    # message_it: the hint of the matched error, or why an answer cannot be read; error_index: which errors[] entry.
    Graded = Data.define(:verdict, :code, :message_it, :error_index, :normalized, :grader_version) do
      def right? = verdict == "right"
      def wrong? = verdict == "wrong"
      def invalid? = verdict == "invalid"
    end
    SLIPS_IT = { "it_accents" => "Controlla gli accenti.", "es_accents" => "Controlla los acentos.", "it_apostrophe_accent" => "Controlla l'apostrofo e l'accento." }.freeze

    module_function

    def grader_version = Grading.git_sha

    # Is the response of a size the endpoint accepts at all (A9: at most 200 characters, student data)?
    def small?(response) = JSON.generate(response).size <= MAX_RESPONSE * 3 && flat_strings(response).all? { |s| s.size <= MAX_RESPONSE }

    def flat_strings(value)
      case value
      when String then [ value ]
      when Array then value.flat_map { |v| flat_strings(v) }
      when Hash then value.flat_map { |k, v| flat_strings(k) + flat_strings(v) }
      else []
      end
    end

    # The pure Rekey result for a check and seed (choice, matching), or an empty one.
    def rekey(check, seed)
      case check["component"]
      when "choice" then Diagnosis::Rekey.call(display: { "options" => check["options"] }, component: "choice", answer: check["answer"], seed: seed)
      when "matching" then Diagnosis::Rekey.call(display: { "left" => check["left"], "right" => check["right"] }, component: "matching", answer: check["answer"], seed: seed)
      else Diagnosis::Rekey::Result.new(display: {}, id_map: {}, shown_order: {})
      end
    end

    # {shown id => stored id} of a check for +seed+ (choice and matching: the shuffle; span_select: s1..sN in order).
    def id_map(check, seed)
      return check["spans"].each_with_index.to_h { |s, i| [ "s#{i + 1}", s["id"] ] } if check["component"] == "span_select"

      rekey(check, seed).id_map
    end

    def grade(check, response, id_map = nil, subject: nil)
      return invalid("unparseable") unless small?(response)

      case check["component"]
      when "span_select" then span_select(check, response, id_map || {})
      when "fraction" then closed(check, response, id_map, subject, form: check["mixed"] ? [ "mixed" ] : [])
      else closed(check, response, id_map, subject)
      end
    end

    def invalid(code, version = grader_version)
      Graded.new(verdict: "invalid", code: code, message_it: Grading::Result::MESSAGES_IT.fetch(code, Grading::Result::MESSAGES_IT["unparseable"]), error_index: nil, normalized: nil, grader_version: version)
    end

    # ---- the shared graders ----------------------------------------------------------------------

    def closed(check, response, id_map, subject, form: [])
      errors = check["errors"].to_a
      spec = Grading::Spec.new(
        component: check["component"], subject: subject, answer: check["answer"],
        errors: errors.each_with_index.map { |e, i| { "code" => "e#{i}", "value" => e["answer"] } },
        accept: check["accept"], unit: check["unit"], form: form,
        display: { "options" => check["options"], "left" => check["left"], "right" => check["right"] }.compact
      )
      result = Grading::Closed.grade(spec, response, id_map: id_map.presence)
      from_result(result, errors)
    end

    def from_result(result, errors)
      return invalid(result.invalid_code, result.grader_version) if result.invalid?

      case result.verdict
      when "correct"
        Graded.new(verdict: "right", code: nil, message_it: nil, error_index: nil, normalized: result.normalized, grader_version: result.grader_version)
      when "typical_error"
        index = result.error_codes.filter_map { |c| c[/\Ae(\d+)\z/, 1]&.to_i }.first
        entry = index && errors[index]
        slip = result.error_codes.find { |c| SLIPS_IT.key?(c) }
        Graded.new(verdict: "wrong", code: entry&.[]("code") || slip, message_it: entry&.[]("message_it") || SLIPS_IT[slip], error_index: index, normalized: result.normalized, grader_version: result.grader_version)
      else
        Graded.new(verdict: "wrong", code: nil, message_it: nil, error_index: nil, normalized: result.normalized, grader_version: result.grader_version)
      end
    end

    # ---- span_select: a set of span ids ------------------------------------------------------------

    def span_select(check, response, id_map)
      return invalid("unparseable") unless response.is_a?(Array) && response.all?(String)
      return invalid("empty") if response.empty?

      stored = response.map { |id| id_map[id] }
      return invalid("unparseable") if stored.any?(&:nil?) || stored.uniq.size != stored.size

      set = stored.sort
      normalized = JSON.generate(set)
      return Graded.new(verdict: "right", code: nil, message_it: nil, error_index: nil, normalized: normalized, grader_version: grader_version) if set == check["answer"].sort

      index = check["errors"].to_a.index { |e| e["answer"].is_a?(Array) && e["answer"].sort == set }
      entry = index && check["errors"][index]
      Graded.new(verdict: "wrong", code: entry&.[]("code"), message_it: entry&.[]("message_it"), error_index: index, normalized: normalized, grader_version: grader_version)
    end
  end
end
