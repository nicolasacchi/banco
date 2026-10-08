# frozen_string_literal: true

module Practice
  # A hint or solution event of one serve (practice_events), as the serve state machine reads it.
  # kind: "hint_shown" (n, auto) or "solution_shown" (reason).
  ServeEvent = Data.define(:kind, :n, :reason, :auto, :at) do
    def initialize(kind:, n: nil, reason: nil, auto: false, at: nil) = super
  end
end
