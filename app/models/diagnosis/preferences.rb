module Diagnosis
  # How the student likes to read: a theme and a text size (B-11, E-10), and for lessons of version 2 the view
  # (one card at a time or all in a column) and reduced motion (A10). Kept on the server, in the append-only
  # app_events (kind student_preference, the latest one counts), so that every computer of the student shows the
  # same pages. The layout puts theme and size on <html> as data-theme and data-size; the item renderer is plain
  # markup in rem, so it follows. `for` answers theme and size only (every old caller); `lesson` the other two.
  module Preferences
    THEMES = %w[cream dark].freeze
    SIZES = %w[normal large larger].freeze
    LESSON_VIEWS = %w[cards scroll].freeze
    DEFAULT = { theme: "cream", size: "normal" }.freeze
    LESSON_DEFAULT = { lesson_view: "cards", reduce_motion: false }.freeze
    KIND = "student_preference".freeze

    module_function

    def stored(student)
      return {} unless student

      payload = AppEvent.where(kind: KIND, student_id: student.id).order(:id).last&.payload_json
      payload ? JSON.parse(payload) : {}
    end

    def for(student)
      stored = stored(student)
      { theme: THEMES.include?(stored["theme"]) ? stored["theme"] : DEFAULT[:theme],
        size: SIZES.include?(stored["size"]) ? stored["size"] : DEFAULT[:size] }
    end

    # { lesson_view: "cards" | "scroll", reduce_motion: true | false }
    def lesson(student)
      stored = stored(student)
      { lesson_view: LESSON_VIEWS.include?(stored["lesson_view"]) ? stored["lesson_view"] : LESSON_DEFAULT[:lesson_view],
        reduce_motion: stored["reduce_motion"] == true }
    end

    # Records the choice (unknown values are ignored: the old one stays). Returns the theme and size now in
    # force. The lesson keys are kept apart from them: a payload carries all four when any is set.
    def record(student, theme: nil, size: nil, lesson_view: nil, reduce_motion: nil)
      now = self.for(student)
      before = lesson(student)
      chosen = { theme: THEMES.include?(theme.to_s) ? theme.to_s : now[:theme], size: SIZES.include?(size.to_s) ? size.to_s : now[:size] }
      lessons = { lesson_view: LESSON_VIEWS.include?(lesson_view.to_s) ? lesson_view.to_s : before[:lesson_view],
                  reduce_motion: reduce_motion.nil? ? before[:reduce_motion] : ActiveModel::Type::Boolean.new.cast(reduce_motion) == true }
      AppEvent.create!(kind: KIND, student: student, payload_json: chosen.merge(lessons).to_json) unless chosen == now && lessons == before
      chosen
    end
  end
end
