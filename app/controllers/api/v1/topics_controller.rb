module Api
  module V1
    # Topics (A2.3, A4): a topic is a lesson plus 2 to 4 pinned practice items per skill, in the order of the course
    # map. Validation is synchronous. The teacher approves topic revisions in the browser (approve_topic);
    # nothing here does, and the stage the agent can reach is awaiting_teacher.
    class TopicsController < Api::BaseController
      include SubjectScoped

      before_action :load_subject, only: :index

      # GET /api/v1/subjects/:subject/topics
      def index
        course = Course::State.latest(@subject)
        rows = (Course::TopicStage.rows(@subject) || {}).values.each_with_index.map do |row, i|
          latest = row.latest
          { topic: row.topic["key"], kind: row.topic["kind"], position: i + 1, title_it: row.topic["title_it"], latest_revision_id: latest&.id, seq: latest&.seq,
            stage: row.stage, approved_revision_id: row.approved_revision_id, stale_pins: row.stale_pins, gate_reasons: row.gate_reasons }
        end
        render json: { subject: @subject.key, course_revision_id: course&.id, rows: rows }
      end

      # GET /api/v1/topics/:topic
      def open
        subject = Subject.find_by(key: params[:topic].split(".", 3)[1])
        row = subject && Course::TopicStage.rows(subject)&.fetch(params[:topic], nil)
        return refuse("E-NOT-FOUND", "topic", "#{params[:topic]} is not a topic of the latest course map", "banco topics list --subject KEY", 404) unless row

        latest = row.latest
        lesson = Lesson.find_by(key: params[:topic])
        render json: { topic: params[:topic], subject: subject.key,
                       latest: latest && { revision_id: latest.id, seq: latest.seq, topic: latest.body },
                       approved_revision_id: row.approved_revision_id, stage: row.stage, stale_pins: row.stale_pins,
                       lesson: row.lesson_pin || { pinned: nil, latest: lesson&.latest_revision&.id },
                       gate_reasons: row.gate_reasons, brief: brief_row("topic"),
                       next: latest ? "edit the topic and run banco topic submit FILE --dry-run" : "write a banco.topic/1 document (see banco brief show topic) and run banco topic submit FILE --dry-run" }
      end

      # POST /api/v1/topics/:topic {topic}
      def submit
        body = parse_json_body or return
        doc = body["topic"]
        return refuse("E-FILES", "topic", "send the topic as {topic: {...}}", "banco topic submit FILE", 422) unless doc.is_a?(Hash)
        if doc["key"] != params[:topic]
          return refuse("E-FILES", "key", "the file has key #{doc['key'].inspect}; you are submitting to #{params[:topic]}", "banco topic submit FILE", 422)
        end

        subject = Subject.find_by(key: params[:topic].split(".", 3)[1])
        return refuse("E-NOT-FOUND", "topic", "no subject in #{params[:topic]}", "banco status", 404) unless subject

        result = Validation::TopicChecks.call(doc, subject: subject)
        return if refuse_findings(result.findings, "fix the topic and run banco topic submit FILE --dry-run again", dry_run: dry_run?)

        author = require_session("author") or return

        warnings = result.findings.warnings.map(&:to_h)
        return render json: { dry_run: true, status: "passed", codes: [], warnings: warnings, stored: result.stored } if dry_run?

        store(subject, result, warnings, author)
      end

      private

      def store(subject, result, warnings, author)
        course = Course::State.latest(subject)
        text = JSON.generate(result.stored)
        lesson = result.lesson_revision.lesson
        latest = nil
        revision = begin
          TopicRevision.transaction do
          latest = lesson.topic_revisions.max_by(&:seq)
          next if latest && latest.body_json == text && latest.course_revision_id == course.id

          TopicRevision.create!(lesson: lesson, seq: (latest&.seq || 0) + 1, course_revision: course, lesson_revision: result.lesson_revision,
                                body_json: text, author_session: author, brief_sha256: Brief.find("topic")&.sha256)
          end
        rescue ActiveRecord::RecordNotUnique
          return refuse("E-STALE-BASE", "topic", "another revision of this topic was stored at the same time", "banco topics list --subject #{subject.key}", 409)
        end
        return render json: { revision_id: latest.id, seq: latest.seq, replayed: true, stored: result.stored, warnings: warnings } unless revision

        render json: { revision_id: revision.id, seq: revision.seq, replayed: false, stored: result.stored, warnings: warnings,
                       next: "banco topics list --subject #{subject.key} (stop at awaiting_teacher: the teacher approves in the browser)" }, status: :created
      end
    end
  end
end
