# frozen_string_literal: true

module Lessons
  module Diagrams
    # The Ruby side of the component contract v2 (WAVE2 1.2; the D-252 pattern). A type's module `extend`s Contract and
    # overrides what it needs; the defaults here are the contract's shape and a safe "not built yet":
    #
    #   static(data, c)            semantic checks of the whole figure (c is a Collector; findings E-LESSON-DIAGRAM, E-LESSON-MAP...)
    #   state(data, c, path)       semantic checks of one effective state (the figure itself when it has no states)
    #   across(data, states, c)    checks across the states
    #   served(data, mode:)        the whitelist projection of the figure for the student's browser: Hash. +mode+ is :student,
    #                              :teacher or :select. Hidden values (x-banco-hide) and every x-banco-solution field come out as
    #                              null; derived values that the module computes (never the author) are added (L1, L2)
    #   targets(data, set)         the stored target ids of select set +set+ in reading order (the same order as the JS targets())
    #   printed(data, state)       every string the state prints, describe() included, hidden ids' labels and served reveals (L4)
    #   reachable(data)            the outputs the figure's controls can show inside their declared ranges: [String], or
    #                              :over_cap when more than 500 (L5, E-DIAGRAM-REACHABLE-CAP)
    #   verify_functions           {"fn.name" => callable} the `verify:` functions of the figure's family this type registers (1.10)
    #
    # With the checks as no-ops a reserved or draft type passes the reserved dry run with its schema only, as the plan says
    # ("skips their semantic checks"); `served` and the others refuse until the track builds them.
    module Contract
      REACHABLE_CAP = 500

      def static(_data, _collector) = nil

      def state(_data, _collector, _path) = nil

      def across(_data, _states, _collector) = nil

      def served(_data, mode: :student) = raise(NotImplementedError, "#{name} is not available yet: served(data, mode: #{mode.inspect})")

      def targets(_data, set) = raise(NotImplementedError, "#{name} is not available yet: targets(data, #{set.inspect})")

      def printed(_data, _state) = raise(NotImplementedError, "#{name} is not available yet: printed(data, state)")

      def reachable(_data) = []

      def verify_functions = {}
    end
  end
end
