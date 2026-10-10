# What the student did in a lesson/2 (A11): a batch of at most 20 events, today only card_seen. Idempotent on
# client_event_id; one card_seen per card per 10 minutes is kept (the others are accepted and dropped). Students only
# (official and trial); guests and the teacher get 403 and no row; the teacher's preview posts nothing. Nothing here
# counts for a skill state.
class LessonEventsController < ApplicationController
  include StudentCourse

  before_action :load_topic_for_json
  before_action { response.headers["Cache-Control"] = "no-store" }

  MAX_BATCH = 20

  def create
    revision = @topic.lesson_revision
    return json_not_found unless revision.lesson2?

    events = request.request_parameters["events"]
    return invalid unless events.is_a?(Array) && events.size.between?(1, MAX_BATCH) && events.all?(Hash)

    cards = revision.body["cards"].map { |c| c["n"] }
    parsed = events.map { |e| parse(e, cards) }
    return invalid if parsed.any?(&:nil?)

    parsed.each { |event| write(revision, event) }
    render json: { ok: true, accepted: parsed.size }
  end

  private

  def load_topic_for_json
    @subject_view, @topic = course_view.find_topic(params[:topic])
    json_not_found unless @topic
  end

  def parse(event, cards)
    kind = event["kind"].to_s
    id = event["client_event_id"].to_s
    card = event["card"]
    return nil unless LessonEvent::WRITTEN_BY_BATCH.include?(kind) && id.match?(LessonEvent::ID_FORMAT)
    return nil unless card.is_a?(Integer) && cards.include?(card)

    { kind: kind, card: card, client_event_id: id }
  end

  def write(revision, event)
    return if LessonEvent.exists?(student: acting_student, client_event_id: event[:client_event_id])
    return if LessonEvent.where(student: acting_student, lesson_revision: revision, kind: event[:kind], card: event[:card]).where("at > ?", LessonEvent::SEEN_WINDOW.ago).exists?

    now = Time.current
    LessonEvent.create!(student: acting_student, topic_revision: @topic.topic_revision, lesson_revision: revision, kind: event[:kind], card: event[:card],
                        payload_json: "{}", client_event_id: event[:client_event_id], at: now, created_at: now)
  rescue ActiveRecord::RecordNotUnique
    nil # the same event arrived twice at once
  end

  def invalid = render(json: { status: "invalid" }, status: :unprocessable_entity)
end
