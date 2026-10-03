module Diagnosis
  # How the student likes to read: a theme and a text size (B-11, E-10). Kept on the
  # server, in the append-only app_events (kind student_preference, the latest one
  # counts), so that every computer of the student shows the same pages. The layout
  # puts them on <html> as data-theme and data-size; the item renderer is plain
  # markup in rem, so it follows.
  module Preferences
    THEMES = %w[cream dark].freeze
    SIZES = %w[normal large larger].freeze
    DEFAULT = { theme: "cream", size: "normal" }.freeze
    KIND = "student_preference".freeze

    module_function

    def for(student)
      return DEFAULT unless student

      payload = AppEvent.where(kind: KIND, student_id: student.id).order(:id).last&.payload_json
      stored = payload ? JSON.parse(payload) : {}
      { theme: THEMES.include?(stored["theme"]) ? stored["theme"] : DEFAULT[:theme],
        size: SIZES.include?(stored["size"]) ? stored["size"] : DEFAULT[:size] }
    end

    # Records the choice (unknown values are ignored: the old one stays). Returns the
    # preferences now in force.
    def record(student, theme:, size:)
      now = self.for(student)
      chosen = { theme: THEMES.include?(theme.to_s) ? theme.to_s : now[:theme], size: SIZES.include?(size.to_s) ? size.to_s : now[:size] }
      AppEvent.create!(kind: KIND, student: student, payload_json: chosen.to_json) unless chosen == now
      chosen
    end
  end
end
