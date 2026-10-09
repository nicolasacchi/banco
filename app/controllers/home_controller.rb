# The front door of the web listener (D-240). Who opens the bare address lands on their own page: the student
# (official or trial) on Oggi, the teacher and a guest on /teacher. Anyone else, and a student login the operator
# has not configured, gets the same bare 404 as before. The edge proxy's login brings the browser back to the
# address it asked for, so opening the site signs in and lands on Oggi.
class HomeController < ApplicationController
  def show
    identity = current_identity
    if identity&.student?
      redirect_to "/today", status: :see_other
    elsif identity&.reader?
      redirect_to "/teacher", status: :see_other
    else
      render plain: "Not found", status: :not_found
    end
  end
end
