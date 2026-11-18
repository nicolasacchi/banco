module Practice
  # The teacher's resolution of a practice try (D-352): the `resolve_attempt` decisions whose payload says attempt_kind "practice"
  # (the attempt_id is then a practice_attempts id, not a diagnosis attempt's). The latest decision on a try is its resolution; the
  # ledger keeps the earlier ones. Read-only.
  #
  #   Practice::Resolutions.for_student(student.id)   # => {practice attempt id => Resolution}
  module Resolutions
    KIND = "practice".freeze

    Resolution = Data.define(:attempt_id, :verdict, :error_code, :reason_it, :at, :decision_id) do
      def to_h_for_api = { verdict: verdict, error_code: error_code, reason_it: reason_it, at: at.utc.iso8601, decision_id: decision_id }.compact
    end

    module_function

    # Whether a decision payload (parsed) is about a practice try.
    def practice?(payload) = payload["attempt_kind"] == KIND

    def for_student(student_id)
      Decision.where(kind: "resolve_attempt", student_id: student_id).order(:id).each_with_object({}) do |decision, out|
        payload = JSON.parse(decision.payload_json)
        next unless practice?(payload)

        out[payload["attempt_id"].to_i] = Resolution.new(
          attempt_id: payload["attempt_id"].to_i, verdict: payload["verdict"], error_code: payload["error_code"].presence,
          reason_it: payload["reason_it"], at: decision.created_at, decision_id: decision.id
        )
      end
    end
  end
end
