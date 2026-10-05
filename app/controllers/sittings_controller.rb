# One diagnosis run on the web: the page (a single app page, Turbo off), the JSON
# step that serves the next item, the pause and visibility events, the end-of-subject
# screen and the flag "Penso che la mia risposta fosse giusta". The same code
# serves the teacher's preview, with a preview student and its own context.
class SittingsController < ApplicationController
  include ActingStudent

  before_action :load_run, except: :create
  before_action :require_open_diagnosis!, except: :create
  before_action :no_store, only: %i[step events flag]

  # Starts or resumes the student's run in a subject and goes to its page.
  def create
    subject = Subject.find_by(key: params[:key]) or return head(:not_found)

    unless preview?
      return head(:forbidden) unless Diagnosis::Release.open?

      row = Diagnosis::Availability.for(acting_student).find { |r| r.subject == subject }
      return head(:forbidden) unless row&.startable
    end
    run = preview? ? Diagnosis::Conductor.fresh_run(acting_student, subject) : Diagnosis::Conductor.run_for(acting_student, subject)
    return head(:not_found) unless run

    redirect_to "#{base_path}/runs/#{run.id}", status: :see_other
  end

  def show
    return redirect_to("#{base_path}/runs/#{@run.id}/results") if @conductor.closed? || @conductor.holding?

    @subject = @run.subject
    @minutes = Diagnosis::Rules::V1.sitting_budget_minutes(@subject.key)
    declared = JSON.parse(@run.blueprint_revision.body_json)
    @calculator = (declared["calculator"] || Diagnosis::Rules::V1.calculator(@subject.key).to_s) == "yes"
    @intro_note = declared["intro_note_it"].to_s.strip.presence
    @second_part = @run.events.exists?(kind: "sitting_closed")
    @resuming = @conductor.resuming?
  end

  def step
    result = @conductor.step!
    case result.type
    when :item then render json: { type: "item" }.merge(@conductor.presentation(result.event, student: acting_student))
    when :sitting_over then render json: { type: "sitting_over" }
    when :wait then render json: { type: "wait" }
    when :final then render json: { type: "final", results_url: "#{base_path}/runs/#{@run.id}/results" }
    end
  end

  def events
    kind = params[:kind].to_s
    return head(:unprocessable_entity) unless kind == "keepalive" || Diagnosis::Conductor::PAUSE_EVENTS.include?(kind)

    @conductor.record(kind) unless kind == "keepalive"
    render json: { ok: true }
  end

  def results
    @summary = Diagnosis::Summary.new(@run)
    redirect_to("#{base_path}/runs/#{@run.id}") unless @summary.final? || @conductor.holding?
    @subject = @run.subject
  end

  # "Penso che la mia risposta fosse giusta": one app_event per attempt, read by
  # the teacher.
  def flag
    attempt = Attempt.where(student: acting_student, served_event_id: @run.events.select(:id)).find_by(id: params[:attempt_id])
    return head(:not_found) unless attempt

    unless AppEvent.where(kind: "answer_flagged", student: acting_student).any? { |e| JSON.parse(e.payload_json)["attempt_id"] == attempt.id }
      AppEvent.create!(kind: "answer_flagged", student: acting_student, payload_json: { attempt_id: attempt.id }.to_json)
    end
    render json: { ok: true }
  end

  private

  def load_run
    @run = DiagnosisRun.find_by(id: params[:run_id], student: acting_student) or return head(:not_found)

    @conductor = Diagnosis::Conductor.new(@run)
  end

  # The student reaches a run only after the release; the daily caps are checked
  # when a sitting is about to start (the subject list says "Domani").
  def require_open_diagnosis!
    return if preview?
    return head(:forbidden) unless Diagnosis::Release.open?
    return unless action_name == "step" && !@conductor.closed? && !@conductor.holding?

    row = Diagnosis::Availability.for(acting_student).find { |r| r.subject == @run.subject }
    return if row&.startable || row&.status == "in_progress"

    # Not today (the day's caps, a dependency, a sitting that closed today): the
    # page shows "Per oggi basta così", it is not an error.
    render json: { type: "wait" }
  end
end
