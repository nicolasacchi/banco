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

  # The student's menu (D-240). :none in the teacher's preview, :sitting (one item) while a diagnosis sitting is on
  # the page, :full everywhere else.
  def student_menu_mode
    return :none if preview?

    controller_name == "sittings" && action_name == "show" ? :sitting : :full
  end

  # [[key, label, href], ...] of the full menu: Materie only when the course is visible to this student, Test
  # d'ingresso when the diagnosis is open (a trial student: always) or the warm-up still waits, Esci when the
  # operator has set a logout address.
  def student_menu_items
    items = [ [ :today, t("student.menu.today"), "/today" ] ]
    items << [ :subjects, t("student.menu.subjects"), "/subjects" ] if student_course_visible?
    items << [ :diagnosis, t("student.menu.diagnosis"), "/diagnosis" ] if student_diagnosis_listed?
    items << [ :settings, t("student.menu.settings"), "/settings" ]
    items << [ :logout, t("student.logout"), logout_url ] if logout_url
    items
  end

  # The menu entry of the page being shown, to mark with aria-current.
  def student_menu_current
    case request.path
    when "/today" then :today
    when %r{\A/(subjects|topics)(/|\z)} then :subjects
    when %r{\A/diagnosis(/|\z)} then :diagnosis
    when "/settings" then :settings
    end
  end

  def student_course_visible?
    view = respond_to?(:course_view) ? course_view : Course::StudentView.new(acting_student)
    view.subjects.any?
  end

  def student_diagnosis_listed? = diagnosis_open? || !Diagnosis::Warmup.complete?(acting_student)
end
