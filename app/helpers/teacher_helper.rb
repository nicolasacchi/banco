# Helpers of the teacher's pages: the decision forms and the words the pages share.
module TeacherHelper
  # Whether decisions are switched on and this computer may take them. The student's
  # computer reads only; BANCO_DECISIONS_ENABLED is the operator's switch (D-08).
  # Returns nil when they can be taken, else the reason as a locale key under teacher.cannot_decide.
  def decision_blocker
    return "read_only" if reader_only?
    return "disabled" unless ENV["BANCO_DECISIONS_ENABLED"] == "1"
    return "student_device" if request.cookies[DecisionRecorder::DEVICE_COOKIE].present?

    nil
  end

  # A form that posts one decision and comes back to this page. The block holds the fields.
  # A guest only reads: the form is not drawn for them.
  def decision_form(path, id: nil, &block)
    return "".html_safe if reader_only?

    form_with(url: path, method: :post, id: id, class: "decide", local: true) do
      safe_join([ hidden_field_tag(:back, request.fullpath), capture(&block) ])
    end
  end

  # "Accesso: LOGIN · insegnante|ospite", on every teacher page.
  def access_line
    identity = current_identity or return nil
    t("teacher.access.line", login: identity.login, role: t("teacher.access.#{identity.guest? ? 'guest' : 'teacher'}"))
  end

  # The query of the chosen student, for links that keep it.
  def with_student(path) = student_param.empty? ? path : "#{path}?#{student_param.to_query}"

  def stage_label(stage) = t("teacher.stage.#{stage}")

  def scope_text(scope)
    mark = Teacher::GraphReview::SCOPE_MARK[scope]
    [ mark.presence, t("teacher.graph.scope.#{scope}") ].compact.join(" ")
  end

  def skill_screen_path(subject, skill) = teacher_test_skill_path(key: subject.key, skill: skill)

  def minutes_text(n) = n.to_i.zero? ? t("teacher.minutes.none") : t("teacher.minutes.some", count: n)

  def gate_sentences(reasons, names = {}) = reasons.map { |r| Teacher::Wording.italian(r, names) }
end
