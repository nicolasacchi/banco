module Diagnosis
  # The end-of-subject screen (B-11): what the student already knows, what we will
  # recover, what is to learn, what waits for the teacher, and the solutions. Only
  # a closed run has one (solutions appear when the subject is final). Nothing here
  # is a grade: no score, no percentage, no alarm colour.
  class Summary
    Skill = Data.define(:key, :label, :text)
    Solution = Data.define(:attempt_id, :prompt, :given, :steps, :final, :verdict)

    attr_reader :run

    def initialize(run)
      @run = run
      @conductor = Conductor.new(run)
    end

    def final? = @conductor.closed?

    def result
      @result ||= Derivation.result(@conductor.plan, EventLoader.for_run(run), voided: EventLoader.voided?(run))
    end

    def minutes = (result[:counted_seconds] / 60.0).round

    def groups
      @groups ||= begin
        rows = result[:skills].select { |r| own?(r) }
        known = rows.select { |r| r[:state] == "demonstrated" }
        learn = rows.select { |r| r[:kind] == "learn" && (r[:state] == "to_recover" || r[:reason] == "prerequisite_to_recover") }
        recover = rows.select { |r| r[:state] == "to_recover" && !learn.include?(r) }
        checking = rows.select { |r| r[:state] == "pending" }
        asked = known + learn + recover + checking
        {
          known: known.map { |r| skill(r, I18n.t("summary.reasons.#{r[:reason]}", default: "")) },
          recover: recover.map { |r| skill(r, recover_message(r)) },
          learn: learn.map { |r| skill(r, nil) },
          checking: checking.map { |r| skill(r, nil) },
          not_asked: rows.count { |r| r[:state] == "not_assessed" && !asked.include?(r) }
        }
      end
    end

    # Per attempt: the item, the student's answer in words, the solution. The
    # answers that were not right come first.
    def solutions
      return [] unless final?

      list = served.filter_map { |event, serve| solution_for(event, serve) }
      list.sort_by.with_index { |s, i| [ s.verdict == "correct" ? 1 : 0, i ] }
    end

    private

    def own?(row) = row[:subject] == run.subject.key || row[:guest]

    def skill(row, text) = Skill.new(row[:skill], labels[row[:skill]] || row[:skill], text.presence)

    def labels
      @labels ||= begin
        graph = JSON.parse(run.blueprint_revision.skill_graph_revision.body_json)
        graph["skills"].to_h { |s| [ s["key"], s["label_it"] ] }
      end
    end

    # The approved message for the first error seen on the skill: the
    # message_it of the item's error catalogue.
    def recover_message(row)
      code = row[:error_codes].first
      return I18n.t("summary.no_message") unless code

      catalogue_messages[code] || I18n.t("summary.no_message")
    end

    def catalogue_messages
      @catalogue_messages ||= served.flat_map { |_e, s| catalogue(s.item_instance.item_revision) }.to_h
    end

    def catalogue(revision)
      body = JSON.parse(revision.body_json)
      entries = Array(body["error_catalogue"]) + Array(body["sub_items"]).flat_map { |s| Array(s["error_catalogue"]) }
      entries.map { |e| [ e["code"], e["message_it"] ] }
    end

    def served
      @served ||= run.events.where(kind: "item_served").order(:seq).map do |event|
        [ event, ItemServed.includes(item_instance: :item_revision).find_by!(diagnosis_event_id: event.id) ]
      end
    end

    def solution_for(event, serve)
      attempt = Attempt.includes(:gradings).find_by(served_event_id: event.id)
      return nil unless attempt

      instance = serve.item_instance
      body = JSON.parse(instance.item_revision.body_json)
      solution = instance.solution_json.present? ? JSON.parse(instance.solution_json) : {}
      verdict = attempt.gradings.last&.verdict
      Solution.new(attempt_id: attempt.id, prompt: prompt_text(body, instance), given: AnswerText.call(attempt, serve),
                   steps: Array(solution["steps"]), final: solution["final"], verdict: verdict)
    end

    def prompt_text(body, instance)
      display = JSON.parse(instance.display_json)
      body["kind"] == "testlet" ? body["passage_it"].to_s : [ body["passage_it"], body.dig("prompt", "stem_it"), display["stem_it"] ].compact.join(" ")
    end
  end
end
