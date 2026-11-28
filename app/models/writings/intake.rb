module Writings
  # The one writer of `writing_submissions` (D-407): the text a student sends on a topic that pins a writing task, checked against what THIS student is
  # shown. The topic must be one his course shows him now, the item revision one of the writing tasks of the topic revision he is shown, and the topic
  # revision, the item and the student are derived here, never taken from the browser. A text changes nothing else: no attempt, no serve, no skill state,
  # nothing the practice engine, a gate or a grade reads (a writing task is not an exercise).
  #
  #   Writings::Intake.call(student: s, course_view: view, topic: key, params: params)  # => Result(status:, submission:, error:)
  #
  # params: `client_writing_id` (8 to 64 of A-Za-z0-9_-), `item_revision_id` (the task as he was shown it) and `text` (1 to WritingSubmission::TEXT_MAX
  # characters). status: :recorded (also a repeat of the same client_writing_id by the same student) or :invalid (final: the page says so and keeps the
  # words). A new text is refused while his latest text of the same task waits for the teacher (:pending): he sends again after the correction.
  # The student is a student (official or trial) or the teacher's preview student, whose row the controller names; a guest and nobody never get here.
  class Intake
    Result = Struct.new(:status, :submission, :error, keyword_init: true)

    ID_FORMAT = /\A[A-Za-z0-9_-]{8,64}\z/

    class Invalid < StandardError; end

    def self.call(**args) = new(**args).call

    def initialize(student:, course_view:, topic:, params:)
      @student = student
      @view = course_view
      @topic_key = topic.to_s
      @params = params
    end

    def call
      raise Invalid, "not a student" unless %w[student preview].include?(@student.kind)

      id = @params[:client_writing_id].to_s
      raise Invalid, "client_writing_id" unless id.match?(ID_FORMAT)

      existing = WritingSubmission.find_by(client_writing_id: id)
      if existing
        return Result.new(status: :recorded, submission: existing) if existing.student_id == @student.id

        raise Invalid, "client_writing_id"
      end

      topic = @view.find_topic(@topic_key)&.last or raise Invalid, "topic"
      revision = task(topic)
      text = WritingSubmission.clean(@params[:text])
      raise Invalid, "empty" if text.empty?
      raise Invalid, "too_long" if text.length > WritingSubmission::TEXT_MAX
      raise Invalid, "pending" if waiting?(revision)

      row = { student: @student, topic_revision: topic.topic_revision, item_revision: revision, client_writing_id: id, text: text,
              word_count: WritingSubmission.count_words(text), created_at: Time.current }
      begin
        submission = WritingSubmission.create!(row)
      rescue ActiveRecord::RecordNotUnique
        submission = WritingSubmission.find_by!(client_writing_id: id, student_id: @student.id)
      end
      Result.new(status: :recorded, submission: submission)
    rescue Invalid => e
      Result.new(status: :invalid, error: e.message)
    end

    private

    # The item revision he was shown as a writing task of this topic revision.
    def task(topic)
      wanted = Integer(@params[:item_revision_id].to_s, 10, exception: false)
      pinned = topic.topic_revision.writing_pins.any? { |pin| pin["revision"] == wanted }
      (pinned && ItemRevision.find_by(id: wanted)) or raise Invalid, "item_revision_id"
    end

    # His latest text of this task (any revision of the item) has no correction yet.
    def waiting?(revision)
      latest = WritingSubmission.of_student(@student).of_item(revision.item).order(:id).last
      latest && !Writings::Corrections.for([ latest ]).key?(latest.id)
    end
  end
end
