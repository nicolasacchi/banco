module Attempts
  # The student's answers to the checks inside the lessons (the questions on the cards, Lessons::CheckAnswer), as the teacher bot reads them (D-346).
  # The rows come from Lessons::Progress.check_index and .check_tries, the one reader of the lesson ledger; this class only adds where each one is
  # (subject, topic, card, block) and, for one try, the check as the student had it. Read-only. A try block's exercise, a faded example's step and a
  # check's part are `ex`, `step` and `part`; `outcome` is the grader's verdict (right or wrong): a check is practice for the student's head, it
  # counts for no skill.
  class LessonLog
    def initialize(student)
      @student = student
      @bodies = {}
    end

    # [[id, at]] of the check answers that match the filters (all but the outcome), oldest first. No skill, item or serve in a lesson check.
    def index(filters)
      return [] if filters.skill || filters.item || filters.serve

      lessons = nil
      topics = nil
      lessons = LessonRevision.joins(lesson: :subject).where(subjects: { key: filters.subject }).pluck(:id) if filters.subject
      topics = TopicRevision.joins(:lesson).where(lessons: { key: filters.topic }).pluck(:id) if filters.topic
      card = block = nil
      if (comment = filters.comment)
        return [] unless comment.lesson_revision_id && comment.card

        lessons = lessons ? lessons & [ comment.lesson_revision_id ] : [ comment.lesson_revision_id ]
        card = comment.card
        block = comment.anchor.to_s.split("/").find { |s| s.match?(/\Ablock:\d+\z/) }&.delete_prefix("block:")&.to_i
      end
      Lessons::Progress.check_index(@student, lesson_revision_ids: lessons, topic_revision_ids: topics, card: card, block: block, since: filters.since, till: filters.till)
    end

    # The rows of these check answers (ids), in id order.
    def rows(ids, _filters = nil)
      tries = Lessons::Progress.check_tries(@student, ids)
      revisions = LessonRevision.where(id: tries.map(&:lesson_revision_id).uniq).includes(lesson: :subject).index_by(&:id)
      topics = TopicRevision.where(id: tries.map(&:topic_revision_id).uniq).includes(:lesson).index_by(&:id)
      latest = LessonRevision.where(lesson_id: revisions.values.map(&:lesson_id).uniq).group(:lesson_id).maximum(:id)
      tries.map { |t| row_of(t, revisions.fetch(t.lesson_revision_id), topics.fetch(t.topic_revision_id), latest) }
    end

    # One check answer with the check as the student had it; nil when the id is not this student's check answer. comment: a Comment to keep alone.
    def detail(id, comment: nil)
      try = Lessons::Progress.check_tries(@student, [ id ]).first or return nil
      revision = LessonRevision.includes(lesson: :subject).find(try.lesson_revision_id)
      topic = TopicRevision.includes(:lesson).find(try.topic_revision_id)
      latest = LessonRevision.where(lesson_id: revision.lesson_id).group(:lesson_id).maximum(:id)
      located = Lessons::CheckAnswer.new(revision, student_key: @student.key).located(locator(try))
      row = row_of(try, revision, topic, latest)
      { attempt: row, check: located && check_block(located, revision), place: place_of(try, revision),
        tries_here: Lessons::Progress.check_tries(@student, sibling_ids(try)).map { |t| row_of(t, revision, topic, latest) },
        comments: comments_of(try, comment) }
    end

    private

    def row_of(try, revision, topic, latest)
      row = { id: try.id, at: try.at.utc.iso8601, subject: revision.lesson.subject.key, topic: topic.lesson.key, lesson_revision_id: revision.id, superseded: revision.id != latest[revision.lesson_id],
              topic_revision_id: topic.id, card: try.card, block: try.block, step: try.step, ex: try.ex, part: try.part, component: try.component,
              answer: try.response, try_number: try.try, outcome: try.verdict, error_code: try.code, grader_version: try.grader_version }
      row[:latest_revision_id] = latest[revision.lesson_id] if row[:superseded]
      row[:text_shown] = true if try.text_shown
      card = body_of(revision)["cards"]&.find { |c| c["n"] == try.card }
      row[:card_title] = card["title_it"] if card&.dig("title_it")
      block = card && Array(card["blocks"]).find { |b| b["n"] == try.block }
      row[:block_type] = block["type"] if block
      row.compact.merge(error_code: try.code)
    end

    def body_of(revision) = @bodies[revision.id] ||= revision.body

    def locator(try) = { card: try.card, block: try.block, step: try.step, ex: try.ex, part: try.part }.compact

    # The check as the page's body had it: stored (with the key and the explanation) and as the student saw it (the shuffle of this student's seed),
    # with the shown order and the id map of that shuffle, so a response in shown ids (o1.., e1.., l1.., r1..) reads back to the stored ones.
    def check_block(located, revision)
      check = located.check
      subject = body_of(revision)["subject"]
      rekeyed = Lessons::Checks.rekey(check, located.seed)
      { stored: check, shown: Lessons::StudentBody.check(check, subject, located.seed), shown_order: rekeyed.shown_order, id_map: Lessons::Checks.id_map(check, located.seed) }
    end

    # Where the check sits in the lesson: the card (n, title) and the block (n, type).
    def place_of(try, revision)
      card = body_of(revision)["cards"]&.find { |c| c["n"] == try.card }
      block = card && Array(card["blocks"]).find { |b| b["n"] == try.block }
      { lesson: revision.lesson.key, card: card && { n: card["n"], title_it: card["title_it"], level: card["level"] }.compact,
        block: block && { n: block["n"], type: block["type"] } }.compact
    end

    # The ids of every answer to the same check (same revision, card, block, step, exercise and part), oldest first.
    def sibling_ids(try)
      same = Lessons::Progress.check_index(@student, lesson_revision_ids: [ try.lesson_revision_id ], card: try.card, block: try.block)
      same_ids = same.map(&:first)
      Lessons::Progress.check_tries(@student, same_ids).select { |t| [ t.step, t.ex, t.part ] == [ try.step, try.ex, try.part ] }.map(&:id)
    end

    # The student's comments on this card (and block, when the anchor names one).
    def comments_of(try, only)
      found = Attempts::Comments.list(@student, only, nil, nil) { |scope| scope.where(lesson_revision_id: try.lesson_revision_id, card: try.card) }
      return found if only

      found.select { |c| (block = c[:anchor].to_s.split("/").find { |s| s.match?(/\Ablock:\d+\z/) }).nil? || block == "block:#{try.block}" }
    end
  end
end
