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
        session = require_session("reviewer", item: @item, next_step: next_session) or return
        return unless independent_role?(session, @item, "reviewer")

        render json: { revision_id: @revision.id, item: @item.key, subject: @item.subject.key, seq: @revision.seq, status: @revision.status,
                       item_json: JSON.parse(@revision.body_json), instances: @text.review_instances, programme_lines: @text.programme_lines,
                       checklist: Review::Checklist.all, brief: brief_row("review"),
                       next: "write banco.review/1 (banco brief show review) and run banco review submit #{@revision.id} --file review.json" }
      end

      # POST /api/v1/revisions/:revision/review {review}
      def submit
        body = parse_json_body or return
        session = require_session("reviewer", item: @item, next_step: next_session) or return
        return unless independent_role?(session, @item, "reviewer") && latest_and_passed?(@revision, @item)

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
