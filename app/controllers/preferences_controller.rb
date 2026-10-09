# The student's choice of theme and text size (B-11), and for lessons of version 2 the view and reduced
# motion (A10). POST /diagnosis/preferences, student only; the teacher's preview has no preferences of its own.
# The settings page posts a form (redirect with a note); the lesson page posts the same fields and wants JSON.
class PreferencesController < ApplicationController
  include ActingStudent

  def update
    chosen = Diagnosis::Preferences.record(acting_student, theme: params[:theme], size: params[:size],
                                                         lesson_view: params[:lesson_view], reduce_motion: params[:reduce_motion])
    if request.format.json?
      render json: chosen.merge(Diagnosis::Preferences.lesson(acting_student))
    else
      redirect_to "/settings", status: :see_other, notice: I18n.t("settings.saved")
    end
  end
end
