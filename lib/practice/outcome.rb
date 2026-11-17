# frozen_string_literal: true

module Practice
  # The practice outcome of one graded try (A8.2). A pure function of the evidence key that
  # Grading::Evidence.key gives (the diagnosis table, same item declarations) and of whether the try
  # was aided. near (practice/3, nil | :typo | :one_word, Grading::NearText.kind) turns a plain `wrong` into a
  # near miss: the answer is one typo or one word away from an accepted one. :contested is not a grading: it is the
  # outcome of a try the student sent to the teacher («Fai controllare»), set by the loader from the stored contest.
  #
  #   Practice::Outcome.call(evidence_key: "correct", aided: true)   # => :correct_aided
  #   Practice::Outcome.call(evidence_key: "wrong", aided: false, near: :typo)   # => :near_miss
  module Outcome
    OUTCOMES = %i[correct correct_aided typical_error unrecognised form near_miss undetermined contested].freeze

    # Evidence class of each outcome: C credit, W wrong, N counts neither way.
    EVIDENCE = {
      correct: :C, correct_aided: :C, typical_error: :W, unrecognised: :W, form: :W, near_miss: :N, undetermined: :N, contested: :N
    }.freeze

    CREDIT_KEYS = %w[correct orthography_slip wrong_form_declared nearly_correct].freeze
    UNDETERMINED_KEYS = %w[undetermined float_method wrong_form_undeclared].freeze

    class NotATry < ArgumentError; end

    module_function

    def call(evidence_key:, aided:, near: nil)
      key = evidence_key.to_s
      return aided ? :correct_aided : :correct if CREDIT_KEYS.include?(key)
      return :undetermined if UNDETERMINED_KEYS.include?(key)

      case key
      when "typical_error" then :typical_error
      when "wrong" then near ? :near_miss : :unrecognised
      when "wrong_form_skill" then :form
      when "near_miss" then :near_miss
      else raise NotATry, "evidence key #{key.inspect} is not a practice try"
      end
    end

    # Whether an evidence key makes a try at all (invalid, dont_know and short_answer do not).
    def try?(evidence_key)
      call(evidence_key: evidence_key, aided: false)
      true
    rescue NotATry
      false
    end

    def evidence(outcome) = EVIDENCE.fetch(outcome.to_sym)
  end
end
