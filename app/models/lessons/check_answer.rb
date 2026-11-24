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

    def call(locator, response, client_event_id: nil, text_shown: false)
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
      record(locator, key, check, response, graded, try, client_event_id, text_shown: text_shown) if stored.nil? && @student
      Reply.new(200, reply(graded, check, located, try))
    end

    # The check a locator names and the seed of its shuffle, as the student's page had them (nil when this revision has no such check): the
    # teacher's read of a recorded answer (D-346). Located: check, seed, example, step_index.
    def located(locator) = locate(locator)

    # The student's recorded answers to this one check (the same step, exercise and part), oldest first: the contest of a check (D-396) reads the last.
    def answers(locator)
      key = key_of(locator)
      rows(locator).select { |r| r.payload.slice("step", "ex", "part") == key }
    end

    # What a finished check shows besides its verdict: the explanation, an oral's model answer, the rest of a faded example. nil when there is no such check.
    # A contested check shows it as a check answered right, or wrong twice, does (D-396).
    def revealed(locator)
      located = locate(locator) or return nil
      reveal(located.check, located)
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
      elsif block["type"] == "oral"
        Located.new(Oral.check(block), base, nil, nil)
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

    def record(loc, key, check, response, graded, try, client_event_id, text_shown: false)
      now = Time.current
      LessonEvent.create!(
        student: @student, topic_revision: @topic_revision, lesson_revision: @revision, kind: "check_answered", card: loc[:card], block: loc[:block],
        payload_json: JSON.generate({ component: check["component"], response: response, verdict: graded.verdict, code: graded.code, try: try }.merge(key).merge(shown_text(check, text_shown)).compact),
        grader_version: graded.grader_version, client_event_id: client_event_id.presence&.to_s, at: now, created_at: now
      )
    rescue ActiveRecord::RecordNotUnique
      nil # the same answer arrived twice at once: the first one stands
    end

    # An answer to a `listen` check given after S looked at the text is recorded as such (D-267): the ledger tells hearing from reading.
    def shown_text(check, text_shown)
      check["listen"].present? && text_shown ? { text_shown: true } : {}
    end

    # ---- the reply --------------------------------------------------------------------------------

    # D-402: a reply of a bilingual lesson is what the served body is: the target text in the slots the page reads (`message_it`, `explain_it`, ...) and
    # the Italian of those strings in the reply's own `tr` table {target string => Italian}. The reply is built with both texts (`message_en` + `message_it`)
    # and folded by Lessons::Bilingual, like the body; a legacy check is answered as it always was.
    def reply(graded, check, located, try)
      out = { verdict: graded.verdict, try: try }
      out[:message_it] = graded.message_it if graded.message_it
      out.merge!(reveal(check, located)) if graded.right? || try >= EXPLAIN_FROM_TRY
      lang = StudentBody.lang_of(@body)
      return out unless lang

      entry = graded.error_index && check["errors"].to_a[graded.error_index]
      if entry && Lang.pair?(entry, "message")
        out.delete(:message_it)
        out.merge!(entry.slice("message_#{lang}", "message_it").transform_keys(&:to_sym))
      end
      Bilingual.fold(out.transform_keys(&:to_s), lang).except("lang").transform_keys(&:to_sym)
    end

    def reveal(check, located)
      out = {}
      %w[explain model].each { |base| copy_pair(out, check, base) } # `model`: an oral's model answer (withheld until now, L6)
      out.merge!(rest_of_example(located)) if located.example
      out
    end

    # The text of +base+ with its target sibling, when the source has them and they are not empty.
    def copy_pair(out, source, base)
      StudentBody.wide([ "#{base}_it" ]).each { |key| out[key.to_sym] = source[key] if source[key].present? }
    end

    # The blank step's do_it and the steps after it, up to the next blank (served as the page serves a first blank),
    # the example's result when no blank is left, and the drawing's states of those steps with the drawing that has them.
    def rest_of_example(located)
      example = located.example
      index = located.step_index
      following = example["steps"][(index + 1)..].to_a.index { |s| s["blank"] }
      stop = following ? index + 1 + following : example["steps"].size - 1
      steps = example["steps"][index..stop].each_with_index.map do |s, k|
        item = s.slice(*StudentBody.wide(%w[tag why_it]))
        if following && index + k == stop
          item["blank"] = StudentBody.check(s["blank"], @body["subject"], StudentBody.seed_for_step(StudentBody.seed_for(@student_key, @revision.id, *example_address(example)), index + k))
        else
          item.merge!(s.slice(*StudentBody.wide(%w[do_it])))
        end
        item
      end
      out = { steps: steps }
      out.merge!(example.slice(*StudentBody.wide(%w[result_it])).compact.transform_keys(&:to_sym)) unless following
      if example["diagram"]
        figure = StudentBody.diagram(example["diagram"])
        if figure["states"]
          # the states of the steps now open, from the blank to the step before the next blank (a state shows what its step did), and the
          # figure with them, cut at the next blank as the page's figure was cut at this one: lesson/blocks/example.js swaps it in
          out[:states] = following ? figure["states"][index...stop] : figure["states"].drop(index)
          out[:diagram] = following ? StudentBody.cut_states(figure, stop) : figure
        end
      end
      out
    end

    def example_address(example)
      card = @body["cards"].find { |c| c["blocks"].include?(example) }
      [ card["n"], example["n"] ]
    end

    # The reply of the solution endpoints of a Prova tu exercise (the student's page, the teacher's preview): {n:, solution_it:} (or {n:, steps:} for tagged
    # steps), and for a bilingual exercise the target text in the same slots with its final and the Italian in a `tr` table of the reply, as the check replies
    # have it (D-402). A legacy exercise is answered as it always was: the final is never sent apart.
    def self.solution(exercise)
      steps = exercise["solution_steps"]
      bilingual = steps ? steps.any? { |s| Lang.sibling_lang(s, "do") || Lang.sibling_lang(s, "why") } : !Lang.sibling_lang(exercise, "solution").nil?
      return (steps ? { n: exercise["n"], steps: steps.map { |s| s.slice("tag", "do_it", "why_it") } } : { n: exercise["n"], solution_it: exercise["solution_it"] }) unless bilingual

      out = if steps
        Bilingual.fold({ "n" => exercise["n"], "steps" => steps.map { |s| s.slice(*StudentBody.wide(%w[tag do_it why_it])) } }, nil).except("lang")
      else
        # the exercise sits where the fold expects it (`/exercises/N`), so that a `final` that is form material (translate_material: false) goes to the `final_it` slot with no
        # Italian, as the page reads it
        wrapped = Bilingual.fold({ "exercises" => [ { "n" => exercise["n"] }.merge(exercise.slice(*StudentBody.wide(%w[solution_it final_it]), Bilingual::MARKER)) ] }, nil)
        wrapped["exercises"].first.except(Bilingual::MARKER).merge(wrapped.slice("tr"))
      end
      out.transform_keys(&:to_sym)
    end
  end
end
