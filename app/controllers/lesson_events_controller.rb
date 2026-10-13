# What the student did in a lesson/2 (A11): a batch of at most 20 events, card_seen, and the events of a free page (page_opened, page_event, page_failed; D-290). Idempotent on
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
    return { kind: kind, card: card, client_event_id: id, payload: {} } unless LessonEvent::PAGE_KINDS.include?(kind)

    page_payload(event, kind)&.then { |payload| { kind: kind, card: card, client_event_id: id, payload: payload } }
  end

  # What a free page event carries (D-290): the block of the card, for page_event the kind the page named (no outcome) and at most
  # 1 KB of its data, for page_failed the limit that tripped. Anything else is refused.
  def page_payload(event, kind)
    block = event["block"]
    return nil unless block.is_a?(Integer) && block.between?(1, 8)

    payload = { "block" => block }
    case kind
    when "page_event"
      return nil unless LessonEvent::PAGE_EVENT_KINDS.include?(event["page_event"].to_s)

      data = event["data"].is_a?(Hash) ? event["data"] : {}
      return nil if JSON.generate(data).bytesize > 1024

      payload.merge!("kind" => event["page_event"], "data" => data)
    when "page_failed"
      return nil unless LessonEvent::PAGE_LIMITS.include?(event["limit"].to_s)

      payload["limit"] = event["limit"]
    end
    payload
  end

  def write(revision, event)
    return if LessonEvent.exists?(student: acting_student, client_event_id: event[:client_event_id])
    # one card_seen or page_opened per card per window; the other page events are all kept (the page's own doings, capped by the bridge)
    if %w[card_seen page_opened].include?(event[:kind]) &&
       LessonEvent.where(student: acting_student, lesson_revision: revision, kind: event[:kind], card: event[:card]).where("at > ?", LessonEvent::SEEN_WINDOW.ago).exists?
      return
    end

    now = Time.current
    LessonEvent.create!(student: acting_student, topic_revision: @topic.topic_revision, lesson_revision: revision, kind: event[:kind], card: event[:card],
                        payload_json: JSON.generate(event[:payload]), client_event_id: event[:client_event_id], at: now, created_at: now)
  rescue ActiveRecord::RecordNotUnique
    nil # the same event arrived twice at once
  end

  def invalid = render(json: { status: "invalid" }, status: :unprocessable_entity)
end
