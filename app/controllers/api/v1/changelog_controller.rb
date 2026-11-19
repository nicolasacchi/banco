module Api
  module V1
    # «Novità» over the API (D-375), for every token role: the curated entries of config/banco/changelog.yml and the topics approved again, both
    # public to the people they are for (the student and the teacher read them on their pages). No student's word is in it (`Le tue segnalazioni`
    # is the student's own page and stays there).
    #
    # audience=student: what the student reads: the entries whose audience includes him, the topic updates of the topics HIS course shows (student=KEY,
    # default the official student), one per topic and day, with no reason and no revision id. audience=teacher (the default): every entry and every
    # update with the two revision ids and the teacher's reason; the reason only for the tokens that read the teacher's words (bot_read, teacher), a content
    # agent's token gets the ids without it. since: a day (2026-11-17) from which on.
    class ChangelogController < Api::BaseController
      # GET /api/v1/changelog[?audience=student|teacher][&since=DATE][&student=KEY]
      def show
        audience = params[:audience].presence || "teacher"
        return refuse("E-FILES", "audience", "audience is student or teacher", "banco changelog --audience student", 422) unless Changelog::Entries::AUDIENCES.include?(audience)

        since = params[:since].presence && parse_day(params[:since].to_s)
        return refuse("E-FILES", "since", "since is a day such as 2026-11-17", "banco changelog --since 2026-11-17", 422) if params[:since].present? && since.nil?

        return refuse("E-FILES", "student", "student applies to audience student", "banco changelog --audience student --student student", 422) if params[:student].present? && audience != "student"

        audience == "student" ? student_answer(since) : teacher_answer(since)
      end

      private

      def teacher_answer(since)
        feed = Changelog::Feed.teacher(since: since)
        render json: { audience: "teacher", since: since&.iso8601, entries: feed.entries.map { |e| Changelog::ApiRows.entry(e, teacher: true) },
                       content_updates: feed.updates.map { |u| Changelog::ApiRows.update(u, reason: reader?) } }.compact
      end

      def student_answer(since)
        key = params[:student].presence&.to_s || Student::OFFICIAL_KEY
        student = Student::KEY_FORMAT.match?(key) ? Student.find_by(key: key, kind: "student") : nil
        return refuse("E-NOT-FOUND", "student", "no student #{key.first(40).inspect}", "banco status", 404) unless student

        feed = Changelog::Feed.student(student, Course::StudentView.new(student), since: since, followups: false)
        days = feed.days.map { |date, list| { date: date.iso8601, topics: list.map { |u| { topic: u.topic, title_it: u.title_it, line_it: I18n.t("changelog.updates.note", locale: :it) } } } }
        render json: { audience: "student", student: student.key, since: since&.iso8601, entries: feed.entries.map { |e| Changelog::ApiRows.entry(e, teacher: false) }, content_updates: days }.compact
      end

      def parse_day(text)
        text.match?(/\A\d{4}-\d{2}-\d{2}\z/) ? Date.iso8601(text) : nil
      rescue Date::Error
        nil
      end
    end
  end
end
