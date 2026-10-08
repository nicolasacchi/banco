module Api
  module V1
    # The author's side of the findings (D-220). A finding of a review or a blind solve is a
    # possible problem; the teacher decides who is right, in the browser. Here the author reads
    # the blocker and major findings of a subject and answers each one: the item is right (with a
    # short proof) or a later revision fixes it. A response never disposes of a finding.
    class FindingsController < Api::BaseController
      include IndependentRoles

      KEYS = %w[stance revision_id note_it].freeze

      # GET /api/v1/subjects/:subject/findings[?open=1]
      # Blocker and major findings of the subject, newest revision last, with the teacher's
      # disposition and the latest response. open=1: no disposition yet and no response yet.
      def index
        subject = Subject.find_by(key: params[:subject].to_s)
        return refuse("E-NOT-FOUND", "subject", "no subject #{params[:subject].to_s.first(40).inspect}", "banco status", 404) unless subject

        findings = ReviewFinding.must_be_disposed.joins(item_revision: :item).where(items: { subject_id: subject.id })
                                .includes(item_revision: :item).order(:id).to_a
        dispositions = ReviewFinding.dispositions
        responses = FindingResponse.latest_for(findings.map(&:id))
        latest = Item.where(subject: subject).includes(:revisions).to_h { |i| [ i.id, i.revisions.map(&:seq).max ] }
        rows = findings.map do |f|
          rev = f.item_revision
          { finding_id: f.id, item: rev.item.key, revision_id: rev.id, seq: rev.seq, current: rev.seq == latest[rev.item_id],
            severity: f.severity, source: f.source, instance: f.instance, problem_it: f.problem_it, fix_it: f.fix_it,
            disposition: dispositions[f.id], response: responses[f.id]&.to_h }.compact
        end
        rows = rows.select { |r| r[:disposition].nil? && r[:response].nil? } if params[:open].to_s.in?(%w[1 true])
        render json: { subject: subject.key, rows: rows,
                       next: "answer each open row: banco findings respond FINDING_ID --file response.json (banco brief show diagnosis-item)" }
      end

      # POST /api/v1/findings/:id/responses {response: {stance, revision_id?, note_it}}
      def respond
        finding = ReviewFinding.find_by(id: params[:finding])
        return refuse("E-NOT-FOUND", "finding", "no finding #{params[:finding].to_s.first(20).inspect}", "banco findings list --subject SUBJECT", 404) unless finding

        body = parse_json_body or return
        item = finding.item_revision.item
        session = require_session("author", item: item, next_step: "banco session new --role author --agent NAME --model MODEL") or return
        return unless allowed_author?(session, finding, item)

        doc = body["response"]
        return refuse("E-FILES", "response", "send the answer as {response: {...}}", next_step(finding), 422) unless doc.is_a?(Hash)

        ok, revision = checked_revision(doc, finding, item)
        return unless ok

        note = doc["note_it"]
        return unless checked_note(note, finding)
        return render json: { dry_run: true, status: "passed", codes: [] } if dry_run?

        row = FindingResponse.create!(review_finding: finding, agent_session: session, stance: doc["stance"], item_revision: revision, note_it: note.strip)
        render json: row.to_h.merge(disposition: finding.disposition,
                                    next: "stop here: only the teacher decides about the finding, in the browser (banco status)"), status: :created
      end

      private

      def next_step(finding) = "banco findings respond #{finding.id} --file response.json"

      # An author-role session that did not raise the finding and holds no other role on the item.
      def allowed_author?(session, finding, item)
        if finding.raised_by_session_id == session.id
          refuse("E-SESSION-NOT-INDEPENDENT", "X-Banco-Session", "session #{session.id} raised finding #{finding.id}: the author must be another session",
                 "banco session new --role author --agent NAME --model MODEL", 422)
          return false
        end
        held = ItemSessions.new(item).conflicts(session.id, "author")
        return true if held.empty?

        refuse("E-SESSION-NOT-INDEPENDENT", "X-Banco-Session", "session #{session.id} already acted as #{held.join(' and ')} on #{item.key}: the author must be another session",
               "banco session new --role author --agent NAME --model MODEL", 422)
        false
      end

      # [ok, revision]: the revision of a fixed answer (nil for item_right). On a problem it answers 422 and ok is false.
      def checked_revision(doc, finding, item)
        extra = doc.keys - KEYS
        return bad("response/#{extra.first}", "the answer has only #{KEYS.join(', ')}", finding) if extra.any?

        stance = doc["stance"]
        return bad("response/stance", "stance is item_right or fixed", finding) unless FindingResponse::STANCES.include?(stance)

        raw = doc["revision_id"]
        if stance == "item_right"
          return [ true, nil ] if raw.nil?

          return bad("response/revision_id", "item_right has no revision_id", finding)
        end
        id = raw.to_s
        revision = ItemRevision.find_by(id: id) if id.match?(AgentSession::ID)
        unless revision && revision.item_id == item.id && revision.seq > finding.item_revision.seq
          return bad("response/revision_id", "fixed needs revision_id: a later revision of #{item.key} than revision #{finding.item_revision.id} (seq #{finding.item_revision.seq})",
                     finding, "banco items list --subject #{item.subject.key} --current")
        end
        [ true, revision ]
      end

      def bad(field, message, finding, next_step = next_step(finding))
        refuse("E-FILES", field, message, next_step, 422)
        [ false, nil ]
      end

      def checked_note(note, finding)
        unless note.is_a?(String) && !note.strip.empty? && note.strip.size <= FindingResponse::MAX_NOTE
          refuse("E-FILES", "response/note_it", "note_it is a text of 1 to #{FindingResponse::MAX_NOTE} characters", next_step(finding), 422)
          return false
        end
        findings = Validation::Findings.new
        Validation::Readability.lint_document({ "note_it" => note }, "response", findings)
        return true unless refuse_findings(findings, "shorten and simplify note_it, then #{next_step(finding)}")

        false
      end
    end
  end
end
