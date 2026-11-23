# frozen_string_literal: true

module Lessons
  # What the student has done in a lesson/2, read from lesson_events (A10, A11): the card to resume from and the
  # cards seen (the page), and the teacher's one line per topic. Only this class and its callers read the table; no
  # practice, diagnosis or skill-state read model does (D-254, tests pin it). The teacher bot's read of the student's answers to the checks
  # (D-346) is here too: `check_index` and `check_tries`, called by Attempts::LessonLog.
  module Progress
    # The teacher's line: cards seen of the core and the extra cards, checks right at the first try over checks
    # answered (a check he sent to the teacher with «Per me va bene così» is answered, D-396), how many of those he sent, the last opening.
    Summary = Data.define(:core_seen, :core_total, :extra_seen, :extra_total, :first_try_right, :checks_answered, :checks_contested, :last_at)

    # One answer to a check (a `check_answered` row): where it was given (card, block and, in a try block or a faded example, the exercise,
    # the part or the step), the response exactly as the page sent it, the grader's verdict (right|wrong), the matched error code and the
    # try number the server counted.
    CheckTry = Data.define(:id, :topic_revision_id, :lesson_revision_id, :card, :block, :step, :ex, :part, :component, :response, :verdict, :code, :try,
                           :grader_version, :text_shown, :at)

    module_function

    # { card: the card of the last card_seen of this revision, or nil; seen: [n, ...] sorted }
    def for(student, revision)
      rows = LessonEvent.where(student: student, lesson_revision_id: revision.id, kind: "card_seen").order(:id).pluck(:card)
      { card: rows.last, seen: rows.uniq.sort }
    end

    # nil for a lesson/1 revision (no cards) or no revision.
    def summary(student, revision)
      return nil unless revision&.lesson2?

      cards = revision.body["cards"]
      core = cards.select { |c| c["level"] == "core" }.map { |c| c["n"] }
      extra = cards.select { |c| c["level"] == "extra" }.map { |c| c["n"] }
      events = LessonEvent.where(student: student, lesson_revision_id: revision.id).order(:id).to_a
      seen = events.select { |e| e.kind == "card_seen" }.map(&:card).uniq
      place = ->(e) { [ e.card, e.block ] + e.payload.values_at("step", "ex", "part") }
      answered = events.select { |e| e.kind == "check_answered" }.group_by(&place)
      contested = events.select { |e| e.kind == "check_contested" }.map(&place).uniq
      first_right = answered.count { |_, rows| rows.first.payload["verdict"] == "right" }
      Summary.new(core_seen: (core & seen).size, core_total: core.size, extra_seen: (extra & seen).size, extra_total: extra.size,
                  first_try_right: first_right, checks_answered: (answered.keys | contested).size, checks_contested: contested.size, last_at: events.last&.at)
    end

    # The card a new "Riprendi" on Oggi should open, or nil: the last card seen of the lesson revision the topic
    # pins, when the student looked at it after their last practice of the topic's skills.
    def resume_card(student, topic_revision, skills)
      revision = topic_revision.lesson_revision
      return nil unless revision.lesson2?

      last = LessonEvent.where(student: student, lesson_revision_id: revision.id, kind: "card_seen").order(:id).last or return nil
      practiced = PracticeServe.where(student: student, skill_key: skills).maximum(:created_at)
      return nil if practiced && practiced > last.at

      last.card
    end

    # [[id, at]] of the student's check answers, oldest first. lesson_revision_ids / topic_revision_ids: only those revisions; card / block: only
    # that place; since / till: answered at or after / at or before; none: no filter.
    def check_index(student, lesson_revision_ids: nil, topic_revision_ids: nil, card: nil, block: nil, since: nil, till: nil)
      scope = LessonEvent.where(student_id: student.id, kind: "check_answered")
      scope = scope.where(lesson_revision_id: lesson_revision_ids) if lesson_revision_ids
      scope = scope.where(topic_revision_id: topic_revision_ids) if topic_revision_ids
      scope = scope.where(card: card) if card
      scope = scope.where(block: block) if block
      scope = scope.where("lesson_events.at >= ?", since) if since
      scope = scope.where("lesson_events.at <= ?", till) if till
      scope.order(:id).pluck(:id, :at)
    end

    # The CheckTry of these event ids of the student, in id order (an id that is not the student's check answer is left out).
    def check_tries(student, ids)
      LessonEvent.where(student_id: student.id, kind: "check_answered", id: ids).order(:id).map do |e|
        payload = e.payload
        CheckTry.new(id: e.id, topic_revision_id: e.topic_revision_id, lesson_revision_id: e.lesson_revision_id, card: e.card, block: e.block,
                     step: payload["step"], ex: payload["ex"], part: payload["part"], component: payload["component"], response: payload["response"],
                     verdict: payload["verdict"], code: payload["code"], try: payload["try"], grader_version: e.grader_version,
                     text_shown: payload["text_shown"] == true, at: e.at)
      end
    end
  end
end
