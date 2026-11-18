module Ratings
  # The one writer of `ratings` (D-365): what a student says of an exercise or a lesson, checked against what that student was shown. Every id
  # is looked up for THIS student and must fit what he can open now; the key, the revision, the subject and the topic the row keeps are derived
  # here, never taken from the browser. A rating writes nothing else: no attempt, no serve, no event, nothing the engine or a grade reads.
  #
  #   Ratings::Intake.call(student: s, course_view: view, params: params, language: "it")  # => Result(status:, rating:, error:)
  #
  # An exercise: params `kind: "item"` and `serve_id`, the serve must be the student's own, on a topic he can see, and OVER (right, solution shown
  # or the tries used up: `ServeState` closed). A lesson: `kind: "lesson"`, `topic` (the key) and `lesson_revision_id`, which must be the revision
  # the student reads on that topic. `stars` (1 to 5) and `text_it` (up to Rating::TEXT_MAX) are both optional, one at least.
  #
  # status: :recorded (also a repeat of the same client_rating_id by the same student) or :invalid (final: the page shows the error). The
  # teacher's preview student and any non-student never get here (the route is the student's, the controller refuses the rest); repeated below.
  class Intake
    Result = Struct.new(:status, :rating, :error, keyword_init: true)

    ID_FORMAT = /\A[A-Za-z0-9_-]{8,64}\z/

    class Invalid < StandardError; end

    def self.call(**args) = new(**args).call

    def initialize(student:, course_view:, params:, language:)
      @student = student
      @view = course_view
      @params = params
      @language = language.to_s
    end

    def call
      raise Invalid, "not a student" unless @student.kind == "student"

      id = @params[:client_rating_id].to_s
      raise Invalid, "client_rating_id" unless id.match?(ID_FORMAT)

      existing = Rating.find_by(client_rating_id: id)
      if existing
        return Result.new(status: :recorded, rating: existing) if existing.student_id == @student.id

        raise Invalid, "client_rating_id"
      end

      row = say.merge(target).merge(student: @student, client_rating_id: id, trial: @student.trial?, language: language, created_at: Time.current)
      begin
        rating = Rating.create!(row)
      rescue ActiveRecord::RecordNotUnique
        rating = Rating.find_by!(client_rating_id: id, student_id: @student.id)
      end
      Result.new(status: :recorded, rating: rating)
    rescue Invalid => e
      Result.new(status: :invalid, error: e.message)
    end

    private

    def language = Rating::LANGUAGES.include?(@language) ? @language : raise(Invalid, "language")

    # The stars and the words: both optional, one at least.
    def say
      raw = @params[:stars]
      none = raw.nil? || raw.to_s.strip.empty?
      stars = none ? nil : Integer(raw.to_s, 10, exception: false)
      raise Invalid, "stars" unless none || Rating::STARS.cover?(stars)

      text = @params[:text_it].to_s.gsub("\r\n", "\n").strip
      raise Invalid, "text_it" if text.length > Rating::TEXT_MAX
      raise Invalid, "empty" if stars.nil? && text.empty?

      { stars: stars, text_it: text.presence }
    end

    def target
      case @params[:kind].to_s
      when "item" then item_target
      when "lesson" then lesson_target
      else raise Invalid, "kind"
      end
    end

    def item_target
      serve = PracticeServe.includes(:events, attempts: :gradings, item_instance: { item_revision: :item }).find_by(id: @params[:serve_id].to_s.to_i, student_id: @student.id)
      raise Invalid, "serve_id" unless serve && visible?(serve.topic_revision_id)
      raise Invalid, "not_over" unless Practice::Loader.status_of(serve, now: Time.current).state == :closed

      revision = serve.item_instance.item_revision
      { target_kind: "item", target_key: revision.item.key, item_revision: revision, practice_serve: serve, subject: revision.item.subject, topic_revision_id: serve.topic_revision_id }
    end

    def lesson_target
      subject_view, topic = @view.find_topic(@params[:topic].to_s)
      raise Invalid, "topic" unless topic

      revision = topic.topic_revision.lesson_revision
      raise Invalid, "lesson_revision_id" unless @params[:lesson_revision_id].to_s == revision.id.to_s

      { target_kind: "lesson", target_key: revision.lesson.key, lesson_revision: revision, subject: subject_view.subject, topic_revision: topic.topic_revision }
    end

    # The serve's topic is one this student's course shows him now (an official student loses the pages when the release is withdrawn).
    def visible?(topic_revision_id)
      @view.subjects.any? { |sv| sv.topics.any? { |t| t.topic_revision.id == topic_revision_id } }
    end
  end
end
