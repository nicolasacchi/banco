module Teacher
  # Every decision of the teacher (firm rule 2, D-08). One action per kind, each a
  # POST under /teacher on the web listener (the route constraint makes it a 404 on
  # the API and harness listeners). Nothing is written here: the actions hand the
  # request to DecisionRecorder, the only writer.
  #
  # 403 unless ALL hold: BANCO_DECISIONS_ENABLED=1, a trusted teacher, a valid CSRF
  # token (checked here whatever the environment says about forgery protection) and
  # a computer that is not the student's. 404: no such target. 422: not possible
  # now, with the reasons.
  class DecisionsController < ApplicationController
    skip_forgery_protection

    before_action :require_teacher!
    before_action :check_csrf
    before_action :allow_decisions!

    PERMITTED = %i[revision_id finding_id disposition reason_it grade_proposal_id attempt_id verdict error_code run_id
                   item_revision_id acknowledged statement_it subject skill override_kind reason_code comment_it enabled back].freeze
    # follow_opinions reads params[:pairs] itself.

    {
      approve_skill_graph: "approve_skill_graph", approve_blueprint: "approve_blueprint", confirm_test_reviewed: "confirm_test_reviewed",
      confirm_grade: "confirm_grade", reject_grade: "reject_grade", resolve_attempt: "resolve_attempt",
      void_run: "void_diagnosis_run", extend_run: "extend_diagnosis_run", close_run: "close_diagnosis_run",
      void_revision_attempts: "void_revision_attempts", release: "release_diagnosis", consent: "record_consent",
      kind_override: "kind_override", send_back_item: "send_back_item", set_formula_sheet: "set_formula_sheet"
    }.each do |action, kind|
      define_method(action) { decide(kind) }
    end

    # One finding: the form of "Segui il parere" also posts follow_verdict, the verdict the teacher saw; it is
    # re-checked here like in the bulk route (decided meanwhile, opinion changed, revision no longer in use).
    def dispose_finding
      verdict = params[:follow_verdict].to_s
      if verdict.present?
        finding = ReviewFinding.find_by(id: Integer(params[:finding_id].to_s, exception: false))
        why = follow_blocker(finding, verdict) if finding
        return refuse_with("opinion not followed", :unprocessable_entity, [ I18n.t("teacher.follow.skipped_#{why}", id: finding.id) ]) if why
      end
      decide("dispose_finding")
    end

    # "Segui il parere su questi M" (D-222): one dispose_finding decision per listed finding, each
    # through DecisionRecorder with every guard, in the teacher's own request. A pair "finding:verdict"
    # is the line the teacher saw. A finding decided meanwhile, one whose two opinions are no longer
    # clear or no longer say that, a minor one, and one of another subject are skipped and reported.
    def follow_opinions
      subject = Subject.find_by(key: params[:subject].to_s) or return render(plain: "Not Found", status: :not_found)
      pairs = Array(params[:pairs]).map(&:to_s).first(200)
      lines = pairs.each_with_index.map { |pair, i| follow_one(subject, pair, i) }
      done = lines.count { |l| l[:done] }
      text = "#{I18n.t('teacher.follow.summary', done: done, skipped: lines.size - done)} #{lines.map { |l| l[:text] }.join(' ')}"
      if json_caller?
        render json: { ok: true, decided: done, skipped: lines.size - done, lines: lines.map { |l| l[:text] } }
      else
        redirect_to back_path, status: :see_other, notice: text.first(1500)
      end
    rescue DecisionRecorder::Refused
      render plain: "Forbidden", status: :forbidden
    end

    private

    def follow_one(subject, pair, index)
      id, verdict = pair.split(":", 2)
      finding = ReviewFinding.find_by(id: Integer(id, exception: false)) if id.to_s.match?(/\A[1-9]\d{0,17}\z/)
      return { done: false, text: I18n.t("teacher.follow.unknown", id: id.to_s.first(20)) } unless finding

      skipped = ->(why) { { done: false, text: I18n.t("teacher.follow.skipped_#{why}", id: finding.id) } }
      return skipped.call(:subject) unless finding.item_revision.item.subject_id == subject.id && finding.severity != "minor"
      why = follow_blocker(finding, verdict)
      return skipped.call(why) if why

      opinion = finding.opinion
      DecisionRecorder.call(request: request, kind: "dispose_finding", request_id: "#{request.request_id.presence || SecureRandom.uuid}/#{index}",
                            params: { finding_id: finding.id, disposition: opinion.disposition, reason_it: I18n.t("teacher.skill.follow_reason") })
      { done: true, text: I18n.t("teacher.follow.done", id: finding.id) }
    rescue DecisionRecorder::Missing, DecisionRecorder::Invalid, ActiveRecord::RecordNotUnique
      { done: false, text: I18n.t("teacher.follow.skipped_invalid", id: id.to_s.first(20)) }
    end

    # nil when a clear opinion with this verdict may be followed now, else :decided, :stale or :changed.
    def follow_blocker(finding, verdict)
      return :decided if finding.disposed?
      return :stale unless live_revision?(finding.item_revision)

      opinion = finding.opinion
      opinion.clear? && opinion.verdict == verdict ? nil : :changed
    end

    # The revision is the current one of its item or pinned by the latest blueprint of the subject.
    def live_revision?(revision)
      item = revision.item
      return true if revision.seq == item.revisions.maximum(:seq)

      BlueprintRevision.where(subject_id: item.subject_id).order(:seq).last&.pinned_item_revision_ids.to_a.include?(revision.id)
    end

    def check_csrf
      request.env[DecisionRecorder::CSRF_KEY] = any_authenticity_token_valid?
    end

    def allow_decisions!
      reason = DecisionRecorder.refusal(request)
      return unless reason

      Rails.logger.info("decision refused: #{reason}")
      render plain: "Forbidden", status: :forbidden
    end

    # JSON callers (tests, scripts) get JSON. The teacher's forms get a redirect back to the
    # page they came from, with a sentence in Italian: what was recorded, or why not.
    def decide(kind)
      params_in = params.permit(*PERMITTED, scores: {}).to_h
      decision = DecisionRecorder.call(request: request, kind: kind, params: params_in)
      if json_caller?
        render json: { ok: true, decision_id: decision.id, kind: decision.kind }
      else
        redirect_to back_path, status: :see_other, notice: I18n.t("teacher.decided.#{kind}", default: I18n.t("teacher.decided.default"))
      end
    rescue DecisionRecorder::Refused
      render plain: "Forbidden", status: :forbidden
    rescue DecisionRecorder::Missing => e
      refuse_with(e.message, :not_found, [ e.message ], json_reasons: false)
    rescue DecisionRecorder::Invalid => e
      refuse_with("not possible now", :unprocessable_entity, e.reasons)
    rescue ActiveRecord::RecordNotUnique
      refuse_with("this request was already recorded", :conflict, [ "this request was already recorded" ], json_reasons: false)
    end

    def refuse_with(error, status, reasons, json_reasons: true)
      if json_caller?
        render json: json_reasons ? { error: error, reasons: reasons } : { error: error }, status: status
      else
        redirect_to back_path, status: :see_other, alert: reasons.map { |r| Teacher::Wording.italian(r) }.join(" ")
      end
    end

    # A script or a test that speaks JSON (Accept or Content-Type); a browser form does not.
    def json_caller? = request.format.json? || request.content_mime_type&.json?

    # Only a path of the teacher's own pages: never an address from the outside.
    def back_path
      back = params[:back].to_s
      back.match?(%r{\A/teacher(?:/[A-Za-z0-9_.\-/]*)?(?:\?[A-Za-z0-9_=&.\-]*)?\z}) && !back.include?("//") ? back : "/teacher"
    end
  end
end
