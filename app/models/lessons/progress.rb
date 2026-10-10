# frozen_string_literal: true

module Lessons
  # What the student has done in a lesson/2, read from lesson_events (A10, A11): the card to resume from and the
  # cards seen (the page), and the teacher's one line per topic. Only this class and its callers read the table; no
  # practice, diagnosis or skill-state read model does (D-254, tests pin it).
  module Progress
    # The teacher's line: cards seen of the core and the extra cards, checks right at the first try over checks
    # answered, the last opening.
    Summary = Data.define(:core_seen, :core_total, :extra_seen, :extra_total, :first_try_right, :checks_answered, :last_at)

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
      answered = events.select { |e| e.kind == "check_answered" }.group_by { |e| [ e.card, e.block ] + e.payload.values_at("step", "ex", "part") }
      first_right = answered.count { |_, rows| rows.first.payload["verdict"] == "right" }
      Summary.new(core_seen: (core & seen).size, core_total: core.size, extra_seen: (extra & seen).size, extra_total: extra.size,
                  first_try_right: first_right, checks_answered: answered.size, last_at: events.last&.at)
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
  end
end
