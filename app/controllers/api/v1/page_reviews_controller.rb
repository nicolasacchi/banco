module Api
  module V1
    # The review of a page revision (D-289, SPEC B8): one per independent session, banco.page_review/1, eleven points and
    # findings by file. The reviewer receives the manifest, every file, the card, the validation report, the screenshots of
    # every seed and the plain diff; never the course sources. Nothing here approves anything.
    class PageReviewsController < Api::BaseController
      include SubjectScoped

      before_action :load_revision

      # GET /api/v1/page-revisions/:revision/review
      def open
        unless author_read?
          session = require_session("reviewer", item: @page, next_step: next_session) or return
          return unless reviewer_ok?(session)
        end

        latest = @page.latest_revision
        current = latest.id == @revision.id
        render json: { revision_id: @revision.id, page: @page.key, seq: @revision.seq, superseded: !current, manifest: @revision.manifest, files: Review::PageIntake.texts_of(@revision),
                       binary_files: @revision.files.reject { |f| f.path.match?(/\.(mjs|css|svg)\z/) }.map { |f| { path: f.path, bytes: f.bytes } },
                       card: Pages::Card.for(@page.key, @page.subject), validation: Pages::Validations.summary(@revision).merge(shots_url: "/api/v1/page-revisions/#{@revision.id}/shots"),
                       diff: Pages::Diff.between(@revision), checklist: Review::PageChecklist.all, brief: brief_row("page-review"),
                       next: current ? "look at the screenshots (banco page shots #{@revision.id} --dir D), write banco.page_review/1 (banco brief show page-review) and run banco page-review submit #{@revision.id} --file review.json" :
                                       "superseded: a review of this revision cannot be filed; run banco page-review open #{latest.id}" }
      end

      # POST /api/v1/page-revisions/:revision/review {review}
      def submit
        body = parse_json_body or return
        session = require_session("reviewer", item: @page, next_step: next_session) or return
        return unless reviewer_ok?(session)

        latest = @page.latest_revision
        return refuse("E-STALE-BASE", "revision", "revision #{@revision.id} is not the latest of #{@page.key} (#{latest.id})", "banco page-review open #{latest.id}", 409) unless latest.id == @revision.id

        doc = body["review"]
        return refuse("E-FILES", "review", "send the review as {review: {...}}", "banco page-review submit REV --file review.json", 422) unless doc.is_a?(Hash)
        if doc["revision"] && doc["revision"].to_s != @revision.id.to_s
          return refuse("E-FILES", "revision", "the file reviews revision #{doc['revision'].inspect}; you are submitting to revision #{@revision.id}", "banco page-review open #{@revision.id}", 422)
        end

        findings = Review::PageIntake.call(doc, @revision)
        return if refuse_findings(findings, "fix review.json and run banco page-review submit #{@revision.id} --file review.json again", dry_run: dry_run?)
        return render json: { dry_run: true, status: "passed", codes: [], findings: doc["findings"].size } if dry_run?

        review = PageReview.create!(page_revision: @revision, agent_session: session, checklist_json: JSON.generate(doc["checklist"]), findings_json: JSON.generate(doc["findings"]),
                                    brief_sha256: Brief.find("page-review")&.sha256)
        render json: { review_id: review.id, revision_id: @revision.id, findings: doc["findings"], counts: doc["findings"].map { |f| f["severity"] }.tally,
                       next: "stop here: the teacher approves the topic that embeds the page in the browser (banco status)" }, status: :created
      rescue ActiveRecord::RecordNotUnique
        refuse("E-SESSION-NOT-INDEPENDENT", "X-Banco-Session", "session #{session.id} has already reviewed revision #{@revision.id}", next_session, 422)
      end

      private

      # A reviewer wrote no revision of the page, is on another model than every author (Providers.refusal) and has not reviewed this revision.
      def reviewer_ok?(session)
        held = PageSessions.new(@page).conflicts(session.id, "reviewer")
        if held.any?
          refuse("E-SESSION-NOT-INDEPENDENT", "X-Banco-Session", "session #{session.id} already acted as #{held.join(' and ')} on #{@page.key}: the reviewer must be another session", next_session, 422)
          return false
        end
        authors = PageSessions.new(@page).sessions("author")
        if (same = authors.find { |a| Providers.family(a.model) == Providers.family(session.model) })
          refuse("E-PROVIDER-NOT-ALLOWED", "X-Banco-Session", "a page reviewer must run on a different model family than every author of the page: session #{same.id} and this one are both #{Providers.family(session.model)} (#{session.model.inspect})",
                 "banco session new --role reviewer --agent NAME --model MODEL (another family than #{Providers.family(same.model)})", 422)
          return false
        end
        if @revision.reviews.exists?(agent_session_id: session.id)
          refuse("E-SESSION-NOT-INDEPENDENT", "X-Banco-Session", "session #{session.id} has already reviewed revision #{@revision.id}", next_session, 422)
          return false
        end
        true
      end

      def author_read?
        raw = request.headers["X-Banco-Session"].to_s
        session = AgentSession.find_by(id: raw) if raw.match?(AgentSession::ID)
        return false unless session&.role == "author" && (session.token_id.nil? || session.token_id == @token.id)

        ApiToken.session_roles(@token.role).include?("author") && PageSessions.new(@page).ids("author").include?(session.id)
      end

      def next_session = "banco session new --role reviewer --agent NAME --model MODEL"

      def load_revision
        @revision = PageRevision.find_by(id: params[:revision])
        return refuse("E-NOT-FOUND", "revision", "no page revision #{params[:revision].to_s.first(20).inspect}", "banco pages list --subject KEY", 404) unless @revision

        @page = @revision.page
      end
    end
  end
end
