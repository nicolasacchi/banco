# frozen_string_literal: true

module Diagnosis
  module Rules
    # Rules of the entry diagnosis, version 1 (docs/rules/diagnosis-1.md is the
    # prose; this file holds the numbers). Every run records RULES_VERSION. A change
    # of any constant here bumps the version: runs already made keep the version
    # they were made under. No I/O, no Rails: the engine and its property tests
    # use this module as plain data.
    module V1
      RULES_VERSION = "diagnosis/1"

      SUBJECTS = %w[math italian english spanish history geography law_economics
                    business computer_science biology chemistry].freeze

      # Short prefixes of the skill inventory mapped to subject keys. A skill key
      # is "<subject>.<slug>", for example math.linear-equation-integer.
      INVENTORY_PREFIXES = {
        "mat" => "math", "it" => "italian", "hist" => "history", "geo" => "geography",
        "eng" => "english", "es" => "spanish", "inf" => "computer_science",
        "che" => "chemistry", "bio" => "biology", "eca" => "business", "dir" => "law_economics"
      }.freeze
      SKILL_KEY_PATTERN = /\A(?:#{SUBJECTS.join('|')})\.[a-z0-9]+(?:-[a-z0-9]+)*\z/

      # Subjects with discursive content: one reading testlet and exactly one
      # short answer (B-06, C-05).
      DISCURSIVE_SUBJECTS = %w[italian english spanish history geography law_economics biology].freeze

      # ---- Evidence (X-03, X-04, operator Q10) ------------------------------
      # What one graded answer is worth to the engine: C credit, W wrong, D "I do
      # not know". :pending counts neither way; :ungraded is not an outcome yet;
      # :none is not an attempt.
      NEAR_MISS = :pending           # (a) a one-letter typo in a written answer
      WRONG_FORM_DECLARED = :credit  # (b) right value in a declared, separate form skill
      ORTHOGRAPHY_SLIP = :credit     # (c) accent or apostrophe slip on an item that does not measure spelling
      OPTIONS_FOR_CASES = %i[credit pending].freeze

      ORTHOGRAPHY_ALLOWLIST = %w[es_accents it_accents it_apostrophe_accent].freeze

      # Near-miss detection: answers of at least NEAR_MISS_MIN_LENGTH characters at
      # one Damerau edit from an accepted answer, on items with spelling_policy near.
      NEAR_MISS_MIN_LENGTH = 5
      NEAR_MISS_EDIT_DISTANCE = 1

      EVIDENCE = {
        "correct" => :C,
        "typical_error" => :W,
        "wrong" => :W,
        "dont_know" => :D,
        "wrong_form_skill" => :W,             # the form is the item's own skill
        "wrong_form_declared" => WRONG_FORM_DECLARED == :credit ? :C : :pending,
        "wrong_form_undeclared" => :pending,
        "orthography_slip" => ORTHOGRAPHY_SLIP == :credit ? :C : :pending,
        "near_miss" => NEAR_MISS == :credit ? :C : :pending,
        "undetermined" => :pending,
        "float_method" => :pending,
        "short_answer" => :pending,
        "ungraded" => :ungraded,
        "invalid" => :none
      }.freeze

      # Extra observations that go with a credit, naming the skill they are about.
      OBSERVATIONS = {
        "wrong_form_declared" => :tail_suspect_on_form_skill,
        "orthography_slip" => :observation_on_orthography_skill
      }.freeze

      # ---- Per-skill sequencing (B-02) --------------------------------------
      # Item 1 is low-guess unless the skill has a choice_only_reason.
      LOW_GUESS_COMPONENTS = %w[number fraction expression normalized_text].freeze
      LOW_GUESS_MIN_ORDERING = 4
      LOW_GUESS_MIN_MATCHING_PAIRS = 4
      MAX_SERVED_PER_SKILL = 5          # with pending or ungraded answers outstanding
      MAX_COUNTED_OUTCOMES = 3          # two of three is the last word
      TESTLET_OUTCOMES_PER_SKILL = 1    # one counted outcome per skill per testlet

      # ---- States and reasons (B-04) ----------------------------------------
      STATES = %w[demonstrated to_recover not_assessed pending].freeze
      REASONS = {
        "demonstrated" => %w[two_of_two two_of_two_choice two_of_three short_answer_above_threshold],
        "to_recover" => %w[dont_know two_wrong mixed short_answer_below_threshold],
        "not_assessed" => %w[below_demonstrated time_budget item_cap not_needed cross_subject_unavailable
                             no_unseen_items voided not_started prerequisite_to_recover],
        "pending" => %w[grade_unconfirmed verdict_pending grader_unavailable]
      }.freeze
      KINDS = %w[recover learn].freeze
      # in_progress and not_in_prima are learn; every other scope is recover. A
      # blueprint kind_override {kind, reason_it} changes one skill.
      LEARN_SCOPES = %w[in_progress not_in_prima].freeze
      SCOPES = %w[studied integration_studied in_progress middle_school not_in_prima].freeze
      SCOPES_WITHOUT_PRIMA_REFS = %w[middle_school not_in_prima].freeze

      # ---- Descent (B-03) ----------------------------------------------------
      END_REASONS = %w[frontier_empty time_budget item_cap teacher_close].freeze

      # ---- Time (B-05, Q11, days) --------------------------------------------
      SITTING_BUDGET_MINUTES = Hash.new(25).merge("math" => 30).freeze
      OPEN_RESERVE_MINUTES = 7          # the short answer is served at budget minus this
      ITEM_CAP_SECONDS = 600
      TESTLET_CAP_SECONDS = 1200
      MAX_ITEMS_PER_SITTING = 30
      SITTINGS_PER_SUBJECT = 2          # operator Q11: automatic second sitting
      AUTO_SECOND_SITTING = true        # when skills remain to explore
      ABANDON_GAP_SECONDS = 1800        # an open item is logged item_abandoned
      KEEPALIVE_SECONDS = 600           # one request every 10 minutes while visible
      DAILY_MAX_SUBJECTS = 2
      DAILY_MAX_MINUTES = 75            # a safety ceiling; two first sittings use at most 55

      # ---- Calculator per subject (operator "calculator") ---------------------
      CALCULATOR = Hash.new(:no).merge("business" => :yes, "chemistry" => :yes).freeze

      # ---- Short answer (B-06) ------------------------------------------------
      SHORT_ANSWER_DEFAULT_THRESHOLD = 0.6
      SHORT_ANSWER_MIN_POINTS = 2
      SHORT_ANSWER_POINT_WEIGHTS = (1..3).freeze

      class << self
        # Maximum counted minutes of one sitting for a subject.
        def sitting_budget_minutes(subject) = SITTING_BUDGET_MINUTES[subject]

        # Total minutes a subject can take over all its sittings.
        def subject_budget_minutes(subject) = sitting_budget_minutes(subject) * SITTINGS_PER_SUBJECT

        def calculator(subject) = CALCULATOR[subject]

        # Evidence key for a grading: verdict is the grader's verdict string;
        # context says what the item declares. Returns an EVIDENCE key.
        def evidence_key(verdict, orthography_slip: false, form: nil)
          return "orthography_slip" if orthography_slip && verdict == "typical_error"
          return verdict unless verdict == "wrong_form"

          case form
          when :skill then "wrong_form_skill"
          when :declared then "wrong_form_declared"
          else "wrong_form_undeclared"
          end
        end

        def evidence(verdict, **context) = EVIDENCE.fetch(evidence_key(verdict, **context))

        # kind of a skill: learn for in_progress and not_in_prima, unless overridden.
        def kind_for(scope, override = nil)
          return override if override

          LEARN_SCOPES.include?(scope) ? "learn" : "recover"
        end

        # True when the item is a low-guess item (item 1 and the third item).
        def low_guess?(component, size: nil)
          return true if LOW_GUESS_COMPONENTS.include?(component)

          case component
          when "ordering" then size.to_i >= LOW_GUESS_MIN_ORDERING
          when "matching" then size.to_i >= LOW_GUESS_MIN_MATCHING_PAIRS
          else false
          end
        end
      end
    end
  end
end
