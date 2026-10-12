# frozen_string_literal: true

module Lessons
  module Diagrams
    # cross_section: reserved (w2-1, T5). The contract stub of WAVE2 1.2: it holds the place of the Ruby side
    # (check hooks, served, targets, printed, reachable) until the track builds it; see Lessons::Diagrams::Contract.
    # While the type is not available a lesson cannot use it (Lessons::Types), so none of this runs on a stored lesson.
    module CrossSection
      extend Contract
    end
  end
end
