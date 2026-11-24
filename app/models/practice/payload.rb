module Practice
  # Pieces of the student's JSON (A9.3) that several endpoints share. Only what the student may see
  # at that moment: a hint the student asked for (or the auto hint of row 3), a solution the state
  # machine sent. Never the key, the error values or the other hints.
  module Payload
    module_function

    # {n, total, hint_it} for a legacy item; {n, total, hint_<lang>, hint_it} for a bilingual one (D-402).
    def hint(instance, n) = { n: n, total: Instances.hints(instance).size }.merge(hint_texts(instance, n))

    # The hint as the serve body lists the ones already shown: {n, hint_it} or {n, hint_<lang>, hint_it}.
    def hint_entry(instance, n) = { n: n }.merge(hint_texts(instance, n))

    # {steps: [{text_it, math?}], final} for a legacy item; a bilingual one carries the pair of each step (`text_<lang>`, `text_it`), `final_it` beside
    # `final` and, once the solution is shown, the Italian of the item's passage (`passage_it`: the exercise is over, he cannot answer from it any more).
    def solution(instance)
      s = Instances.solution(instance)
      out = { steps: Array(s["steps"]).map { |st| Items::Text.pair(st, "text").merge(math: st["math"]).compact }, final: s["final"] }
      out[:final_it] = s["final_it"] if s["final_it"]
      out.merge(passage(instance))
    end

    # The Italian of the passage of a bilingual item, for the replies that come after the answer; {} for any other item. The part never carries it.
    def passage(instance)
      body = Instances.body(instance)
      Lessons::Lang.pair?(body, "passage") ? { passage_it: body["passage_it"] } : {}
    end

    def skill(key, states_before, states_after)
      after = states_after[key]
      { key: key, state: after.state, state_it: Messages.skill_state_it(after), why_it: Messages.why_it(after.why), missing_it: Messages.missing_it(after.why),
        changed: states_before[key]&.state != after.state, clean: Messages.clean_count(after.why) }
    end

    def closed = { status: "closed", message_it: I18n.t("practice.closed") }

    # An exercise the topic has replaced with a newer version (D-377): the answer, the hint, the solution and the contest are not taken.
    def replaced = { status: "replaced", message_it: I18n.t("practice.replaced") }

    # The refusal of a serve that is not open: the line of a replaced one, else the line of a closed one.
    def refused(status) = status.state == :replaced ? replaced : closed

    def actions(status) = status.actions.map(&:to_s)

    # The hint's text in the layers the item has: the target one under `hint_<lang>` and the Italian under `hint_it`; a legacy item's one under `hint_it`.
    def hint_texts(instance, n)
      source = Instances.hints_source(instance)
      lang = Items::Text.lang(source, "hints")
      text = Items::Text.hints(source).fetch(n - 1)
      return { hint_it: text } unless lang

      { "hint_#{lang}": text, hint_it: Array(source["hints_it"])[n - 1] }.compact
    end
  end
end
