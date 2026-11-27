module Grading
  # The grader's word on one answer. invalid is not an attempt: it carries a code
  # of config/banco/error_codes.yml (grader_codes) and a message for the
  # student, and nothing is stored.
  class Result
    # The sentence for an answer that cannot be read (config/locales/grading.*.yml, D-356): in the language of the page that asks, Italian
    # for the teacher; a code with no sentence says «unparseable».
    # detail: the word a message names (extra_word: «Scrivi solo il numero, senza «metri».», D-386).
    def self.message(code, detail: nil) = I18n.t("grading.messages.#{code}", word: detail, default: :"grading.messages.unparseable")

    # matched, observation and answer_part are NOT stored columns (to_attributes stays columns only). matched {kind:, value:, code?} says what the answer
    # matched, for the read-only grade commands (`banco item grade`): kind "key", "accept" (an accept entry), "error" (a declared error value, with its code) or
    # "slip" (the key or accept entry an accent, apostrophe or typo slip is of); only a normalized_text grading sets it, the others are read from the key and the errors.
    # "full_sentence" says the
    # student wrote the whole sentence around a `___` blank (D-339) and answer_part is the words she wrote in place of
    # the blank, as typed; the stored `normalized` is then the normalized part, which is what was graded.
    attr_reader :verdict, :error_codes, :form_violations, :normalized, :grading_method, :grader,
                :checker_version, :ce_version, :invalid_code, :reason, :observation, :answer_part, :invalid_detail, :matched

    def initialize(verdict:, grader:, error_codes: [], form_violations: [], normalized: nil, grading_method: nil,
                   checker_version: nil, ce_version: nil, invalid_code: nil, reason: nil, observation: nil, answer_part: nil, invalid_detail: nil, matched: nil)
      @verdict = verdict
      @grader = grader
      @error_codes = error_codes
      @form_violations = form_violations
      @normalized = normalized
      @grading_method = grading_method
      @checker_version = checker_version
      @ce_version = ce_version
      @invalid_code = invalid_code
      @reason = reason
      @observation = observation
      @answer_part = answer_part
      @invalid_detail = invalid_detail
      @matched = matched
    end

    def self.invalid(code, grader:, reason: nil, detail: nil)
      new(verdict: "invalid", grader: grader, invalid_code: code, reason: reason, invalid_detail: detail)
    end

    def invalid? = verdict == "invalid"

    def message_it = invalid? ? self.class.message(invalid_code, detail: invalid_detail) : nil

    # grader_version of the row: git sha, plus the checker version for expressions.
    def grader_version
      checker_version ? "#{Grading.git_sha}+#{checker_version}" : Grading.git_sha
    end

    # Columns of attempt_gradings (seq, attempt_id and source are the recorder's).
    def to_attributes
      {
        verdict: verdict,
        error_codes_json: error_codes.to_json,
        form_violations_json: form_violations.to_json,
        normalized: normalized,
        method: grading_method,
        grader: grader,
        grader_version: grader_version,
        ce_version: ce_version
      }
    end

    # The same result with what it matched (see above).
    def with_matched(kind, value, code: nil)
      dup.tap { |copy| copy.instance_variable_set(:@matched, { kind: kind, value: value, code: code }.compact) }
    end

    # The same result for a whole sentence written around a blank: +part+ is what she wrote in place of the blank.
    def full_sentence(part)
      dup.tap do |copy|
        copy.instance_variable_set(:@observation, "full_sentence")
        copy.instance_variable_set(:@answer_part, part)
      end
    end

    def ==(other)
      other.is_a?(Result) && to_attributes == other.to_attributes && invalid_code == other.invalid_code &&
        observation == other.observation && answer_part == other.answer_part
    end
  end
end
