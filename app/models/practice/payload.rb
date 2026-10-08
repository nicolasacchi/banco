module Practice
  # Pieces of the student's JSON (A9.3) that several endpoints share. Only what the student may see
  # at that moment: a hint the student asked for (or the auto hint of row 3), a solution the state
  # machine sent. Never the key, the error values or the other hints.
  module Payload
    module_function

    def hint(instance, n)
      hints = Instances.hints(instance)
      { n: n, total: hints.size, hint_it: hints.fetch(n - 1) }
    end

    # {steps: [{text_it, math?}], final}
    def solution(instance)
      s = Instances.solution(instance)
      { steps: Array(s["steps"]).map { |st| { text_it: st["text_it"], math: st["math"] }.compact }, final: s["final"] }
    end

    def skill(key, states_before, states_after)
      after = states_after[key]
      { key: key, state: after.state, state_it: Messages.state_it(after.state), why_it: Messages.why_it(after.why),
        changed: states_before[key]&.state != after.state }
    end

    def closed = { status: "closed", message_it: I18n.t("practice.closed") }

    def actions(status) = status.actions.map(&:to_s)
  end
end
