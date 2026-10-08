# Practice on one skill of a topic (A9): the page, and the JSON of the serve, the answer, the hint and the
# solution. The server grades (Grading, the same code as the diagnosis) and chooses every sentence from
# approved stored text (firm rule 1). The browser is told only what Practice::Payload and Items::Part allow:
# never the key, the error values, a hint not asked for, or a solution before the state machine sends it.
class PracticeController < ApplicationController
  include StudentCourse

  before_action :no_store, except: :show
  before_action :load_topic, only: :show

  # GET /topics/:topic/practice/:skill
  def show
    @skill = params[:skill].to_s
    return head(:not_found) unless @topic.skills.include?(@skill)

    @skill_label = course_view.label(@skill)
    @state = course_view.state(@skill)
  end

  # POST /practice/serves {topic, skill, follow}
  def serve
    _, topic = course_view.find_topic(params[:topic])
    skill = params[:skill].to_s
    return json_not_found unless topic && topic.skills.include?(skill)

    choice = Practice::Selector.next(student: acting_student, topic_revision: topic.topic_revision, skill: skill, follow: follow_param, now: Time.current)
    render json: serve_body(choice.serve, topic)
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

  private

  def follow_param
    raw = params[:follow]
    return nil unless raw.respond_to?(:permit)

    raw.permit(:serve_id, :kind).to_h.symbolize_keys
  end

  # A serve of this student, on a topic this student can see now (an official student loses the pages when the
  # teacher withdraws the release).
  def own_visible_serve?(id)
    serve = PracticeServe.find_by(id: id.to_s.to_i, student_id: acting_student.id) or return false
    subject_visible?(serve.skill_key.split(".").first)
  end

  # A9.3: the open serve as the browser sees it.
  def serve_body(serve, topic)
    serve = PracticeServe.includes(:events, attempts: :gradings, item_instance: { item_revision: :item }).find(serve.id)
    status = Practice::Loader.status_of(serve, now: Time.current)
    instance = serve.item_instance
    hints = Practice::Instances.hints(instance)
    state = course_view.state(serve.skill_key)
    {
      type: "item", serve_id: serve.id, reason: serve.reason, reason_it: Practice::Messages.reason_it(serve.reason),
      status: status.state.to_s, next_try_number: status.next_try_number,
      skill: skill_block(serve.skill_key, state),
      hints: { total: hints.size, shown: hints.first(status.hints_shown).each_with_index.map { |text, i| { n: i + 1, hint_it: text } } },
      item: item_part(serve, instance)
    }
  end

  def skill_block(key, state)
    { key: key, label_it: course_view.label(key), state: state.state, state_it: Practice::Messages.state_it(state.state),
      why_it: Practice::Messages.why_it(state.why) }
  end

  def item_part(serve, instance)
    body = JSON.parse(instance.item_revision.body_json)
    stored = JSON.parse(instance.display_json)
    shown_order = serve.shown_order_json ? JSON.parse(serve.shown_order_json) : {}
    display = Diagnosis::Rekey.replay(display: stored, component: body["component"], shown_order: shown_order)
    Items::Part.new(subject: instance.item_revision.item.subject, expression_input: expression_input).call(body, body["component"], display)
  end

  def expression_input
    AppEvent.where(student_id: acting_student.id, kind: "warmup_editor_fallback").exists? ? "text" : "mathlive"
  end
end
