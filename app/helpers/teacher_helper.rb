# Helpers of the teacher's pages: the decision forms and the words the pages share.
module TeacherHelper
  # Whether decisions are switched on and this computer may take them. The student's
  # computer reads only; BANCO_DECISIONS_ENABLED is the operator's switch (D-08).
  # Returns nil when they can be taken, else the reason as a locale key under teacher.cannot_decide.
  def decision_blocker
    return "disabled" unless ENV["BANCO_DECISIONS_ENABLED"] == "1"
    return "student_device" if request.cookies[DecisionRecorder::DEVICE_COOKIE].present?

    nil
  end

  # A form that posts one decision and comes back to this page. The block holds the fields.
  def decision_form(path, id: nil, &block)
    form_with(url: path, method: :post, id: id, class: "decide", local: true) do
      safe_join([ hidden_field_tag(:back, request.fullpath), capture(&block) ])
    end
  end

  def stage_label(stage) = t("teacher.stage.#{stage}")

  def scope_text(scope)
    mark = Teacher::GraphReview::SCOPE_MARK[scope]
    [ mark.presence, t("teacher.graph.scope.#{scope}") ].compact.join(" ")
  end

  def skill_screen_path(subject, skill) = teacher_test_skill_path(key: subject.key, skill: skill)

  def minutes_text(n) = n.to_i.zero? ? t("teacher.minutes.none") : t("teacher.minutes.some", count: n)

  def gate_sentences(reasons, names = {}) = reasons.map { |r| Teacher::Wording.italian(r, names) }
end
