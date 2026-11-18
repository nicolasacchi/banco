# A page for everyone who is signed in (D-357: privacy and account): the student in the student's layout, the teacher and a guest in
# the teacher's. Never in the preview (no route default), never on another listener, nothing is written. It borrows ActingStudent for
# the student's layout and menu, so two things change: the teacher and the guest pass the gate, and the student's device cookie is
# set only on a student's own request (a teacher must not get it: decisions are refused from a computer that carries it).
module InfoPage
  extend ActiveSupport::Concern
  include ActingStudent

  included do
    layout ->(controller) { controller.current_identity&.student? ? "student" : "teacher" }
    skip_before_action :mark_student_device
    before_action :mark_student_device, if: -> { current_identity&.student? && !trial_account? }
  end

  def acting_student = current_identity&.student? ? super : nil

  private

  def require_actor!
    return if current_identity&.reader?

    require_student!
  end
end
