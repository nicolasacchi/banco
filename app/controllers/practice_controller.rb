# Practice on one skill of a topic (A9): the page, and the JSON of the serve, the answer, the hint and the
# solution. The server grades (Grading, the same code as the diagnosis) and chooses every sentence from
# approved stored text (firm rule 1). The browser is told only what Practice::Payload and Items::Part allow:
# never the key, the error values, a hint not asked for, or a solution before the state machine sends it.
class PracticeController < ApplicationController
  include StudentCourse

  before_action :load_topic, only: :show

  # GET /topics/:topic/practice/:skill
  def show
    @skill = params[:skill].to_s
    return page_not_found unless @topic.skills.include?(@skill)

    @skill_label = course_view.label(@skill)
    @state = course_view.state(@skill)
  end

  # POST /practice/serves {topic, skill, follow, item, advance}: item is an item key (that exercise), advance is «Avanti» and «Salta» (the next
  # exercise, the open ones kept open); with neither, the exercise to resume (D-337). When every skill of the topic is demonstrated (D-366) the
  # server serves nothing on its own: the answer is the closing screen of the topic; only a chosen exercise (`item`, the list) is served.
  def serve
    subject_view, topic = course_view.find_topic(params[:topic])
    skill = params[:skill].to_s
    return json_not_found unless topic && topic.skills.include?(skill)
    return render(json: topic_done_body(subject_view, topic, skill)) if item_param.nil? && Practice::Today.done?(topic, course_view.states)

    choice = Practice::Selector.next(student: acting_student, topic_revision: topic.topic_revision, skill: skill, follow: follow_param,
                                     item: item_param, advance: ActiveModel::Type::Boolean.new.cast(params[:advance]), now: Time.current)
    return render(json: exhausted_body(skill)) if choice == Practice::Selector::EXHAUSTED

    render json: serve_body(choice.serve, topic, chosen: item_param.present?)
  rescue Practice::Selector::BadFollow
    render json: { status: "bad_follow" }, status: :unprocessable_entity
  rescue Practice::Selector::NotPinned
    json_not_found
  end

  # POST /practice/answers {serve_id, client_attempt_id, raw, source}
  def answer
    return json_not_found unless own_visible_serve?(params[:serve_id])

    result = Practice::AnswerRecorder.new(student: acting_student).call(
      serve_id: params[:serve_id], client_attempt_id: params[:client_attempt_id], raw: params[:raw], source: params[:source]
    )
    render json: result.body, status: result.http
  end

  # POST /practice/serves/:serve_id/draft {raw, source}: what the student has typed, saved as a row. Only an open serve of the student's own.
  def draft
    return json_not_found unless own_visible_serve?(params[:serve_id])

    raw = params[:raw]
    source = params[:source]
    return render(json: { status: "bad_draft" }, status: :unprocessable_entity) unless raw.is_a?(String) && (source.nil? || source.is_a?(String))

    PracticeDraft.transaction do
      serve = PracticeServe.includes(:events, attempts: :gradings, item_instance: { item_revision: :item }).find(params[:serve_id].to_i)
      next render(json: { status: "closed" }, status: :conflict) unless Practice::Loader.status_of(serve, now: Time.current).state == :open
      next render(json: { status: "too_long" }, status: :unprocessable_entity) if raw.length > PracticeDraft::MAX_RAW
      next render(json: { status: "unchanged" }) if raw == (PracticeDraft.current_for(serve)&.raw || "")

      PracticeDraft.create!(student: acting_student, practice_serve: serve, raw: raw, source: source.presence&.first(PracticeDraft::MAX_SOURCE))
      render json: { status: "saved" }
    end
  end

  # GET /practice/exercises?topic=KEY: the topic's exercises with what each one is for this student (Practice::Exercises).
  def exercises
    subject_view, topic = course_view.find_topic(params[:topic])
    return json_not_found unless topic

    render json: Practice::Exercises.call(topic: topic, subject: subject_view.subject, student: acting_student, view: course_view, root: student_root)
  end

  # POST /practice/serves/:serve_id/hint {n}
  def hint
    return json_not_found unless own_visible_serve?(params[:serve_id])

    result = Practice::Actions.new(student: acting_student).hint(serve_id: params[:serve_id], n: Integer(params[:n].to_s, 10, exception: false))
    render json: result.body, status: result.http
  end

  # POST /practice/serves/:serve_id/solution
  def solution
    return json_not_found unless own_visible_serve?(params[:serve_id])

    result = Practice::Actions.new(student: acting_student).solution(serve_id: params[:serve_id])
    render json: result.body, status: result.http
  end

  # POST /practice/serves/:serve_id/contest: «Fai controllare» (D-339), the latest wrong try goes to the teacher with a comment; the solution comes back.
  def contest
    return json_not_found unless own_visible_serve?(params[:serve_id])

    result = Practice::Contest.new(student: acting_student, course_view: course_view).call(serve_id: params[:serve_id])
    render json: result.body, status: result.http
  end

  private

  def item_param = params[:item].is_a?(String) ? params[:item].presence : nil

  def follow_param
    raw = params[:follow]
    return nil unless raw.respond_to?(:permit)

    raw.permit(:serve_id, :kind).to_h.symbolize_keys
  end

  # A serve of this student, on a topic this student can see now (an official student loses the pages when the
  # teacher withdraws the release).
  def own_visible_serve?(id)
    serve = PracticeServe.find_by(id: id.to_s.to_i, student_id: acting_student.id) or return false
    course_view.subjects.any? { |sv| sv.topics.any? { |t| t.topic_revision.id == serve.topic_revision_id } }
  end

  # D-348: no exercise of the skill is unseen and none is open: nothing is served and the page says so (the fact is recorded by the selector).
  def exhausted_body(skill)
    { type: "exhausted", message_it: I18n.t("practice.exhausted"), note_it: I18n.t("practice.exhausted_note"),
      skill: skill_block(skill, course_view.state(skill)) }
  end

  # D-366: the topic is done (Practice::Today.done?: every skill demonstrated or consolidated, from the practice or from the entry test). The closing
  # screen speaks of this topic only: its title, the topic Oggi proposes next for the subject (Course::StudentView#next_topic, the one `banco next`
  # gives; nil when none is left, and then there is no offer) and the way back to Oggi. Addresses come from here (student_root), never from a script.
  # D-373: the topic's schema (D-372) is open by definition, since the topic is done: `schema` is in the reply only when the topic has one (its
  # lesson has a summary), with the address built by `spath` (the preview's own in the preview).
  def topic_done_body(subject_view, topic, skill)
    pick = course_view.next_topic(subject_view)
    { type: "topic_done", skill: skill_block(skill, course_view.state(skill)), title_it: I18n.t("practice.topic_done.title"),
      offer_it: pick && I18n.t("practice.topic_done.offer"),
      next: pick && { topic: pick.topic.key, title_it: pick.topic.title_it, label_it: I18n.t("practice.topic_done.next"), url: "#{student_root}/topics/#{pick.topic.key}" },
      today: { label_it: I18n.t("practice.topic_done.today"), url: "#{student_root}/today" } }.tap do |body|
      body[:schema] = { label_it: I18n.t("practice.topic_done.schema"), url: helpers.schema_href(topic.key) } if Course::Schemas.new(course_view).exists?(topic)
    end
  end

  # A9.3: the open serve as the browser sees it. chosen: the student picked this exercise from the list (no line saying it is a similar one).
  def serve_body(serve, topic, chosen: false)
    serve = PracticeServe.includes(:events, attempts: :gradings, item_instance: { item_revision: :item }).find(serve.id)
    status = Practice::Loader.status_of(serve, now: Time.current)
    instance = serve.item_instance
    hints = Practice::Instances.hints(instance)
    state = course_view.state(serve.skill_key)
    {
      type: "item", serve_id: serve.id, reason: serve.reason, reason_it: reason_it(serve, chosen), reminder_it: reminder_it(serve),
      status: status.state.to_s, next_try_number: status.next_try_number,
      skill: skill_block(serve.skill_key, state),
      hints: { total: hints.size, shown: hints.first(status.hints_shown).each_with_index.map { |text, i| { n: i + 1, hint_it: text } } },
      item: item_part(serve, instance),
      draft: draft_block(serve), exercise: exercise_block(serve, topic), rating: rating_block(serve)
    }
  end

  # The line above the exercise: why it was given. The same item as the serve before (the rule keeps the student on it until it has the right
  # tries it needs) says so in its own words, unless the student chose it (D-348).
  def reason_it(serve, chosen)
    return Practice::Messages.same_item_it if !chosen && %w[next after_solution].include?(serve.reason) && Practice::Repeat.call(serve)

    Practice::Messages.reason_it(serve.reason)
  end

  # D-358: «Ricorda: …», the item's own message for the typical error this student made lately in the skill, when this exercise declares it; nil
  # otherwise. Not a hint (no counter, no try, no state); recorded as an app event (Practice::Reminder). Only the sentence leaves the server.
  def reminder_it(serve)
    Practice::Reminder.call(serve, student: acting_student, description: ->(code) { course_view.error_description(serve.skill_key, code) })&.text_it
  end

  # His latest rating of this exercise (D-365), for the box that opens when it is over; nil when he has given none.
  def rating_block(serve)
    rating = Rating.latest_for(acting_student, "item", serve.item_instance.item_revision.item.key)
    rating && { stars: rating.stars, text_it: rating.text_it }
  end

  # What the student typed in this serve and has not answered yet; nil when there is nothing (or a try came after it).
  def draft_block(serve)
    row = PracticeDraft.current_for(serve)
    row && row.raw != "" ? { raw: row.raw, source: row.source } : nil
  end

  # The place of the serve's exercise in its skill: the item key and its 1-based position in the pin order of the topic the student sees (n is
  # nil when the item is no longer pinned there: an open serve of an older revision).
  def exercise_block(serve, topic)
    key = serve.item_instance.item_revision.item.key
    pins = topic.topic_revision.body["practice"].find { |p| p["skill"] == serve.skill_key }&.dig("items") || []
    position = pins.index { |pin| pin["item"] == key }
    { skill: serve.skill_key, item: key, n: position && position + 1 }
  end

  def skill_block(key, state)
    { key: key, label_it: course_view.label(key), state: state.state, state_it: Practice::Messages.state_it(state.state),
      why_it: Practice::Messages.why_it(state.why), clean: Practice::Messages.clean_count(state.why) }
  end

  def item_part(serve, instance)
    body = JSON.parse(instance.item_revision.body_json)
    stored = JSON.parse(instance.display_json)
    shown_order = serve.shown_order_json ? JSON.parse(serve.shown_order_json) : {}
    display = Diagnosis::Rekey.replay(display: stored, component: body["component"], shown_order: shown_order)
    Items::Part.new(subject: instance.item_revision.item.subject, expression_input: expression_input,
                    revision: instance.item_revision).call(body, body["component"], display, answer: JSON.parse(instance.answer_json),
                                                           accept: Items::Part.accepted(body, instance.accept_json.present? ? JSON.parse(instance.accept_json) : []))
  end

  def expression_input
    AppEvent.where(student_id: acting_student.id, kind: "warmup_editor_fallback").exists? ? "text" : "mathlive"
  end
end
