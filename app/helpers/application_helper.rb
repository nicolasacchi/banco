module ApplicationHelper
  # The importmap of the student's pages: no Turbo, no application.js (X-02).
  def student_importmap
    # config.x answers an empty options object for a name nobody set, so test the type.
    map = Rails.application.config.x.student_importmap
    return map if map.is_a?(Importmap::Map)

    Rails.application.config.x.student_importmap = Importmap::Map.new.draw(Rails.root.join("config/importmap.student.rb"))
  end

  # Theme and size for <html>: the student's own choice on the student's pages, the
  # defaults everywhere else (the teacher's pages and the preview).
  def ui_preferences
    student = respond_to?(:acting_student) && !preview? ? acting_student : nil
    Diagnosis::Preferences.for(student)
  end

  # The texts that the student's JavaScript needs, one flat object (Italian texts
  # live in config/locales/it.yml, never in the scripts).
  def student_texts
    warmup = I18n.t("warmup")
    I18n.t("items").merge(I18n.t("sitting").except(:intro)).merge(
      accents_label: I18n.t("accents.label"),
      retry: warmup[:retry], warmup_step: warmup[:step], warmup_paused: warmup[:paused], warmup_right: warmup[:right],
      warmup_skip: warmup[:skip], warmup_fallback_note: warmup[:fallback_note]
    )
  end

  # The texts of the practice page's script (config/locales/course.it.yml), one flat object.
  def practice_labels
    t = I18n.t("practice")
    t.slice(:loading, :saving, :empty, :blocked, :error, :hint, :hint_n, :solution, :solution_title, :final, :skill_now, :try_this,
            :try_this_reason, :after_solution, :next, :back, :closed, :not_counted, :reseen, :submit)
  end

  # The texts of the "Non ho capito" control's script.
  def question_labels = I18n.t("question").slice(:sent, :error, :send, :close)

  def lesson_labels = I18n.t("lesson").slice(:error, :loading_solution, :solution_title, :show_solution)
end
