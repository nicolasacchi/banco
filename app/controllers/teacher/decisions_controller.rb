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

    before_action :check_csrf
    before_action :allow_decisions!

    PERMITTED = %i[revision_id finding_id disposition reason_it grade_proposal_id attempt_id verdict error_code run_id
                   item_revision_id acknowledged statement_it subject skill override_kind reason_code comment_it back].freeze

    {
      approve_skill_graph: "approve_skill_graph", approve_blueprint: "approve_blueprint", confirm_test_reviewed: "confirm_test_reviewed", dispose_finding: "dispose_finding",
      confirm_grade: "confirm_grade", reject_grade: "reject_grade", resolve_attempt: "resolve_attempt",
      void_run: "void_diagnosis_run", extend_run: "extend_diagnosis_run", close_run: "close_diagnosis_run",
      void_revision_attempts: "void_revision_attempts", release: "release_diagnosis", consent: "record_consent",
      kind_override: "kind_override", send_back_item: "send_back_item"
    }.each do |action, kind|
      define_method(action) { decide(kind) }
    end

    private

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
