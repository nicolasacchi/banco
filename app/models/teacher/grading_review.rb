module Teacher
  # «Contestazioni» (D-368): where the grader may be wrong, before the student says so. A read model over the tries the teacher bot already reads
  # (Attempts::Log: the practice tries, Practice::AttemptLog, and the entry test's answers, Attempts::DiagnosisLog), the teacher's resolutions
  # (Practice::Resolutions and the `resolve_attempt` decisions of the entry test), «Per me va bene così» (PracticeContest, and, for the checks of the
  # lessons, the lesson events `check_contested`: Teacher::LessonContests) and the student's comments.
  # It writes nothing, decides nothing and has no table: it is derived at read time, so it is not retroactive (the grader's later fixes, D-339 and
  # D-352, show only in the tries made after them).
  #
  #   review = Teacher::GradingReview.new(student: student, since: Time.utc(2026, 11, 1), subject: "english")
  #   review.items    # one row per exercise: tries, not-right rate, manual-correction rate, flagged («da controllare») and why
  #   review.tries    # the not-right tries, each with its signals
  #   review.totals   # the weekly measure: written tries not right, manual corrections, identical resends, contested
  #   review.lesson_contests   # the checks of the lessons the student sent to the teacher, with his answer in words (D-400: no comment is written for them)
  #
  # A try is counted when it is one: a practice try the engine graded, an entry-test answer that is not «non lo so» and was graded. It is NOT RIGHT
  # when the grader did not call it right, whatever the teacher said later (a resolved try keeps the grader's own outcome: that is what a signal is
  # about). Only the item's current revision is read: a try on an older revision is skipped (`totals[:superseded]`), because the fix is the
  # revision. Signals of a not-right try:
  #
  #   full_sentence   a whole sentence that holds all the words of the key (or an accepted form) in order, with other words round them
  #   near_text       the whole answer is one or two edits from the key or an accepted form (Damerau, forms of NEAR_MIN_LETTERS letters or more)
  #   resend          the same answer, as the grader reads it, was already sent for this exercise (practice only; since D-339 the app refuses
  #                   it and stores nothing, so only older tries and a redo of the same exercise show it)
  #   contested       the student sent it to the teacher with «Fai controllare» (practice only)
  #   comment         the student wrote a comment (not a «mi piace») at or after the try on its serve or its exercise, or, when the comment names no exercise,
  #                   on its practice page within an hour of it
  #   resolved_right  the teacher's `resolve_attempt` made it right
  #
  # An item is FLAGGED when it has FLAG_MIN_TRIES tries or more and more than half not right, or at least one manual correction (a `resolve_attempt`
  # of any verdict on one of its tries). The thresholds are high on purpose: a wrong alarm costs the teacher's attention.
  #
  # A contest writes no comment (D-400): a practice contest is the `contested` signal of its try, a lesson check's one row of `lesson_contests`.
  #
  # `answer` is what the student typed: his own words, for the teacher's token and page; `to_h(answers: false)` leaves it out for a reader that never sees it.
  class GradingReview
    PRACTICE_RIGHT = %w[correct correct_aided].freeze
    SIGNALS = %w[full_sentence near_text resend contested comment resolved_right].freeze
    FLAG_MIN_TRIES = 5
    FLAG_NOT_RIGHT_ABOVE = 0.5
    NEAR_DISTANCE = 2
    NEAR_MIN_LETTERS = 5
    PAGE_COMMENT_SECONDS = 3600
    TEXT_MAX_CHARS = 300
    EVERYTHING = 1_000_000
    ROW_KEYS = %i[kind ref id at subject skill topic item revision_id outcome answer error_code signals near_distance resolution comment_ids].freeze
    Loaded = Data.define(:tries, :superseded)
    # The student's comments that are not a «mi piace», each with the key of the exercise it names.
    Note = Data.define(:id, :time, :serve_id, :served_event_id, :item, :page)

    attr_reader :student, :since, :subject

    # student: a Student (the official one by default); since: a Time, the first moment a try may have; subject: a subject key.
    def initialize(student: Student.official, since: nil, subject: nil)
      @student = student
      @since = since
      @subject = subject
    end

    # The exercises with at least one try in the window, the flagged ones first (most manual corrections, then the highest rate of not-right tries).
    def items
      @items ||= window.group_by { |t| [ t[:subject], t[:item] ] }.map { |(subject, item), tries| item_row(subject, item, tries) }
                       .sort_by { |r| [ r[:flagged] ? 0 : 1, -r[:manual_corrections], -r[:not_right_rate], -r[:tries], r[:item] ] }
    end

    # The not-right tries in the window, oldest first, each with its signals (an empty list: nothing in them looks like the grader's doing).
    def tries = @tries ||= window.select { |t| t[:not_right] }.map { |t| public_row(t) }

    # The checks of the lessons that the student sent to the teacher in the window, oldest first (Teacher::LessonContests rows).
    def lesson_contests = @lesson_contests ||= LessonContests.call(student: student, since: since, subject: subject)

    # The not-right tries that have at least one signal.
    def suspect_tries = tries.select { |t| t[:signals].any? }

    # What the student typed, in the words the teacher's corrections page uses (Teacher::AnswerWords), for the page: {ref => text} of the tries with a
    # signal. `answer` stays the stored raw text.
    def answer_words = @answer_words ||= Teacher::AnswerWords.call(suspect_tries)

    def totals
      @totals ||= begin
        mine = window
        written = mine.select { |t| t[:written] }
        not_right = mine.select { |t| t[:not_right] }
        written_not_right = written.count { |t| t[:not_right] }
        { tries: mine.size, not_right: not_right.size, written_tries: written.size, written_not_right: written_not_right,
          written_not_right_rate: ratio(written_not_right, written.size), manual_corrections: mine.count { |t| t[:resolution] },
          resends: mine.count { |t| t[:signals].include?("resend") }, contested: mine.count { |t| t[:signals].include?("contested") },
          lesson_contested: lesson_contests.size, items: items.size, flagged_items: items.count { |i| i[:flagged] }, superseded: loaded.superseded,
          signals: SIGNALS.to_h { |s| [ s, not_right.count { |t| t[:signals].include?(s) } ] } }
      end
    end

    # The JSON of the API and the console: the totals, the items and the not-right tries; answers: false leaves out what the student typed.
    def to_h(answers: true)
      rows = answers ? tries : tries.map { |t| t.except(:answer) }
      contests = answers ? lesson_contests : lesson_contests.map { |c| c.except(:answer) }
      { student: student.key, since: since&.utc&.iso8601, subject: subject, totals: totals, items: items, tries: rows, lesson_contests: contests }
    end

    private

    def public_row(try) = try.slice(*ROW_KEYS)

    # ---- the tries, with their signals

    def window
      @window ||= loaded.tries.select { |t| !since || t[:time] >= since }
    end

    def loaded
      @loaded ||= begin
        rows = Attempts::Log.new(student).list(Attempts::Filters.new(subject: subject), kinds: %w[practice diagnosis], limit: EVERYTHING).rows
        current = rows.reject { |r| r[:superseded] }
        Loaded.new(analyse(current), rows.size - current.size)
      end
    end

    def analyse(rows)
      instances = ItemInstance.where(id: rows.map { |r| r[:item_instance_id] }.uniq).includes(item_revision: :item).index_by(&:id)
      @specs = {}
      @instances = instances
      sent = {}
      rows.filter_map do |row|
        try = base(row) or next
        try[:resend] = try[:kind] == "practice" && resend?(sent, try)
        try[:signals] = try[:not_right] ? signals(try) : []
        try
      end
    end

    # The try as the review reads it; nil for a row that is not a try of the review (not a try, not graded, «non lo so»).
    def base(row)
      kind = row[:kind]
      return nil if row[:outcome] == "ungraded"

      if kind == "practice"
        return nil if row[:outcome] == "not_a_try"

        outcome = row[:resolution] ? row[:outcome_before_resolution] : (row[:outcome_before_contest] || row[:outcome])
        right = PRACTICE_RIGHT.include?(outcome) && !contested_ids.include?(row[:id])
        resolution = row[:resolution]
        resolved_right = resolution && PRACTICE_RIGHT.include?(row[:outcome])
      else
        return nil if row[:evidence] == "D"

        outcome = row[:outcome]
        right = row[:evidence] == "C"
        resolution = diagnosis_resolutions[row[:id]]
        resolved_right = resolution && resolution[:right]
        resolution = resolution&.except(:right)
      end
      spec = spec_of(row[:item_instance_id])
      { kind: kind, ref: row[:ref], id: row[:id], time: Time.iso8601(row[:at]), at: row[:at], subject: row[:subject], skill: row[:skill], topic: row[:topic],
        item: row[:item], revision_id: row[:revision_id], item_instance_id: row[:item_instance_id], serve_id: row[:practice_serve_id],
        served_event_id: row[:served_event_id], outcome: outcome.to_s, answer: row[:answer], error_code: row[:error_code], not_right: !right,
        resolution: resolution, resolved_right: resolved_right ? true : false, component: spec.component, written: written?(spec) }
    end

    def signals(try)
      spec = spec_of(try[:item_instance_id])
      found = []
      if try[:written]
        found << "full_sentence" if whole_sentence?(spec, try[:answer])
        distance = near_distance(spec, try[:answer])
        if distance
          try[:near_distance] = distance
          found << "near_text"
        end
      end
      found << "resend" if try[:resend]
      found << "contested" if try[:kind] == "practice" && contested_ids.include?(try[:id])
      try[:comment_ids] = comments_on(try).map(&:id)
      found << "comment" if try[:comment_ids].any?
      found << "resolved_right" if try[:resolved_right]
      found
    end

    def spec_of(instance_id) = @specs[instance_id] ||= Grading::Spec.from_instance(@instances.fetch(instance_id))

    # A written answer (normalized_text, not a bit string): the only component whose text a sentence or a typo can be read in.
    def written?(spec) = spec.component == "normalized_text" && !(spec.profile.is_a?(Hash) && spec.profile["name"] == "binary")

    def candidates(spec) = ([ spec.answer ] + spec.accept).map(&:to_s).reject(&:blank?)

    # All the words of a candidate, in order, with other words in the answer: the sentence round the key (a whole sentence, or the key with words
    # between its own).
    def whole_sentence?(spec, answer)
      mine = Grading::Frame.words(answer)
      candidates(spec).any? do |c|
        words = Grading::Frame.words(c)
        words.any? && mine.size > words.size && subsequence?(words, mine)
      end
    end

    def subsequence?(words, mine)
      at = 0
      words.all? do |w|
        found = (at...mine.size).find { |i| mine[i] == w }
        found && (at = found + 1)
      end
    end

    # The smallest distance (1 or 2) between the whole answer and a candidate of NEAR_MIN_LETTERS letters or more; nil when none is that near.
    def near_distance(spec, answer)
      text = Grading::Closed::Text.normalize(answer.to_s, case_sensitive: spec.case_sensitive)
      return nil if text.empty? || text.length > TEXT_MAX_CHARS

      found = candidates(spec).filter_map do |c|
        wanted = Grading::Closed::Text.normalize(c, case_sensitive: spec.case_sensitive)
        next if wanted.length < NEAR_MIN_LETTERS || wanted.length > TEXT_MAX_CHARS

        d = Grading::Closed::Text.damerau(text, wanted)
        d if d.between?(1, NEAR_DISTANCE)
      end
      found.min
    end

    # The same answer, as the grader reads it, was sent before on this exercise instance (one serve or a redo of it).
    def resend?(sent, try)
      key = [ try[:item_instance_id], answer_key(try) ]
      again = sent.key?(key)
      sent[key] = true
      again
    end

    # As Practice::AnswerRecorder reads an answer to compare it: a whole sentence round a `___` blank is its words, spaces collapsed, text normalized.
    def answer_key(try)
      spec = spec_of(try[:item_instance_id])
      raw = try[:answer].to_s
      text = ((spec.component == "normalized_text" && Grading::Frame.for_spec(spec)&.part(raw)) || raw).gsub(/[[:space:]]+/, " ").strip
      spec.component == "normalized_text" ? Grading::Closed::Text.normalize(text, case_sensitive: spec.case_sensitive) : text
    end

    # ---- what the ledger says about the tries

    def contested_ids = @contested_ids ||= PracticeContest.where(student_id: student.id).pluck(:practice_attempt_id).to_set

    # {attempt id => {verdict, reason_it, at, decision_id, right}} of the entry test's `resolve_attempt` decisions; the latest on a try counts.
    def diagnosis_resolutions
      @diagnosis_resolutions ||= Decision.where(kind: "resolve_attempt", student_id: student.id).order(:id).each_with_object({}) do |decision, out|
        payload = JSON.parse(decision.payload_json)
        next if Practice::Resolutions.practice?(payload)

        verdict = payload["verdict"]
        out[payload["attempt_id"].to_i] = { verdict: verdict, reason_it: payload["reason_it"], at: decision.created_at.utc.iso8601, decision_id: decision.id,
                                            right: Diagnosis::Rules::V1.evidence(verdict) == :C }.compact
      end
    end

    def notes
      @notes ||= begin
        list = Comment.where(student_id: student.id).where.not(reason: "like").order(:id).to_a
        by_revision = ItemRevision.joins(:item).where(id: list.filter_map(&:item_revision_id)).pluck("item_revisions.id", "items.key").to_h
        by_instance = ItemInstance.joins(item_revision: :item).where(id: list.filter_map(&:item_instance_id)).pluck("item_instances.id", "items.key").to_h
        list.map do |c|
          item = by_revision[c.item_revision_id] || by_instance[c.item_instance_id]
          # a comment that names no exercise at all is about the practice page it was written on
          page = c.page_kind == "practice" && c.practice_serve_id.nil? && c.served_event_id.nil? && item.nil? ? c.page_path : nil
          Note.new(c.id, c.created_at, c.practice_serve_id, c.served_event_id, item, page)
        end
      end
    end

    # The comments written at or after the try, having seen the verdict, on its serve, on its exercise, or (a comment that names no exercise) on its practice
    # page within PAGE_COMMENT_SECONDS of it.
    def comments_on(try)
      page = try[:topic] && try[:skill] ? "/topics/#{try[:topic]}/practice/#{try[:skill]}" : nil
      notes.select do |n|
        wait = n.time.to_i - try[:time].to_i
        wait >= 0 &&
          ((n.serve_id && n.serve_id == try[:serve_id]) || (n.served_event_id && n.served_event_id == try[:served_event_id]) ||
           (n.item && n.item == try[:item]) || (page && n.page == page && wait <= PAGE_COMMENT_SECONDS))
      end
    end

    # ---- one item

    def item_row(subject, item, tries)
      not_right = tries.count { |t| t[:not_right] }
      manual = tries.count { |t| t[:resolution] }
      reasons = []
      reasons << "many_not_right" if tries.size >= FLAG_MIN_TRIES && not_right > tries.size * FLAG_NOT_RIGHT_ABOVE
      reasons << "manual_correction" if manual >= 1
      { item: item, subject: subject, skill: tries.last[:skill], component: tries.last[:component], tries: tries.size, not_right: not_right,
        not_right_rate: ratio(not_right, tries.size), manual_corrections: manual, manual_correction_rate: ratio(manual, tries.size),
        resends: tries.count { |t| t[:signals].include?("resend") }, contested: tries.count { |t| t[:signals].include?("contested") },
        suspect_tries: tries.count { |t| t[:not_right] && t[:signals].any? }, flagged: reasons.any?, flag_reasons: reasons, last_at: tries.last[:at] }
    end

    def ratio(part, whole) = whole.zero? ? 0.0 : (part.to_f / whole).round(3)
  end
end
