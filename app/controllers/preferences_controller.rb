# The student's choice of theme and text size (B-11). POST /diagnosis/preferences,
# student only; the teacher's preview has no preferences of its own.
class PreferencesController < ApplicationController
  include ActingStudent

  def update
    Diagnosis::Preferences.record(acting_student, theme: params[:theme], size: params[:size])
    redirect_to "/diagnosis", status: :see_other
  end
end
