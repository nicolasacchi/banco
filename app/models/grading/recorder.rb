module Grading
  # Appends gradings to the ledger. Grading is done before this runs, outside any
  # transaction; the append is one short transaction (X-01). A grading is never
  # updated: a retry adds a row with source retry, and the latest row wins.
  module Recorder
    # Wait times of GradePendingJob after a worker failure (A-01): the first retry
    # 30 s after the failed grading, then 2 minutes, then 10 minutes.
    RETRY_WAITS = [ 30.seconds, 2.minutes, 10.minutes ].freeze
    UNAVAILABLE_CODE = "grader_unavailable".freeze
    INVALID_ANSWER_CODE = "invalid_answer".freeze

    module_function

    # Appends one attempt_gradings row for +attempt+. invalid results are not
    # attempts and are refused.
    #
    # model: the grading table. AttemptGrading (the diagnosis, the default) or PracticeGrading (the
    # practice ledger, A7); the attempt is a PracticeAttempt for the latter.
    def append(attempt, result, source: "sync", model: AttemptGrading)
      raise ArgumentError, "an invalid answer is not an attempt, nothing to record" if result.invalid?

      owner = model == PracticeGrading ? :practice_attempt : :attempt
      model.transaction do
        seq = model.where("#{owner}_id": attempt.id).maximum(:seq).to_i + 1
        model.create!(result.to_attributes.merge(owner => attempt, seq: seq, source: source))
      end
    end

    # Retry flow: grade the attempt (no transaction open), then append. Raises
    # Grading::Expression::Unavailable when the worker does not answer; nothing is
    # written then.
    def grade_attempt(attempt, source: "retry", id_map: nil)
      id_map ||= logged_id_map(attempt)
      result = Grading.grade(attempt.item_instance, attempt.raw, source: attempt.source, id_map: id_map)
      return append(attempt, result, source: source) unless result.invalid?

      # The attempt exists already (the first grading could not run) and the student
      # was told it was recorded: an answer the checker now calls invalid settles
      # as a terminal row for the teacher, never as silence.
      append(attempt, Result.new(verdict: "undetermined", grader: result.grader, error_codes: [ INVALID_ANSWER_CODE ], reason: result.invalid_code),
             source: source)
    end

    # The shuffle the serve layer logged for the attempt's serve (X-01), so a retry
    # undoes it like the first grading would have.
    def logged_id_map(attempt)
      json = ItemServed.find_by(diagnosis_event_id: attempt.served_event_id)&.id_map_json
      json.present? ? JSON.parse(json) : nil
    end

    # After the last retry failed: the attempt goes to the teacher as
    # verdict_pending. The row says so; it counts neither way.
    def give_up(attempt)
      append(attempt, Result.new(verdict: "undetermined", grader: Expression::GRADER, error_codes: [ UNAVAILABLE_CODE ]),
             source: "retry")
    end

    # An attempt waits for grading when it has no row, or its latest row is the
    # give-up marker (a later retry may still settle it).
    def pending?(attempt)
      latest = attempt.gradings.last
      latest.nil? || JSON.parse(latest.error_codes_json || "[]").include?(UNAVAILABLE_CODE)
    end

    # Schedules the first retry of an attempt the worker could not grade.
    def schedule_retry(attempt)
      GradePendingJob.set(wait: RETRY_WAITS.first).perform_later(attempt.id)
    end
  end
end
