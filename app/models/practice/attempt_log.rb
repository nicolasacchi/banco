module Practice
  # The student's practice tries as the teacher bot reads them (D-346): one student's `practice_attempts` with what the practice engine
  # makes of each (Practice::Instances.grade, the same outcome the pages and the fold use), the serve it belongs to, the hints and the
  # solution of that serve, and, for one try, the exercise as the student saw it. Read-only: it never writes and never records that
  # anyone read. One kind of Attempts::Log (the others: the entry test, the checks in lessons); the teacher token alone reads it.
  #
  #   log = Practice::AttemptLog.new(student)
  #   log.index(filters)            # [[id, answered_at]] oldest first, after the filters
  #   log.rows(ids, filters)        # the rows of those tries
  #   log.detail(attempt_id)        # nil when the try is not this student's
  #
  # Every try is listed, also one on a superseded item revision (`superseded: true`, `latest_revision_id`) and one on a voided revision:
  # the log is the ledger, the fold's exclusions are not applied. The outcome is the engine's: correct, correct_aided, typical_error,
  # unrecognised, form, near_miss, undetermined, contested (the student sent it to the teacher, D-339; `outcome_before_contest` is what
  # it was before), the outcome the teacher gave it (D-352: `resolution` {verdict, reason_it, error_code?, at, decision_id}, `outcome_before_resolution`;
  # a try after the one that closed its serve is `counted: false`) and, for a stored text that is not a try, not_a_try (graded invalid or «Non lo so») or ungraded (no grading yet).
  class AttemptLog
    OUTCOMES = (Outcome::OUTCOMES.map(&:to_s) + %w[not_a_try ungraded]).freeze

    def initialize(student)
      @student = student
      @specs = {}
      @shown = {}
    end

    # [[id, answered_at]] of the tries that match the filters (all but the outcome), oldest first.
    def index(filters)
      matching(filters).order("practice_attempts.id").pluck("practice_attempts.id", "practice_attempts.answered_at")
    end

    # The rows of these tries (ids), in id order; the anchor row of the comment filter is added to each.
    def rows(ids, filters)
      attempts = load(PracticeAttempt.where(id: ids)).to_a
      contested = contested_ids(ids)
      latest = latest_revisions(attempts.map { |a| a.practice_serve.item_instance.item_revision.item_id }.uniq)
      attempts.map do |attempt|
        row = row_of(attempt, contested, latest)
        anchor = filters.comment && anchor_row(filters.comment.anchor, attempt)
        anchor ? row.merge(anchor_row: anchor) : row
      end
    end

    # One try with everything about its serve; comment: a Comment to keep alone among the comments on the serve.
    def detail(attempt_id, comment: nil)
      attempt = load(PracticeAttempt.where(student_id: @student.id, id: attempt_id)).first or return nil
      serve = attempt.practice_serve
      instance = serve.item_instance
      revision = instance.item_revision
      shown = shown_of(serve)
      contested = contested_ids(serve.attempts.map(&:id))
      latest = latest_revisions([ revision.item_id ])
      row = row_of(attempt, contested, latest)
      { attempt: row.merge(grading: grading_of(attempt)),
        served: served_of(serve, shown),
        instance: instance_of(attempt, instance, shown),
        events: events_of(serve),
        tries: serve.attempts.sort_by(&:try_number).map { |a| row_of(a, contested, latest) },
        draft: draft_of(serve),
        refused_inputs: Teacher::RefusedTries.practice(@student, [ serve.id ])[serve.id].to_a.map { |text, at| { text: text, at: stamp(at) } },
        comments: comments_of(serve, instance, attempt, shown, comment) }
    end

    private

    # ---- which tries

    def matching(filters)
      scope = PracticeAttempt.where(student_id: @student.id)
                             .joins(practice_serve: [ { item_instance: { item_revision: { item: :subject } } }, { topic_revision: :lesson } ])
      scope = scope.where(subjects: { key: filters.subject }) if filters.subject
      scope = scope.where(lessons: { key: filters.topic }) if filters.topic
      scope = scope.where(practice_serves: { skill_key: filters.skill }) if filters.skill
      scope = scope.where(items: { key: filters.item }) if filters.item
      scope = scope.where(practice_serves: { id: filters.serve }) if filters.serve
      scope = scope.where("practice_attempts.answered_at >= ?", filters.since) if filters.since
      scope = scope.where("practice_attempts.answered_at <= ?", filters.till) if filters.till
      scope = scope.where(comment_clause(filters.comment)) if filters.comment
      scope
    end

    # The comment's serve; a comment with no serve, its instance (the student's serves of it); a comment with neither points at no try.
    def comment_clause(comment)
      if comment.practice_serve_id
        { practice_serves: { id: comment.practice_serve_id } }
      elsif comment.item_instance_id
        { practice_serves: { item_instance_id: comment.item_instance_id } }
      else
        "0 = 1"
      end
    end

    def load(scope)
      scope.preload(:gradings, practice_serve: [ :events, { attempts: :gradings, item_instance: { item_revision: { item: :subject } }, topic_revision: :lesson } ]).order(:id)
    end

    def contested_ids(ids) = PracticeContest.where(practice_attempt_id: ids).pluck(:practice_attempt_id).to_set

    def latest_revisions(item_ids) = ItemRevision.where(item_id: item_ids).group(:item_id).maximum(:id)

    # ---- one row

    def row_of(attempt, contested, latest)
      serve = attempt.practice_serve
      instance = serve.item_instance
      revision = instance.item_revision
      item = revision.item
      resolution = resolutions[attempt.id]
      grade = Instances.grade(attempt, spec_of(instance), contested_ids: contested, resolution: resolution)
      outcome = grade&.outcome || (attempt.latest_grading ? :not_a_try : :ungraded)
      codes = grade&.resolution ? grade.codes : JSON.parse(attempt.latest_grading&.error_codes_json || "[]")
      row = { id: attempt.id, at: stamp(attempt.answered_at), subject: item.subject.key, topic: serve.topic_revision.lesson.key, skill: serve.skill_key,
              item: item.key, revision_id: revision.id, superseded: revision.id != latest[item.id], item_instance_id: instance.id,
              practice_serve_id: serve.id, try_number: attempt.try_number, answer: attempt.raw, source: attempt.source, outcome: outcome.to_s,
              error_code: codes.first, error_codes: codes, hints_shown: attempt.hints_before, aided: attempt.aided,
              solution_requested: serve.events.any? { |e| e.kind == "solution_shown" && JSON.parse(e.payload_json || "{}")["reason"] == "requested" },
              seconds: seconds_of(attempt, serve) }
      row[:latest_revision_id] = latest[item.id] if row[:superseded]
      row[:outcome_before_contest] = Outcome.call(evidence_key: grade.key, aided: attempt.aided, near: grade.near).to_s if grade&.contested
      if grade&.resolution
        row[:outcome_before_resolution] = Instances.grade(attempt, spec_of(instance), contested_ids: contested)&.outcome.to_s
        row[:resolution] = grade.resolution.to_h_for_api
      end
      row[:counted] = false if grade && !counted_numbers(serve).include?(attempt.try_number)
      row
    end

    # The teacher's resolutions of this student's practice tries (D-352), {attempt id => Resolution}.
    def resolutions = @resolutions ||= Resolutions.for_student(@student.id)

    # The try numbers of a serve that count (Practice::ServeState.counted): a try after the one that closed the serve, which only a
    # resolution of an earlier try can cause, is listed with `counted: false`.
    def counted_numbers(serve)
      @counted ||= {}
      @counted[serve.id] ||= begin
        spec = spec_of(serve.item_instance)
        contested = contested_ids(serve.attempts.map(&:id))
        tries = serve.attempts.filter_map do |a|
          g = Instances.grade(a, spec, contested_ids: contested, resolution: resolutions[a.id]) or next
          ServeTry.new(a.try_number, g.outcome, g.contested)
        end
        ServeState.counted(tries).map(&:try_number)
      end
    end

    def spec_of(instance) = @specs[instance.id] ||= Grading::Spec.from_instance(instance)

    # The loader's seconds: from the serve (or the try before) to this try, capped.
    def seconds_of(attempt, serve)
      before = serve.attempts.select { |a| a.try_number < attempt.try_number }.max_by(&:try_number)
      (attempt.answered_at - (before&.answered_at || serve.created_at)).to_i.clamp(0, Rules::V6::TIME_CAP_SECONDS)
    end

    def stamp(time) = time.utc.iso8601

    # ---- the detail

    def grading_of(attempt)
      grading = attempt.latest_grading or return nil
      { verdict: grading.verdict, error_codes: JSON.parse(grading.error_codes_json || "[]"), form_violations: JSON.parse(grading.form_violations_json || "[]"),
        normalized: grading.normalized, method: grading[:method], grader: grading.grader, grader_version: grading.grader_version, source: grading.source,
        graded_at: stamp(grading.created_at) }.compact
    end

    # `reminders` (D-358): the «Ricorda» lines the page showed with this serve ({code, source: item|graph, at}); absent when none.
    # The serve and the display as the practice page drew it: the stored display re-keyed with the shown order the serve logged
    # (Diagnosis::Rekey.replay, as PracticeController does), through Items::Part, so it carries the same members the browser got.
    def served_of(serve, shown)
      instance = serve.item_instance
      revision = instance.item_revision
      accept = Items::Part.accepted(shown.body, instance.accept_json.present? ? JSON.parse(instance.accept_json) : [])
      item = Items::Part.new(subject: revision.item.subject, revision: revision).call(shown.body, shown.component, shown.display, answer: shown.answer, accept: accept)
      reminders = Reminder.shown(serve.id)[serve.id].map { |r| { code: r[:code], source: r[:source], at: stamp(r[:at]) } }
      { practice_serve_id: serve.id, reason: serve.reason, parent_serve_id: serve.parent_serve_id, error_code: serve.error_code, at: stamp(serve.created_at),
        rules_version: serve.rules_version, seed: serve.seed, shown_order: shown.shown_order, id_map: shown.id_map, item: item,
        reminders: reminders.presence }.compact
    end

    # The instance as the teacher reads it, and the hints with the ones this try had been shown.
    def instance_of(attempt, instance, shown)
      hints = Instances.hints(instance)
      Attempts::InstanceBlock.call(instance, shown, attempt.raw, JSON.parse(attempt.latest_grading&.error_codes_json || "[]"))
                             .merge(hints: hints.each_with_index.map { |text, i| { n: i + 1, hint_it: text, shown_before: i < attempt.hints_before } }, hints_total: hints.size)
    end

    def events_of(serve)
      serve.events.sort_by(&:id).map do |event|
        payload = JSON.parse(event.payload_json || "{}")
        { kind: event.kind, at: stamp(event.at), n: payload["n"], reason: payload["reason"], auto: payload["auto"] }.compact
      end
    end

    def draft_of(serve)
      draft = PracticeDraft.current_for(serve)
      draft && draft.raw != "" ? { raw: draft.raw, source: draft.source, at: stamp(draft.created_at) }.compact : nil
    end

    # The student's comments on this serve (a comment with no serve: on this instance), each with the row its anchor points at.
    def comments_of(serve, instance, attempt, shown, only)
      Attempts::Comments.list(@student, only, shown, attempt.raw) do |scope|
        scope.where("practice_serve_id = ? OR (practice_serve_id IS NULL AND item_instance_id = ?)", serve.id, instance.id)
      end
    end

    def anchor_row(anchor, attempt) = shown_of(attempt.practice_serve).anchor_row(anchor, attempt.raw)

    def shown_of(serve) = @shown[serve.id] ||= Attempts::Shown.new(serve)
  end
end
