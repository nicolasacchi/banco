module Api
  module V1
    # The author's side of the findings (D-220). A finding of a review or a blind solve is a
    # possible problem; the teacher decides who is right, in the browser. Here the author reads
    # the blocker and major findings of a subject and answers each one: the item is right (with a
    # short proof) or a later revision fixes it. A response never disposes of a finding.
    #
    # The third reviewer, the arbiter (D-222), reads a finding with the item and the author's answer and
    # says who is right. Two opinions count, the first and the second (two models), and the second must
    # be written independently: an arbiter session does not see the assessments of a finding before it has
    # written its own. An assessment never writes a decision: the teacher decides, in the browser.
    class FindingsController < Api::BaseController
      include IndependentRoles

      KEYS = %w[stance revision_id note_it].freeze
      ASSESS_KEYS = %w[verdict note_it].freeze

      # GET /api/v1/subjects/:subject/findings[?open=1][&all=1]
      # Blocker and major findings of the subject (all=1: minor ones too, for the third reviewer), newest revision last, with the teacher's
      # disposition, the latest response of the author and the third reviewer's opinion (the first and the second assessment). The assessments are shown only to a valid
      # session that is not an arbiter still to assess that finding (else a count only). open=1: no disposition yet, no response yet,
      # and on the current or a pinned revision (not a superseded one).
      def index
        subject = Subject.find_by(key: params[:subject].to_s)
        return refuse("E-NOT-FOUND", "subject", "no subject #{params[:subject].to_s.first(40).inspect}", "banco status", 404) unless subject

        scope = params[:all].to_s.in?(%w[1 true]) ? ReviewFinding.all : ReviewFinding.must_be_disposed
        findings = scope.joins(item_revision: :item).where(items: { subject_id: subject.id })
                                .includes(item_revision: :item).order(:id).to_a
        dispositions = ReviewFinding.dispositions
        responses = FindingResponse.latest_for(findings.map(&:id))
        opinions = FindingAssessment.opinions_for(findings.map(&:id))
        viewer = viewer_session
        latest = Item.where(subject: subject).includes(:revisions).to_h { |i| [ i.id, i.revisions.map(&:seq).max ] }
        pinned = BlueprintRevision.where(subject: subject).order(:seq).last&.pinned_item_revision_ids.to_a
        rows = findings.map do |f|
          rev = f.item_revision
          { finding_id: f.id, item: rev.item.key, revision_id: rev.id, seq: rev.seq, current: rev.seq == latest[rev.item_id],
            severity: f.severity, source: f.source, instance: f.instance, problem_it: f.problem_it, fix_it: f.fix_it,
            disposition: dispositions[f.id], response: responses[f.id]&.to_h, opinion: visible_opinion(opinions[f.id], viewer) }.compact
        end
        rows = rows.select { |r| r[:disposition].nil? && r[:response].nil? && (r[:current] || pinned.include?(r[:revision_id])) } if params[:open].to_s.in?(%w[1 true])
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
        return unless checked_note(note, FindingResponse::MAX_NOTE, "response", next_step(finding))
        return render json: { dry_run: true, status: "passed", codes: [] } if dry_run?

        row = FindingResponse.create!(review_finding: finding, agent_session: session, stance: doc["stance"], item_revision: revision, note_it: note.strip)
        render json: row.to_h.merge(disposition: finding.disposition,
                                    next: "stop here: only the teacher decides about the finding, in the browser (banco status)"), status: :created
      end

      # POST /api/v1/findings/:id/assessments {assessment: {verdict, note_it}}
      def assess
        finding = ReviewFinding.find_by(id: params[:finding])
        return refuse("E-NOT-FOUND", "finding", "no finding #{params[:finding].to_s.first(20).inspect}", "banco findings list --subject SUBJECT --all", 404) unless finding

        body = parse_json_body or return
        item = finding.item_revision.item
        session = require_session("arbiter", item: item, finding: finding, next_step: "banco session new --role arbiter --agent NAME --model MODEL") or return
        return unless allowed_arbiter?(session, item)

        doc = body["assessment"]
        step = assess_step(finding)
        return refuse("E-FILES", "assessment", "send the opinion as {assessment: {verdict, note_it}}", step, 422) unless doc.is_a?(Hash)

        extra = doc.keys - ASSESS_KEYS
        return refuse("E-FILES", "assessment/#{extra.first}", "the opinion has only #{ASSESS_KEYS.join(', ')}", step, 422) if extra.any?
        return refuse("E-FILES", "assessment/verdict", "verdict is #{FindingAssessment::VERDICTS.join(', ')}", step, 422) unless FindingAssessment::VERDICTS.include?(doc["verdict"])
        return unless checked_note(doc["note_it"], FindingAssessment::MAX_NOTE, "assessment", step)
        return render json: { dry_run: true, status: "passed", codes: [] } if dry_run?

        row = FindingAssessment.create!(review_finding: finding, agent_session: session, verdict: doc["verdict"], note_it: doc["note_it"].strip)
        render json: row.to_h.merge(next: "stop here: the teacher decides, in the browser; the second opinion is another model's job"), status: :created
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

      def checked_note(note, max, doc_name, step)
        unless note.is_a?(String) && !note.strip.empty? && note.strip.size <= max
          refuse("E-FILES", "#{doc_name}/note_it", "note_it is a text of 1 to #{max} characters", step, 422)
          return false
        end
        findings = Validation::Findings.new
        Validation::Readability.lint_document({ "note_it" => note }, doc_name, findings)
        return true unless refuse_findings(findings, "shorten and simplify note_it, then #{step}")

        false
      end

      def assess_step(finding) = "banco findings assess #{finding.id} --file assessment.json"

      # An arbiter session that holds no other role on the item. Judging many findings of one item is fine.
      def allowed_arbiter?(session, item)
        held = ItemSessions.new(item).conflicts(session.id, "arbiter")
        return true if held.empty?

        refuse("E-SESSION-NOT-INDEPENDENT", "X-Banco-Session", "session #{session.id} already acted as #{held.join(' and ')} on #{item.key}: the arbiter must be another session",
               "banco session new --role arbiter --agent NAME --model MODEL", 422)
        false
      end

      # The session of the request when it is a valid one of this token, else nil (no error answered).
      def viewer_session
        raw = request.headers["X-Banco-Session"].to_s
        session = AgentSession.find_by(id: raw) if raw.match?(AgentSession::ID)
        session if session && (session.token_id.nil? || session.token_id == @token.id)
      end

      # The opinion on a finding as the viewer may read it (D-222). The second opinion is written
      # independently, so the assessments go only to a valid session of this token that is not an
      # arbiter still to assess this finding: the author, a reviewer or operator session, or an arbiter that
      # has assessed it itself. Without a valid session, or for an arbiter that has not assessed it, only
      # the count of the opinions given is shown.
      def visible_opinion(opinion, viewer)
        return nil unless opinion.any?
        return { hidden: true, count: opinion.given.size } if viewer.nil? || (viewer.role == "arbiter" && opinion.given.none? { |a| a.agent_session_id == viewer.id })

        { state: opinion.state, verdict: opinion.verdict, first: opinion.first&.to_h, second: opinion.second&.to_h }.compact
      end
    end
  end
end
