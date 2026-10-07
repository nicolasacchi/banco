module Api
  module V1
    # The expert review of an item revision (A-05): open what a reviewer may see,
    # submit banco.review/1. Findings are stored append-only; what the teacher does
    # with them is a decision in the browser. Nothing here approves anything.
    class ReviewsController < Api::BaseController
      include IndependentRoles

      before_action :load_revision

      # GET /api/v1/revisions/:revision/review
      def open
        # Reading needs no session (D-158): the session matters when a review is stored. A header
        # that is sent is still checked, so an error message in the variable is not taken for none.
        if request.headers["X-Banco-Session"].to_s.strip.empty?
          return refuse("E-AUTH", "authorization", "this token cannot review", "banco schema", 403) unless ApiToken.session_roles(@token.role).include?("reviewer")
        elsif author_read?
          # D-211: the author reads the page of a revision (the item it wrote); the findings are in `work open`.
        else
          session = require_session("reviewer", item: @item, next_step: next_session) or return
          return unless independent_role?(session, @item, "reviewer")
        end

        latest = @item.latest_revision
        current = latest.id == @revision.id
        next_step = current ? "write banco.review/1 (banco brief show review) and run banco review submit #{@revision.id} --file review.json" :
                              "superseded: a review of this revision cannot be filed; run banco review open #{latest.id}"
        render json: { revision_id: @revision.id, item: @item.key, subject: @item.subject.key, seq: @revision.seq, status: @revision.status,
                       current: current, superseded_by: current ? nil : latest.id,
                       item_json: JSON.parse(@revision.body_json), instances: @text.review_instances, programme_lines: @text.programme_lines,
                       checklist: Review::Checklist.all, brief: brief_row("review"),
                       next: next_step }
      end

      # An author session of this token that wrote a file of this item reads the page (D-211); no other role does.
      def author_read?
        raw = request.headers["X-Banco-Session"].to_s
        session = AgentSession.find_by(id: raw) if raw.match?(AgentSession::ID)
        return false unless session&.role == "author" && (session.token_id.nil? || session.token_id == @token.id)

        ApiToken.session_roles(@token.role).include?("author") && ItemSessions.new(@item).ids("author").include?(session.id)
      end

      # POST /api/v1/revisions/:revision/review {review}
      def submit
        body = parse_json_body or return
        session = require_session("reviewer", item: @item, next_step: next_session) or return
        return unless independent_role?(session, @item, "reviewer") && latest_and_passed?(@revision, @item, step: "review")

        doc = body["review"]
        return refuse("E-FILES", "review", "send the review as {review: {...}}", "banco review submit REV --file review.json", 422) unless doc.is_a?(Hash)
        if doc["revision"] && doc["revision"].to_s != @revision.id.to_s
          return refuse("E-FILES", "revision", "the file reviews revision #{doc['revision'].inspect}; you are submitting to revision #{@revision.id}", "banco review open #{@revision.id}", 422)
        end

        findings = Review::Intake.call(doc, @text)
        return if refuse_findings(findings, "fix review.json and run banco review submit #{@revision.id} --file review.json again", dry_run: dry_run?)
        return render json: { dry_run: true, status: "passed", codes: [], findings: doc["findings"].size } if dry_run?

        review = ItemReview.transaction do
          row = ItemReview.create!(item_revision: @revision, agent_session: session, checklist_json: JSON.generate(doc["checklist"]),
                                   brief_sha256: Brief.find("review")&.sha256)
          doc["findings"].each do |f|
            ReviewFinding.create!(item_revision: @revision, source: "review", item_review: row, severity: f["severity"], instance: f["instance"],
                                  field: f["field"], quote: f["quote"], problem_it: f["problem_it"], fix_it: f["fix_it"])
          end
          row
        end
        render json: result(review), status: :created
      end

      private

      def result(review)
        gate = Review::Gate.check(@revision)
        { review_id: review.id, revision_id: @revision.id, findings: review.findings.order(:id).map(&:to_h),
          counts: review.findings.group(:severity).count, approvable: gate.approvable, reasons: gate.reasons,
          next: "stop here: the teacher disposes of the findings in the browser (banco status)" }
      end

      def next_session = "banco session new --role reviewer --agent NAME --model MODEL"

      def load_revision
        @revision = ItemRevision.find_by(id: params[:revision])
        return refuse("E-NOT-FOUND", "revision", "no revision #{params[:revision].to_s.first(20).inspect}", "banco work open ITEM", 404) unless @revision

        @item = @revision.item
        @text = Review::ItemText.new(@revision, all: true)
      end
    end
  end
end
