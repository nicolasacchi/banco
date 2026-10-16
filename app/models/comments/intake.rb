module Comments
  # The one writer of `comments` (D-304): a student's comment from the page, checked against what that student was
  # actually shown. The browser names a place (path, anchor, and the ids it holds: lesson revision, practice serve,
  # served event); every id is looked up for THIS student and must fit the page, and every id the row keeps
  # (revisions, instance, blueprint, run) is derived here, never taken from the browser. A comment writes nothing
  # else: no attempt, no serve, no event of a run, nothing the engine or the practice ledger reads.
  #
  #   Comments::Intake.call(student: s, course_view: view, params: params)  # => Result(status:, comment:, error:)
  #
  # status: :recorded (also a repeat of the same client_comment_id by the same student) or :invalid (final: the
  # page's outbox drops it). The preview student and any non-student never get here (the controller refuses them,
  # and the preview has no route); the check is repeated below.
  class Intake
    Result = Struct.new(:status, :comment, :error, keyword_init: true)

    ID_FORMAT = /\A[A-Za-z0-9_-]{8,64}\z/
    # name or name:value, up to eight segments: card:3/block:2/option:1
    ANCHOR_FORMAT = %r{\A[a-z][a-z_]{0,23}(?::[A-Za-z0-9_.-]{1,40})?(?:/[a-z][a-z_]{0,23}(?::[A-Za-z0-9_.-]{1,40})?){0,7}\z}
    REFS = %w[lesson_revision_id serve_id served_event_id].freeze
    THEMES = Diagnosis::Preferences::THEMES
    SIZES = Diagnosis::Preferences::SIZES

    class Invalid < StandardError; end

    def self.call(**args) = new(**args).call

    def initialize(student:, course_view:, params:)
      @student = student
      @view = course_view
      @params = params
    end

    def call
      raise Invalid, "not a student" unless @student.kind == "student"

      id = @params[:client_comment_id].to_s
      raise Invalid, "client_comment_id" unless id.match?(ID_FORMAT)

      existing = Comment.find_by(client_comment_id: id)
      if existing
        return Result.new(status: :recorded, comment: existing) if existing.student_id == @student.id

        raise Invalid, "client_comment_id"
      end

      row = base_row(id).merge(place)
      begin
        comment = Comment.create!(row)
      rescue ActiveRecord::RecordNotUnique
        comment = Comment.find_by!(client_comment_id: id, student_id: @student.id)
      end
      Result.new(status: :recorded, comment: comment)
    rescue Invalid => e
      Result.new(status: :invalid, error: e.message)
    end

    private

    def base_row(id)
      reason = @params[:reason].to_s
      raise Invalid, "reason" unless Comment::REASONS.include?(reason)

      text = @params[:text_it].to_s.gsub(/[[:space:]]+/, " ").strip
      raise Invalid, "text_it" if text.length > Comment::TEXT_MAX
      selected = @params[:selected_text].to_s.gsub(/[[:space:]]+/, " ").strip.first(Comment::SELECTED_MAX)
      anchor = @params[:anchor].presence&.to_s
      raise Invalid, "anchor" if anchor && !anchor.match?(ANCHOR_FORMAT)
      raise Invalid, "anchor" if anchor && anchor.length > 200

      { student: @student, client_comment_id: id, trial: @student.trial?, reason: reason, text_it: text.presence,
        selected_text: selected.presence, anchor: anchor, page_path: page.path_string, page_kind: page.kind,
        viewport_width: clamp(@params[:viewport_width]), viewport_height: clamp(@params[:viewport_height]),
        theme: THEMES.include?(@params[:theme].to_s) ? @params[:theme].to_s : nil,
        text_size: SIZES.include?(@params[:text_size].to_s) ? @params[:text_size].to_s : nil, created_at: Time.current }
    end

    def clamp(value)
      n = Integer(value.to_s, exception: false)
      n && n.between?(1, 20_000) ? n : nil
    end

    PageInfo = Struct.new(:kind, :path_string, :parsed, keyword_init: true)

    def page
      @page ||= begin
        path = @params[:page_path].to_s
        parsed = Pages.parse(path) or raise Invalid, "page_path"
        PageInfo.new(kind: parsed.kind, path_string: path, parsed: parsed)
      end
    end

    # The ids the browser gave, as integers; a malformed one is invalid.
    def refs
      @refs ||= REFS.to_h do |name|
        raw = (@params[:refs].respond_to?(:[]) ? @params[:refs][name] : nil)
        next [ name, nil ] if raw.nil? || raw == ""

        n = Integer(raw.to_s, exception: false)
        raise Invalid, name unless n&.positive?

        [ name, n ]
      end
    end

    def allow_refs!(*names)
      given = refs.select { |_k, v| v }.keys
      raise Invalid, "refs" unless (given - names).empty?
    end

    # The columns that say where it was, derived and checked per kind of page.
    def place
      parsed = page.parsed
      case page.kind
      when "topic" then topic_place(parsed)
      when "lesson" then lesson_place(parsed)
      when "practice" then practice_place(parsed)
      when "sitting", "results" then run_place(parsed)
      when "subject" then subject_place(parsed)
      else
        allow_refs!
        {}
      end
    end

    def visible_topic(parsed)
      found = @view.find_topic(parsed.topic) or raise Invalid, "page_path"
      found
    end

    def topic_place(parsed)
      allow_refs!
      subject_view, topic = visible_topic(parsed)
      { subject: subject_view.subject, topic_revision: topic.topic_revision }
    end

    def lesson_place(parsed)
      allow_refs!("lesson_revision_id")
      subject_view, topic = visible_topic(parsed)
      revision = topic.topic_revision.lesson_revision
      given = refs["lesson_revision_id"]
      raise Invalid, "lesson_revision_id" if given && given != revision.id

      card = anchor_card
      if card
        raise Invalid, "anchor" unless revision.lesson2? && revision.body["cards"].any? { |c| c["n"] == card }
      end
      { subject: subject_view.subject, topic_revision: topic.topic_revision, lesson_revision: revision, card: card }
    end

    def practice_place(parsed)
      allow_refs!("serve_id")
      subject_view, topic = visible_topic(parsed)
      raise Invalid, "page_path" unless topic.skills.include?(parsed.skill)

      row = { subject: subject_view.subject, topic_revision: topic.topic_revision }
      return row unless refs["serve_id"]

      serve = PracticeServe.find_by(id: refs["serve_id"], student_id: @student.id)
      raise Invalid, "serve_id" unless serve && serve.skill_key == parsed.skill && topic.skills.include?(serve.skill_key)

      row.merge(practice_serve: serve, item_instance_id: serve.item_instance_id, item_revision_id: serve.item_instance.item_revision_id)
    end

    def run_place(parsed)
      allow_refs!("served_event_id")
      run = DiagnosisRun.find_by(id: parsed.run_id, student_id: @student.id) or raise Invalid, "page_path"
      row = { subject_id: run.subject_id, diagnosis_run: run, blueprint_revision_id: run.blueprint_revision_id }
      return row unless refs["served_event_id"]

      served = ItemServed.joins(:diagnosis_event)
                         .find_by(diagnosis_event_id: refs["served_event_id"], diagnosis_events: { diagnosis_run_id: run.id, kind: "item_served" }) or raise Invalid, "served_event_id"
      row.merge(served_event_id: served.diagnosis_event_id, item_instance_id: served.item_instance_id,
                item_revision_id: served.item_instance.item_revision_id)
    end

    def subject_place(parsed)
      allow_refs!
      view = @view.subject(parsed.subject_key) or raise Invalid, "page_path"
      { subject: view.subject }
    end

    # card:N in the anchor, the card of a lesson/2.
    def anchor_card
      m = @params[:anchor].to_s.match(%r{\Acard:([1-9]\d{0,2})(?:/|\z)})
      m && m[1].to_i
    end
  end
end
