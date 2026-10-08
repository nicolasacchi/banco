# frozen_string_literal: true

module Practice
  module Rules
    # Rules of the guided practice, version 1 (docs/rules/practice-1.md is the prose; this file holds the
    # numbers, and a test fails when the two drift apart). Every serve records RULES_VERSION. A change of
    # any constant is a new version and a D- entry; every state is derived, so nothing is rewritten.
    # No I/O, no Rails.
    module V1
      RULES_VERSION = "practice/1"
      DEMONSTRATE_CORRECT_UNAIDED = 3   # distinct fingerprints
      DEMONSTRATE_DISTINCT_DAYS = 2     # Europe/Rome calendar days
      DEMONSTRATE_MIN_LOW_GUESS = 2     # of those fingerprints; low guess as Diagnosis::Rules::V1.low_guess?
      CONSOLIDATE_AFTER_DAYS = 14
      REVIEW_BACK_CORRECT = 2           # to_review -> previous state
      MAX_WRONG_TRIES = 2               # counted W tries per serve
      MAX_NEAR_MISS_RETRIES = 1         # a second near miss closes the serve
      MAX_TRIES = 3                     # stored tries per serve (follows from the two above)
      ADVANCE_AFTER_CORRECT_UNAIDED = 2 # per pinned item, before the next item in pin order
      OPEN_SERVE_HOURS = 24
      TIME_CAP_SECONDS = 600
      SUGGESTIONS_MAX = 3
      ZONE = "Europe/Rome"
      STATES = %w[not_seen to_recover to_learn in_study demonstrated consolidated to_review].freeze
    end
  end
end
