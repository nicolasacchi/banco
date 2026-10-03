module Diagnosis
  # Takes one answer from the browser and records it (X-01). The browser posts
  # {served_event_id, client_attempt_id, raw, source}; the reply carries a status
  # and, for an invalid answer, a message for the student, and never an outcome.
  #
  # The grading runs first, outside any transaction (the expression worker can
  # take 2 s and SQLite would hold the write lock all that time). Then one short
  # transaction appends the attempt and its grading row. A repeated
  # client_attempt_id, or a second answer to a serve that already has one, is
  # answered "recorded" without writing again, so the browser's outbox may retry
  # as often as it needs to.
  class AnswerRecorder
    Outcome = Data.define(:status, :message_it)

    SOURCES = %w[text mathlive button].freeze
    MAX_RAW_BYTES = 20_000

    def initialize(student:, context:, clock: Clock.new)
      @student = student
      @context = context
      @clock = clock
    end

    def call(served_event_id:, client_attempt_id:, raw:, source:)
      client_id = client_attempt_id.to_s
      return gone unless raw.is_a?(String) && client_id.match?(/\A[A-Za-z0-9_-]{8,64}\z/)
      return invalid(Grading::Result::MESSAGES_IT["empty"]) if raw.strip.empty?
      return invalid(Grading::Result::MESSAGES_IT["unparseable"]) if raw.bytesize > MAX_RAW_BYTES
      return recorded if Attempt.exists?(client_attempt_id: client_id)

      event = DiagnosisEvent.joins(:diagnosis_run)
                            .find_by(id: served_event_id, kind: "item_served", diagnosis_runs: { student_id: @student.id })
      return gone unless event
      return recorded if Attempt.exists?(served_event_id: event.id)

      served = ItemServed.includes(item_instance: :item_revision).find_by!(diagnosis_event_id: event.id)
      instance = served.item_instance
      source = SOURCES.include?(source.to_s) ? source.to_s : "text"
      id_map = served.id_map_json.present? ? JSON.parse(served.id_map_json) : nil

      begin
        result = Grading.grade(instance, raw, source: source, id_map: id_map)
      rescue Grading::Expression::Unavailable
        result = nil # no verdict is written; GradePendingJob retries (A-01)
      end
      if result&.invalid?
        AppEvent.create!(kind: "invalid_input", student: @student,
                         payload_json: { served_event_id: event.id, code: result.invalid_code }.to_json)
        return invalid(result.message_it)
      end

      attempt = append(event, instance, client_id, raw, source, result)
      Grading::Recorder.schedule_retry(attempt) if result.nil?
      recorded
    rescue ActiveRecord::RecordNotUnique
      recorded # the same answer arrived twice at once
    end

    private

    def append(event, instance, client_id, raw, source, result)
      Attempt.transaction do
        attempt = Attempt.create!(student: @student, context: @context, served_event: event, client_attempt_id: client_id,
                                  item_instance: instance, raw: raw, source: source, answered_at: @clock.now)
        Grading::Recorder.append(attempt, result) if result
        attempt
      end
    end

    def recorded = Outcome.new("recorded", nil)
    def invalid(message) = Outcome.new("invalid", message)
    def gone = Outcome.new("invalid", I18n.t("sitting.gone"))
  end
end
