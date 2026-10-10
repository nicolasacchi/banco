# frozen_string_literal: true

module Lessons
  # One answer to an inline question of a lesson/2 (A9): find the check in the stored body, recompute the student's
  # shuffle (the same Diagnosis::Rekey seed as Lessons::StudentBody), grade it with the shared graders, record a
  # lesson_events row (unless it is the teacher's preview), and build the reply of the endpoint.
  #
  #   Lessons::CheckAnswer.new(revision, student_key:, student: student_or_nil).call(locator, response, client_event_id:)
  #
  # The locator is {card:, block:, step: nil, ex: nil, part: nil} (1-based, as the URL has them). The try number is
  # the server's (the rows already recorded for this check, plus one), never the browser's; the explanation and the
  # rest of a faded example come after a right answer or the second wrong one (A9). An answer that cannot be read
  # ("invalid") is not a try and is not recorded. A check never writes to the practice ledger.
  class CheckAnswer
    EXPLAIN_FROM_TRY = 2
    Located = Data.define(:check, :seed, :example, :step_index)

    # status: 200 | 404 | 422
    Reply = Data.define(:status, :body)

    def initialize(revision, student_key:, student: nil, topic_revision: nil, trial_try: nil)
      @revision = revision
      @topic_revision = topic_revision
      @body = revision.body
      @student_key = student_key
      @student = student
      @trial_try = trial_try
    end

    def call(locator, response, client_event_id: nil)
      located = locate(locator) or return Reply.new(404, { status: "not_found" })
      return Reply.new(422, { status: "invalid" }) if client_event_id.present? && !client_event_id.to_s.match?(LessonEvent::ID_FORMAT)

      key = key_of(locator)
      stored = existing(client_event_id)
      return Reply.new(422, { status: "invalid" }) if stored && !same_check?(stored, locator)

      # A replay answers for the stored row: the response the ledger holds is graded, never the resent one.
      response = stored.payload.fetch("response") if stored
      check = located.check
      id_map = Checks.id_map(check, located.seed)
      graded = Checks.grade(check, response, id_map, subject: @body["subject"])
      return Reply.new(200, { verdict: "invalid", message_it: graded.message_it }) if graded.invalid?

      try = stored ? stored.payload.fetch("try") : next_try(locator, key)
      record(locator, key, check, response, graded, try, client_event_id) if stored.nil? && @student
      Reply.new(200, reply(graded, check, located, try))
    end

    private

    # ---- where the check is ------------------------------------------------------------------------

    def locate(loc)
      card = @body["cards"].find { |c| c["n"] == loc[:card] } or return nil
      block = card["blocks"].find { |b| b["n"] == loc[:block] } or return nil
      base = StudentBody.seed_for(@student_key, @revision.id, card["n"], block["n"])
      if loc[:ex]
        return nil unless block["type"] == "try"

        exercise = block["exercises"].find { |e| e["n"] == loc[:ex] } or return nil
        if loc[:part]
          return nil if loc[:part] < 1

          check = exercise["checks"]&.at(loc[:part] - 1) or return nil

          Located.new(check, StudentBody.seed_for_exercise(base, exercise["n"], loc[:part] - 1), nil, nil)
        else
          return nil unless exercise["check"]

          Located.new(exercise["check"], StudentBody.seed_for_exercise(base, exercise["n"]), nil, nil)
        end
      elsif loc[:step]
        return nil unless block["type"] == "example" && loc[:step] >= 1

        blank = block["steps"][loc[:step] - 1]&.dig("blank") or return nil
        Located.new(blank, StudentBody.seed_for_step(base, loc[:step] - 1), block, loc[:step] - 1)
      else
        return nil unless block["type"] == "check"

        Located.new(block, base, nil, nil)
      end
    end

    def key_of(loc) = loc.slice(:step, :ex, :part).compact.transform_keys(&:to_s)

    # ---- tries, idempotency, the record -----------------------------------------------------------

    def rows(loc)
      return [] unless @student

      LessonEvent.where(student: @student, lesson_revision: @revision, kind: "check_answered", card: loc[:card], block: loc[:block]).order(:id).to_a
    end

    def next_try(loc, key)
      return @trial_try.to_i.clamp(1, 99) if @trial_try # the teacher's preview records nothing: the browser counts

      rows(loc).count { |r| r.payload.slice("step", "ex", "part") == key } + 1
    end

    def existing(client_event_id)
      return nil if client_event_id.blank? || @student.nil?

      LessonEvent.find_by(student: @student, client_event_id: client_event_id.to_s)
    end

    def same_check?(row, loc)
      row.kind == "check_answered" && row.lesson_revision_id == @revision.id && row.card == loc[:card] && row.block == loc[:block] &&
        row.payload.slice("step", "ex", "part") == key_of(loc)
    end

    def record(loc, key, check, response, graded, try, client_event_id)
      now = Time.current
      LessonEvent.create!(
        student: @student, topic_revision: @topic_revision, lesson_revision: @revision, kind: "check_answered", card: loc[:card], block: loc[:block],
        payload_json: JSON.generate({ component: check["component"], response: response, verdict: graded.verdict, code: graded.code, try: try }.merge(key).compact),
        grader_version: graded.grader_version, client_event_id: client_event_id.presence&.to_s, at: now, created_at: now
      )
    rescue ActiveRecord::RecordNotUnique
      nil # the same answer arrived twice at once: the first one stands
    end

    # ---- the reply --------------------------------------------------------------------------------

    def reply(graded, check, located, try)
      out = { verdict: graded.verdict, try: try }
      out[:message_it] = graded.message_it if graded.message_it
      reveal = graded.right? || try >= EXPLAIN_FROM_TRY
      out[:explain_it] = check["explain_it"] if reveal && check["explain_it"].present?
      out.merge!(rest_of_example(located)) if reveal && located.example
      out
    end

    # The blank step's do_it and the steps after it, up to the next blank (served as the page serves a first blank),
    # the example's result when no blank is left, and the drawing's states from the blank on.
    def rest_of_example(located)
      example = located.example
      index = located.step_index
      following = example["steps"][(index + 1)..].to_a.index { |s| s["blank"] }
      stop = following ? index + 1 + following : example["steps"].size - 1
      steps = example["steps"][index..stop].each_with_index.map do |s, k|
        item = s.slice("tag", "why_it")
        if following && index + k == stop
          item["blank"] = StudentBody.check(s["blank"], @body["subject"], StudentBody.seed_for_step(StudentBody.seed_for(@student_key, @revision.id, *example_address(example)), index + k))
        else
          item["do_it"] = s["do_it"]
        end
        item
      end
      out = { steps: steps }
      out[:result_it] = example["result_it"] if example["result_it"] && !following
      if example["diagram"]
        states = StudentBody.diagram(example["diagram"])["states"]
        out[:states] = states.drop(index) if states
      end
      out
    end

    def example_address(example)
      card = @body["cards"].find { |c| c["blocks"].include?(example) }
      [ card["n"], example["n"] ]
    end
  end
end
