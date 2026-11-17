module Attempts
  # The student's entry-test answers as the teacher bot reads them (D-346): every `attempts` row of context diagnosis (the sitting's own; the teacher's
  # preview and the warm-up are not the student's answers), not only the pending ones of Teacher::Corrections. The grading is the latest
  # `attempt_gradings` row as stored (verdict, evidence, error codes: an `undetermined` with the code invalid_answer is the answer the program could not read,
  # D-317); the exercise is the one the student saw (the serve-time shuffle of `item_served`, Diagnosis::ItemPresenter). Read-only.
  # `outcome` is the stored verdict (Grading::VERDICTS) or `ungraded`; `evidence` what the engine makes of it (C credit, W wrong, D «non lo so», pending, ungraded).
  class DiagnosisLog
    def initialize(student)
      @student = student
      @specs = {}
    end

    # [[id, answered_at]] of the answers that match the filters (all but the outcome), oldest first. No topic and no serve in the entry test.
    def index(filters)
      return [] if filters.topic || filters.serve

      scope = Attempt.where(student_id: @student.id, context: "diagnosis").where.not(served_event_id: nil)
                     .joins("INNER JOIN item_served ON item_served.diagnosis_event_id = attempts.served_event_id")
                     .joins(item_instance: { item_revision: { item: :subject } })
      scope = scope.where(subjects: { key: filters.subject }) if filters.subject
      scope = scope.where(items: { key: filters.item }) if filters.item
      scope = scope.where("item_served.skill_key = ?", filters.skill) if filters.skill
      scope = scope.where("attempts.answered_at >= ?", filters.since) if filters.since
      scope = scope.where("attempts.answered_at <= ?", filters.till) if filters.till
      scope = scope.where(comment_clause(filters.comment)) if filters.comment
      scope.order("attempts.id").pluck("attempts.id", "attempts.answered_at")
    end

    # The rows of these answers (ids), in id order; the anchor row of the comment filter is added to each.
    def rows(ids, filters = nil)
      attempts = load(ids)
      served = served_by_event(attempts)
      attempts = attempts.select { |a| served.key?(a.served_event_id) }
      context = context_of(attempts, served)
      attempts.map do |attempt|
        row = row_of(attempt, served.fetch(attempt.served_event_id), context)
        anchor = filters&.comment && Attempts::Shown.new(served.fetch(attempt.served_event_id)).anchor_row(filters.comment.anchor, attempt.raw)
        anchor ? row.merge(anchor_row: anchor) : row
      end
    end

    # One answer with the exercise as the student saw it; nil when the id is not this student's entry-test answer. comment: a Comment to keep alone.
    def detail(id, comment: nil)
      attempt = load([ id ]).first or return nil
      served = served_by_event([ attempt ])[attempt.served_event_id] or return nil
      context = context_of([ attempt ], { attempt.served_event_id => served })
      shown = Attempts::Shown.new(served)
      row = row_of(attempt, served, context)
      codes = JSON.parse(latest(attempt)&.error_codes_json || "[]")
      instance = Attempts::InstanceBlock.call(attempt.item_instance, shown, attempt.raw, codes).merge(answer_words: Diagnosis::AnswerText.call(attempt, served))
      { attempt: row.merge(gradings: attempt.gradings.map { |g| grading_of(g) }), served: served_of(served, row, shown), instance: instance,
        refused_inputs: Teacher::RefusedTries.diagnosis(@student, [ served.diagnosis_event_id ])[served.diagnosis_event_id].to_a.map { |text| { text: text } },
        comments: Attempts::Comments.list(@student, comment, shown, attempt.raw) { |scope| scope.where("served_event_id = ? OR (served_event_id IS NULL AND item_instance_id = ?)", served.diagnosis_event_id, attempt.item_instance_id) } }
    end

    private

    # The comment's served event; with none, its item instance; a comment with neither points at no answer.
    def comment_clause(comment)
      if comment.served_event_id
        { attempts: { served_event_id: comment.served_event_id } }
      elsif comment.item_instance_id
        { attempts: { item_instance_id: comment.item_instance_id } }
      else
        "0 = 1"
      end
    end

    def load(ids)
      Attempt.where(student_id: @student.id, context: "diagnosis", id: ids).where.not(served_event_id: nil)
             .preload(:gradings, item_instance: { item_revision: { item: :subject } }).order(:id).to_a
    end

    def served_by_event(attempts)
      ItemServed.where(diagnosis_event_id: attempts.map(&:served_event_id)).includes(item_instance: { item_revision: { item: :subject } }).index_by(&:diagnosis_event_id)
    end

    # The serve events, the sitting starts of their runs and the latest revision of each item.
    Context = Data.define(:events, :starts, :latest)

    def context_of(attempts, served)
      events = DiagnosisEvent.where(id: served.keys).index_by(&:id)
      starts = DiagnosisEvent.where(diagnosis_run_id: events.values.map(&:diagnosis_run_id).uniq, kind: "sitting_started").pluck(:diagnosis_run_id, :seq).group_by(&:first)
      Context.new(events, starts, ItemRevision.where(item_id: attempts.map { |a| a.item_instance.item_revision.item_id }.uniq).group(:item_id).maximum(:id))
    end

    def latest(attempt) = attempt.gradings.max_by(&:seq)

    def row_of(attempt, served, context)
      instance = attempt.item_instance
      revision = instance.item_revision
      item = revision.item
      event = context.events.fetch(served.diagnosis_event_id)
      grading = latest(attempt)
      codes = JSON.parse(grading&.error_codes_json || "[]")
      evidence = Grading::Evidence.for_grading(grading, spec_of(instance))
      cap = JSON.parse(revision.body_json)["kind"] == "testlet" ? Diagnosis::Rules::V1::TESTLET_CAP_SECONDS : Diagnosis::Rules::V1::ITEM_CAP_SECONDS
      row = { id: attempt.id, at: attempt.answered_at.utc.iso8601, subject: item.subject.key, skill: served.skill_key, item: item.key, revision_id: revision.id,
              superseded: revision.id != context.latest[item.id], item_instance_id: instance.id, run_id: event.diagnosis_run_id,
              sitting: context.starts.fetch(event.diagnosis_run_id, []).count { |_, seq| seq <= event.seq }, served_event_id: event.id, answer: attempt.raw,
              source: attempt.source, outcome: grading&.verdict || "ungraded", evidence: evidence.to_s, error_code: codes.first, error_codes: codes,
              grader: grading&.grader, seconds: (attempt.answered_at - event.at).to_i.clamp(0, cap) }
      row[:latest_revision_id] = context.latest[item.id] if row[:superseded]
      row[:unreadable] = true if codes.include?(Grading::Recorder::INVALID_ANSWER_CODE)
      row
    end

    def spec_of(instance) = @specs[instance.id] ||= Grading::Spec.from_instance(instance)

    def grading_of(grading)
      { seq: grading.seq, verdict: grading.verdict, error_codes: JSON.parse(grading.error_codes_json || "[]"), form_violations: JSON.parse(grading.form_violations_json || "[]"),
        normalized: grading.normalized, method: grading[:method], grader: grading.grader, grader_version: grading.grader_version, source: grading.source,
        graded_at: grading.created_at.utc.iso8601 }.compact
    end

    # The serve and the display as the sitting drew it (Diagnosis::ItemPresenter over the logged shown order, the same call the sitting page makes).
    def served_of(served, row, shown)
      event = DiagnosisEvent.find(served.diagnosis_event_id)
      item = Diagnosis::ItemPresenter.new(served: served, number: 1, subject: served.item_instance.item_revision.item.subject).as_json[:item]
      { served_event_id: event.id, run_id: row[:run_id], sitting: row[:sitting], at: event.at.utc.iso8601, reason: JSON.parse(event.payload_json || "{}")["reason"],
        skill: served.skill_key, formula_sheet_available: served.formula_sheet_available, shown_order: shown.shown_order, id_map: shown.id_map, item: item }.compact
    end
  end
end
