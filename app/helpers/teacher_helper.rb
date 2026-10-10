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
  def with_student(path)
    query = respond_to?(:student_param) ? student_param : {} # a few teacher pages have no student of their own
    query.empty? ? path : "#{path}?#{query.to_query}"
  end

  def with_student_for(student, path) = student.official? ? path : "#{path}?#{{ student: student.key }.to_query}"

  # A link from the dashboard to a detail page: it opens in a new tab (the toggle on the page can switch that
  # off); an anchor in the same page does not, and neither does a page that sets @same_tab (the findings list).
  def dash_link(text, href, **options)
    options = options.merge(target: "_blank", rel: "noopener", data: { newtab: true }) unless @same_tab || href.to_s.start_with?("#")
    link_to(text, href, **options)
  end

  # A moment in the teacher's days and hours: 08/10/2026 14:05, Rome time.
  def teacher_time(time) = time.in_time_zone("Europe/Rome").strftime("%d/%m/%Y %H:%M")

  # "Lezione: 7 schede su 11 viste (approfondimenti 1 su 2), controlli giusti al primo tentativo 5 su 7, ultima apertura ..."
  # for a topic whose lesson is a lesson/2 (A11); nil for a lesson/1, so the page shows nothing there.
  def lesson_progress_line(student, topic_revision)
    summary = Lessons::Progress.summary(student, topic_revision&.lesson_revision) or return nil
    parts = [ t("teacher.practice.lesson.cards", seen: summary.core_seen, total: summary.core_total) ]
    parts[0] += " " + t("teacher.practice.lesson.extra", seen: summary.extra_seen, total: summary.extra_total) if summary.extra_total.positive?
    parts << t("teacher.practice.lesson.checks", right: summary.first_try_right, answered: summary.checks_answered) if summary.checks_answered.positive?
    parts << (summary.last_at ? t("teacher.practice.lesson.last", at: teacher_time(summary.last_at)) : t("teacher.practice.lesson.never"))
    t("teacher.practice.lesson.line", parts: parts.join(", "))
  end

  def stage_label(stage) = t("teacher.stage.#{stage}")

  def scope_text(scope)
    mark = Teacher::GraphReview::SCOPE_MARK[scope]
    [ mark.presence, t("teacher.graph.scope.#{scope}") ].compact.join(" ")
  end

  def skill_screen_path(subject, skill) = teacher_test_skill_path(key: subject.key, skill: skill)

  def minutes_text(n) = n.to_i.zero? ? t("teacher.minutes.none") : t("teacher.minutes.some", count: n)

  REF_TOKEN = /\u27E6ref:(\d+)\u27E7/

  # The gate's sentences in Italian, safe HTML: where a sentence names an item revision it carries the
  # D-218 reference (name, key, popover) instead of the bare key. A revision that does not exist keeps
  # the plain words of Wording.
  def gate_sentences(reasons)
    marked = Hash.new { |_, id| ItemRevision.exists?(id) ? "\u27E6ref:#{id}\u27E7" : nil }
    reasons.map do |reason|
      text = ERB::Util.html_escape(Teacher::Wording.italian(reason, marked)).to_str
      text.gsub(REF_TOKEN) { ref_for(ItemRevision.find(Regexp.last_match(1).to_i)) }.html_safe
    end
  end
end
