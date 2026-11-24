# The student's choice of theme, text size, interface language and Italian translation (B-11, D-356, D-402), and for lessons of version 2 the view and reduced
# motion (A10). POST /diagnosis/preferences, student only; the teacher's preview has no preferences of its own (and no language or translation: it
# is always Italian, with the translation open).
# The settings page posts a form (redirect with a note); the lesson page posts the same fields and wants JSON.
class PreferencesController < ApplicationController
  include ActingStudent

  def update
    chosen = Diagnosis::Preferences.record(acting_student, theme: params[:theme], size: params[:size],
                                                         lesson_view: params[:lesson_view], reduce_motion: params[:reduce_motion],
                                                         listen: params[:listen], slower: params[:slower], language: (params[:language] unless preview?),
                                                         translation: (params[:translation] unless preview?))
    if request.format.json?
      render json: chosen.merge(Diagnosis::Preferences.lesson(acting_student)).merge(translation: Diagnosis::Preferences.translation(acting_student))
    else
      # said in the language just chosen: the next page is in it
      saved = I18n.with_locale(student_locale) { I18n.t("settings.saved") }
      redirect_to "#{student_root}/settings", status: :see_other, notice: saved
    end
  end
end
