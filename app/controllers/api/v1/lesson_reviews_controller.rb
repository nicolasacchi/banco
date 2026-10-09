module Api
  module V1
    # The review of a lesson revision (A5): one by an independent session, banco.lesson_review/1. Findings stay
    # inline in the review; what the teacher does with them is the approval of the topic in the browser. Nothing
    # here approves anything.
    class LessonReviewsController < Api::BaseController
      include IndependentRoles

      before_action :load_revision

      # GET /api/v1/lesson-revisions/:revision/review
      def open
        if request.headers["X-Banco-Session"].to_s.strip.empty?
          return refuse("E-AUTH", "authorization", "this token cannot review", "banco schema", 403) unless ApiToken.session_roles(@token.role).include?("reviewer")
        elsif !author_read?
          session = require_session("reviewer", item: @lesson, next_step: next_session) or return
          return unless reviewer_ok?(session)
        end

        latest = @lesson.latest_revision
        current = latest.id == @revision.id
        render json: { revision_id: @revision.id, lesson: @lesson.key, seq: @revision.seq, superseded: !current, lesson_md: @revision.source_md,
                       body: @revision.body, programme_lines: programme_lines, skills: skills(@revision.body["skills"]),
                       uses: skills(@revision.body["uses"]).map { |s| s.slice(:key, :label_it) },
                       checklist: Review::LessonChecklist.for(@revision), brief: brief_row("lesson-review"),
                       next: current ? "write banco.lesson_review/1 (banco brief show lesson-review) and run banco lesson-review submit #{@revision.id} --file review.json" :
                                       "superseded: a review of this revision cannot be filed; run banco lesson-review open #{latest.id}" }
      end

      # POST /api/v1/lesson-revisions/:revision/review {review}
      def submit
        body = parse_json_body or return
        session = require_session("reviewer", item: @lesson, next_step: next_session) or return
        return unless reviewer_ok?(session)

        latest = @lesson.latest_revision
        return refuse("E-STALE-BASE", "revision", "revision #{@revision.id} is not the latest of #{@lesson.key} (#{latest.id})", "banco lesson-review open #{latest.id}", 409) unless latest.id == @revision.id

        doc = body["review"]
        return refuse("E-FILES", "review", "send the review as {review: {...}}", "banco lesson-review submit REV --file review.json", 422) unless doc.is_a?(Hash)
        if doc["revision"] && doc["revision"].to_s != @revision.id.to_s
          return refuse("E-FILES", "revision", "the file reviews revision #{doc['revision'].inspect}; you are submitting to revision #{@revision.id}", "banco lesson-review open #{@revision.id}", 422)
        end

        findings = Review::LessonIntake.call(doc, @revision)
        return if refuse_findings(findings, "fix review.json and run banco lesson-review submit #{@revision.id} --file review.json again", dry_run: dry_run?)
        return render json: { dry_run: true, status: "passed", codes: [], findings: doc["findings"].size } if dry_run?

        review = LessonReview.create!(lesson_revision: @revision, agent_session: session, checklist_json: JSON.generate(doc["checklist"]),
                                      recomputed_json: JSON.generate(doc["recomputed"]), findings_json: JSON.generate(doc["findings"]),
                                      brief_sha256: Brief.find("lesson-review")&.sha256)
        render json: { review_id: review.id, revision_id: @revision.id, findings: doc["findings"], counts: doc["findings"].map { |f| f["severity"] }.tally,
                       next: "stop here: the teacher reads the review and approves the topic in the browser (banco status)" }, status: :created
      rescue ActiveRecord::RecordNotUnique
        refuse("E-SESSION-NOT-INDEPENDENT", "X-Banco-Session", "session #{session.id} has already reviewed revision #{@revision.id}", next_session, 422)
      end

      private

      # An author of the lesson cannot review it; the same session may review a later revision, never the same twice.
      def reviewer_ok?(session)
        held = LessonSessions.new(@lesson).conflicts(session.id, "reviewer")
        if held.any?
          refuse("E-SESSION-NOT-INDEPENDENT", "X-Banco-Session", "session #{session.id} already acted as #{held.join(' and ')} on #{@lesson.key}: the reviewer must be another session", next_session, 422)
          return false
        end
        if @revision.reviews.exists?(agent_session_id: session.id)
          refuse("E-SESSION-NOT-INDEPENDENT", "X-Banco-Session", "session #{session.id} has already reviewed revision #{@revision.id}", next_session, 422)
          return false
        end
        true
      end

      # The author of the lesson reads the page of a revision it wrote.
      def author_read?
        raw = request.headers["X-Banco-Session"].to_s
        session = AgentSession.find_by(id: raw) if raw.match?(AgentSession::ID)
        return false unless session&.role == "author" && (session.token_id.nil? || session.token_id == @token.id)

        ApiToken.session_roles(@token.role).include?("author") && LessonSessions.new(@lesson).ids("author").include?(session.id)
      end

      # The full text of each cited line of the programme (what the lesson says it comes from).
      def programme_lines
        @revision.body["refs"].filter_map do |ref|
          source = SyllabusSource.find_by(key: ref["source"]) or next
          line = SyllabusLine.find_by(syllabus_source: source, number: ref["line"]) or next
          { source: ref["source"], line: ref["line"], text: line.text }
        end
      end

      def skills(keys)
        context = Validation::CourseContext.for(@lesson.subject)
        graph = Course::State.latest_graph(@lesson.subject)&.then { |g| JSON.parse(g.body_json)["skills"].map { |s| s["key"] } } || []
        Array(keys).map do |key|
          skill = context.skill(key) || {}
          { key: key, label_it: skill["label_it"], source: graph.include?(key) ? "graph" : "course",
            errors: Array(skill["errors"]).map { |e| { code: e["code"], description_it: e["description_it"] } } }
        end
      end

      def next_session = "banco session new --role reviewer --agent NAME --model MODEL"

      def load_revision
        @revision = LessonRevision.find_by(id: params[:revision])
        return refuse("E-NOT-FOUND", "revision", "no lesson revision #{params[:revision].to_s.first(20).inspect}", "banco lessons list --subject KEY", 404) unless @revision

        @lesson = @revision.lesson
      end
    end
  end
end
