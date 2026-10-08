module Api
  module V1
    # Lessons (A2.1, A4): list a subject's lessons, open one as lesson.md, submit a new revision, read the state
    # of a revision. Validation is synchronous (no Chrome): a lesson with an error is refused and nothing is
    # stored. The teacher approves topics and sends lessons back in the browser; nothing here does.
    class LessonsController < Api::BaseController
      include SubjectScoped

      before_action :load_subject, only: :index

      # GET /api/v1/subjects/:subject/lessons
      def index
        map_keys = Course::State.latest(@subject)&.body&.fetch("topics", [])&.map { |t| t["key"] }.to_a
        lessons = Lesson.where(subject: @subject).includes(revisions: :reviews).order(:key)
        rows = lessons.filter_map do |lesson|
          latest = lesson.latest_revision or next
          { lesson: lesson.key, kind: lesson.kind, latest_revision_id: latest.id, seq: latest.seq, rules_version: latest.rules_version,
            older_rules: Course::LessonView.older_rules?(latest), reviews: latest.reviews.size,
            review_blockers: Course::LessonView.severity_count(latest, "blocker"), review_majors: Course::LessonView.severity_count(latest, "major"),
            sent_back: Course::Decisions.lesson_sent_back?(latest), in_course_map: map_keys.include?(lesson.key),
            pinned_by_topic_revision_ids: TopicRevision.where(lesson_revision_id: latest.id).order(:id).pluck(:id) }
        end
        render json: { subject: @subject.key, rows: rows }
      end

      # GET /api/v1/lessons/:lesson
      def open
        lesson = Lesson.find_by(key: params[:lesson])
        latest = lesson&.latest_revision
        return refuse("E-NOT-FOUND", "lesson", "no lesson #{params[:lesson].to_s.first(80)}: a first submit creates it (banco brief show lesson)", "banco lesson submit DIR", 404) unless latest

        render json: { lesson: lesson.key, kind: lesson.kind, subject: lesson.subject.key, latest: Course::LessonView.latest_row(latest),
                       files: { "lesson.md" => latest.source_md }, reviews: Course::LessonView.reviews(latest),
                       teacher_comments: Course::LessonView.comments(lesson),
                       next: "edit lesson.md, then banco lesson submit DIR --dry-run" }
      end

      # GET /api/v1/lesson-revisions/:revision
      def status
        revision = LessonRevision.find_by(id: params[:revision])
        return refuse("E-NOT-FOUND", "revision", "no lesson revision #{params[:revision].to_s.first(20).inspect}", "banco lessons list --subject KEY", 404) unless revision

        latest = revision.lesson.latest_revision
        render json: { revision_id: revision.id, lesson: revision.lesson.key, seq: revision.seq, superseded: latest.id != revision.id,
                       rules_version: revision.rules_version, older_rules: Course::LessonView.older_rules?(revision), warnings: revision.warnings,
                       reviews: Course::LessonView.reviews(revision), sent_back: Course::Decisions.lesson_sent_back?(revision) }
      end

      # POST /api/v1/lessons/submit {lesson, base, files: {"lesson.md"}}
      def submit
        body = parse_json_body or return
        key = body["lesson"].to_s
        unless key.match?(/\A(ripasso|ponte|lezione)\.[a-z_]+\.[a-z0-9]+(-[a-z0-9]+)*\z/) && key.size <= 120
          return refuse("E-FILES", "lesson", "lesson is a key such as ripasso.math.linear-equations-integer", "banco lesson submit DIR", 422)
        end
        files = body["files"]
        unless files.is_a?(Hash) && files.keys == [ "lesson.md" ] && files["lesson.md"].is_a?(String)
          return refuse("E-FILES", "files", "send exactly {\"lesson.md\": \"...\"}", "banco lesson submit DIR", 422)
        end
        if files["lesson.md"].bytesize > Validation::Rules.get(:lesson, :max_bytes)
          return refuse("E-TOO-LARGE", "files/lesson.md", "lesson.md is over #{Validation::Rules.get(:lesson, :max_bytes)} bytes", "shorten the lesson", 413)
        end
        subject = Subject.find_by(key: key.split(".", 3)[1])
        return refuse("E-NOT-FOUND", "lesson", "no subject #{key.split('.', 3)[1].inspect}", "banco status", 404) unless subject

        source = Lessons::Parser.normalize(files["lesson.md"])
        outcome = Validation::LessonChecks.call(source, subject: subject.key, context: Validation::CourseContext.for(subject))
        if outcome.parsed && outcome.parsed.front_matter["key"] != key
          return refuse("E-FILES", "lesson", "the front matter key #{outcome.parsed.front_matter['key'].inspect} differs from the lesson #{key}", "banco lesson submit DIR", 422)
        end
        return if refuse_findings(outcome.findings, "fix lesson.md and run banco lesson submit DIR --dry-run again", dry_run: dry_run?)

        author = require_session("author") or return

        lesson = Lesson.find_by(key: key)
        latest = lesson&.latest_revision
        return unless base_ok?(body["base"], lesson, latest, key)

        warnings = outcome.findings.warnings.map(&:to_h)
        return render json: { dry_run: true, status: "passed", codes: [], warnings: warnings } if dry_run?

        store(key, subject, source, outcome.body, warnings, author, body["base"])
      end

      private

      def base_ok?(base, lesson, latest, key)
        if latest
          return true if base.to_s == latest.id.to_s

          refuse("E-STALE-BASE", "base", "the base is revision #{base.inspect}; the latest of #{key} is #{latest.id}", "banco lesson open #{key}", 409)
          return false
        end
        return true if base.nil?

        refuse("E-NOT-FOUND", "base", "the lesson #{key} has no revision #{base}", "banco lesson submit DIR (a new lesson has no base)", 404)
        false
      end

      def store(key, subject, source, body, warnings, author, base)
        sha = Digest::SHA256.hexdigest(source)
        rules = Validation::Rules.version.to_s
        replay = nil
        revision = begin
          LessonRevision.transaction do
          lesson = Lesson.find_or_create_by!(key: key) { |l| l.subject = subject; l.kind = body["kind"] }
          latest = lesson.latest_revision
          if latest && latest.source_sha256 == sha && latest.rules_version == rules
            replay = latest
            next
          end
          LessonRevision.create!(lesson: lesson, seq: (latest&.seq || 0) + 1, base_revision_id: latest&.id, source_md: source, source_sha256: sha,
                                 body_json: JSON.generate(body), rules_version: rules, warnings_json: JSON.generate(warnings),
                                 author_session: author, brief_sha256: Brief.find("lesson")&.sha256)
          end
        rescue ActiveRecord::RecordNotUnique
          return refuse("E-STALE-BASE", "base", "another revision of #{key} was stored at the same time", "banco lesson open #{key}", 409)
        end
        return render json: { lesson: key, revision_id: replay.id, seq: replay.seq, replayed: true, warnings: replay.warnings } unless revision

        render json: { lesson: key, revision_id: revision.id, seq: revision.seq, replayed: false, warnings: warnings,
                       next: "stop here until another session reviews it: banco lesson-review open #{revision.id}" }, status: :created
      end
    end
  end
end
