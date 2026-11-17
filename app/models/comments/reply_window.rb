module Comments
  # How long the teacher takes to answer (D-349): the promise made to the student and the limit of the teacher's inbox, from
  # config/banco/comments.yml (reply_within_hours). A conversation waits when the student has the last word (state sent or
  # read); it is late when it has waited longer than the promise.
  module ReplyWindow
    CONFIG_PATH = Rails.root.join("config/banco/comments.yml").freeze

    module_function

    def hours = @hours ||= Integer(YAML.safe_load_file(CONFIG_PATH, aliases: false).fetch("reply_within_hours")).tap { |h| raise ArgumentError, "reply_within_hours must be positive" unless h.positive? }

    def limit = hours.hours

    def late?(waiting_since, now = Time.current) = !waiting_since.nil? && now - waiting_since > limit

    # "un giorno", "2 giorni", "un'ora", "6 ore": whole days when the span is a number of days, else hours (at least one).
    def span_it(seconds)
      total_hours = [ (seconds / 3600.0).round, 1 ].max
      return I18n.t("comments.span.days", count: total_hours / 24) if (total_hours % 24).zero?

      I18n.t("comments.span.hours", count: total_hours)
    end

    # The sentence of both pages: «Il docente risponde entro un giorno.»
    def line_it = I18n.t("comments.reply_within", span: span_it(limit.to_i))

    # How long a conversation has waited, for the teacher: «meno di un'ora», «5 ore», «2 giorni».
    def waited_it(waiting_since, now = Time.current)
      seconds = now - waiting_since
      return I18n.t("comments.span.under_hour") if seconds < 3600

      hours = (seconds / 3600).floor
      hours >= 48 ? I18n.t("comments.span.days", count: hours / 24) : I18n.t("comments.span.hours", count: hours)
    end

    def reset! = @hours = nil
  end
end
