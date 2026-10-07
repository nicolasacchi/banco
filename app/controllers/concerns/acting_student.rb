# Who is answering? The student on /diagnosis, or the teacher playing a test as
# the student on /teacher/preview (a student row of kind preview, attempts in the
# context teacher_preview, never mixed with the student's own log).
#
# The preview scope is known from the route default `preview: true`, read from
# path_parameters only: a client cannot switch it on with a query string.
module ActingStudent
  extend ActiveSupport::Concern

  included do
    layout "student"
    before_action :require_actor!
    before_action :mark_student_device, unless: -> { preview? || trial_account? }
    helper_method :preview?, :base_path, :acting_student
  end

  def preview? = request.path_parameters[:preview] == true

  def base_path = preview? ? "/teacher/preview" : "/diagnosis"

  # No release for a trial student: the whole flow can be tried before the teacher opens it.
  def diagnosis_open? = trial_account? || Diagnosis::Release.open?

  def context_name = preview? ? "teacher_preview" : "diagnosis"

  def acting_student
    @acting_student ||=
      if preview?
        Student.create_with(kind: "preview").find_or_create_by!(key: "preview")
      else
        Student.create_with(kind: "student").find_or_create_by!(key: current_identity.student_key)
      end
  end

  private

  # The student's computer is marked with a signed cookie, so that /teacher decisions
  # are refused from it (D-08). The student's pages are the only place that sets it.
  # A trial student never gets it: an adult testing on a computer that is also the teacher's (D-217).
  def mark_student_device
    cookies.signed.permanent[DecisionRecorder::DEVICE_COOKIE] = { value: "student", httponly: true, same_site: :lax, secure: request.ssl? }
  end

  def require_actor!
    preview? ? require_teacher! : require_student!
  end

  # Responses of the JSON endpoints must not be cached: they carry the open item.
  def no_store
    response.headers["Cache-Control"] = "no-store"
  end
end
