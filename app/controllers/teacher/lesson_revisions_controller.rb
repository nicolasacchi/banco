module Teacher
  # The teacher's box "Come la vede lo studente" (A14) asks three things of the server, all read-only and none recorded:
  #   GET  /teacher/lesson-revisions/:id/full.json                    the stored body: answers, error messages, explanations, solutions
  #   POST /teacher/lesson-revisions/:id/checks/...                   a check graded with the seed "preview" (same grader as the student's)
  #   POST /teacher/lesson-revisions/:id/exercises/:n/solution        an exercise's solution
  # Guards, as DecisionRecorder's for reading: web listener only (the route), the teacher or a guest (reader; the two POSTs: the teacher), never
  # from the student's computer (the banco_device cookie) nor from a student identity (a student is not a reader);
  # Cache-Control: no-store. A refusal is a 403 with no body.
  class LessonRevisionsController < Teacher::BaseController
    skip_before_action :require_reader!
    before_action :guard
    # The grading and the solutions are POSTs: the teacher's only (a guest reads, and every write of the area is refused to a guest).
    before_action :require_teacher!, only: %i[check solution]
    before_action :load_revision
    before_action :require_lesson2, only: :check
    before_action { response.headers["Cache-Control"] = "no-store" }

    def full
      render json: @revision.body
    end

    def check
      locator = { card: params[:card].to_i, block: params[:block].to_i, step: params[:step]&.to_i, ex: params[:n]&.to_i, part: params[:part]&.to_i }
      answer = Lessons::CheckAnswer.new(@revision, student_key: "preview", trial_try: params[:try].to_i.clamp(1, 99))
      reply = answer.call(locator, JSON.parse(request.request_parameters["response"].to_json))
      render json: reply.body, status: reply.status
    end

    def solution
      exercise = @revision.exercise(params[:n].to_i)
      return render(json: { status: "not_found" }, status: :not_found) unless exercise

      answer = { n: exercise["n"], solution_it: exercise["solution_it"] }
      answer = { n: exercise["n"], steps: exercise["solution_steps"].map { |s| s.slice("tag", "do_it", "why_it") } } if exercise["solution_steps"]
      render json: answer
    end

    private

    def guard
      return head(:forbidden) unless current_identity&.reader?

      head(:forbidden) if request.cookies[DecisionRecorder::DEVICE_COOKIE].present?
    end

    def load_revision
      @revision = LessonRevision.find_by(id: params[:id])
      head(:not_found) unless @revision
    end

    def require_lesson2
      head(:not_found) unless @revision.lesson2?
    end
  end
end
