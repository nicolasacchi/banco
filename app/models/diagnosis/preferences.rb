module Diagnosis
  # How the student likes to read: a theme and a text size (B-11, E-10), and for lessons of version 2 the view
  # (one card at a time or all in a column) and reduced motion (A10). Kept on the server, in the append-only
  # app_events (kind student_preference, the latest one counts), so that every computer of the student shows the
  # same pages. The layout puts theme and size on <html> as data-theme and data-size; the item renderer is plain
  # markup in rem, so it follows. `for` answers theme and size only (every old caller); `lesson` the other two.
  # Themes (D-350): cream (the default), light (white, neutral), dark, and auto, which follows the device
  # (prefers-color-scheme: light shows cream, dark shows dark). Sizes are the root font size, 12 to 28 px (D-354), and every
  # length of the pages is in rem, so a size scales the whole page, not only the text.
  # The language of the interface (D-356): it (the default) or en, saved with the theme and the size. It is the language of the
  # chrome only (menus, buttons, messages the code generates); lessons and exercises stay Italian. A new language is one entry in
  # LANGUAGES (and in config.i18n.available_locales) plus its locale files; the teacher's pages and the preview are always Italian.
  module Preferences
    THEMES = %w[cream light dark auto].freeze
    SIZES = %w[minimum tiny smallest small normal large larger].freeze
    LANGUAGES = %w[it en].freeze
    DEFAULT_LANGUAGE = "it".freeze
    LESSON_VIEWS = %w[cards scroll].freeze
    DEFAULT = { theme: "cream", size: "normal" }.freeze
    LESSON_DEFAULT = { lesson_view: "cards", reduce_motion: false, listen: true, slower: false }.freeze
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

    # The language of the student's interface: "it" or "en" (D-356). Its own reader, so that `for` keeps answering theme and size only.
    def language(student)
      stored = stored(student)["language"]
      LANGUAGES.include?(stored) ? stored : DEFAULT_LANGUAGE
    end

    # { lesson_view: "cards" | "scroll", reduce_motion: true | false, listen: true | false, slower: true | false }
    # listen is the "Ascolta" switch (on until the student turns it off), slower the "Più lento" speed (D-283).
    def lesson(student)
      stored = stored(student)
      { lesson_view: LESSON_VIEWS.include?(stored["lesson_view"]) ? stored["lesson_view"] : LESSON_DEFAULT[:lesson_view],
        reduce_motion: stored["reduce_motion"] == true,
        listen: stored["listen"] != false,
        slower: stored["slower"] == true }
    end

    # Records the choice (unknown values are ignored: the old one stays). Returns the theme and size now in
    # force. The lesson keys and the language are kept apart from them: a payload carries all of them when any is set.
    def record(student, theme: nil, size: nil, lesson_view: nil, reduce_motion: nil, listen: nil, slower: nil, language: nil)
      now = self.for(student)
      before = lesson(student)
      language_before = self.language(student)
      chosen_language = LANGUAGES.include?(language.to_s) ? language.to_s : language_before
      chosen = { theme: THEMES.include?(theme.to_s) ? theme.to_s : now[:theme], size: SIZES.include?(size.to_s) ? size.to_s : now[:size] }
      lessons = { lesson_view: LESSON_VIEWS.include?(lesson_view.to_s) ? lesson_view.to_s : before[:lesson_view],
                  reduce_motion: reduce_motion.nil? ? before[:reduce_motion] : ActiveModel::Type::Boolean.new.cast(reduce_motion) == true,
                  listen: listen.nil? ? before[:listen] : ActiveModel::Type::Boolean.new.cast(listen) == true,
                  slower: slower.nil? ? before[:slower] : ActiveModel::Type::Boolean.new.cast(slower) == true }
      unchanged = chosen == now && lessons == before && chosen_language == language_before
      AppEvent.create!(kind: KIND, student: student, payload_json: chosen.merge(lessons).merge(language: chosen_language).to_json) unless unchanged
      chosen
    end
  end
end
