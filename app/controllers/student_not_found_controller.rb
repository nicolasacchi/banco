# A mistyped or stale address on the web listener (D-378): the student gets his own 404 (D-361), in his layout, with the menu and «Commenta» and
# in his language, Italian or English (D-356); the generic catch-all page is Italian and has no menu. Everybody else (the teacher, a guest,
# nobody, a student the operator has not configured) gets the same bare 404 as before, from the same view. Other methods and listeners
# stay with NotFoundController.
class StudentNotFoundController < ApplicationController
  include ActingStudent

  # The student's device cookie only on a student's own request (a teacher must not get it: decisions are refused from a computer that carries it).
  skip_before_action :mark_student_device
  before_action :mark_student_device, if: -> { current_identity&.student? && !trial_account? }

  def show
    return render_error(:not_found) unless current_identity&.student?

    page_not_found
  end

  private

  # Not a gate: only a student has a page here, and nobody is refused (the answer is a 404 either way).
  def require_actor! = nil
end
