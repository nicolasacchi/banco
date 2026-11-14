module Api
  module V1
    # The teacher's decisions over the API (D-327, the exception to firm rule 2): a bot with a teacher token records the
    # decisions the operator tells it to, and reads them back for audit. The bot_read token reads the list and never
    # decides; a content agent's token does neither.
    #
    # POST goes through DecisionConsole, so through DecisionRecorder and every gate of the kind: BANCO_DECISIONS_ENABLED,
    # a teacher of BANCO_TEACHER_USERS (the token's login), the business guards, and the attestation words that only the
    # console and this API accept. The origin is DecisionRecorder::Api: the row says api and the payload names the token.
    # Without confirm: true it is a dry run, exactly like the console's: the whole recorder runs inside a savepoint that
    # is rolled back and the answer shows the payload.
    class DecisionsController < Api::BaseController
      include TeacherApi

      self.teacher_writes = true

      LIMIT = 100
      MAX_LIMIT = 500

      before_action(only: :index) { require_token_roles("bot_read", "teacher") }
      before_action(only: :create) { require_token_roles("teacher") }

      # GET /api/v1/decisions[?since=ID][&limit=N][&kind=KIND]: recorded decisions with an id above since, oldest first.
      def index
        since = integer_param(:since, 0) or return
        limit = integer_param(:limit, LIMIT) or return
        limit = limit.clamp(1, MAX_LIMIT)
        scope = Decision.where("id > ?", since).order(:id)
        scope = scope.where(kind: params[:kind].to_s) if params[:kind].present?
        rows = scope.includes(:subject, :student).limit(limit + 1).to_a
        more = rows.size > limit
        rows = rows.first(limit)
        render json: { decisions: rows.map { |d| row(d) }, more: more, next_since: (rows.last&.id || since),
                       next: "banco decisions --since #{rows.last&.id || since}" }
      end

      # POST /api/v1/decisions {kind, params, reason_it, attest_it, confirm}
      def create
        body = parse_json_body or return
        kind = body["kind"]
        return refuse("E-FILES", "kind", "kind is one of #{DecisionRecorder::KINDS.join(', ')}", "banco decide KIND --params JSON", 422) unless kind.is_a?(String) && kind.present?

        extra = body.fetch("params", {})
        return refuse("E-FILES", "params", "params is a JSON object (the other parameters of the kind)", "banco decide #{kind} --params JSON", 422) unless extra.is_a?(Hash)

        confirm = body.fetch("confirm", false)
        return refuse("E-FILES", "confirm", "confirm is true or false", "banco decide #{kind} --confirm", 422) unless [ true, false ].include?(confirm)

        reason, attest = body["reason_it"], body["attest_it"]
        return refuse("E-FILES", "reason_it", "reason_it is a string", "banco decide #{kind} --reason TEXT", 422) unless reason.nil? || reason.is_a?(String)
        return refuse("E-FILES", "attest_it", "attest_it is a string", "banco decide #{kind} --attest TEXT", 422) unless attest.nil? || attest.is_a?(String)

        confirm &&= !dry_run? # the dry-run header wins
        result = DecisionConsole.call(kind: kind, subject: extra["subject"], reason: reason, params: extra, attest_it: attest, confirm: confirm, origin: teacher_origin)
        return answer_failure(result, invalid_code: "E-DECISION-INVALID", next_step: "banco decide #{kind} --params JSON") unless result.ok

        if result.recorded
          render json: { recorded: true, dry_run: false, kind: kind, decision: row(result.decision), payload: result.payload }, status: :created
        else
          render json: { recorded: false, dry_run: true, kind: kind, allowed: true, reasons: [], payload: result.payload,
                         next: "send the same request with confirm: true (banco decide #{kind} --confirm) to record it" }
        end
      end

      private

      def row(decision)
        payload = JSON.parse(decision.payload_json)
        { id: decision.id, kind: decision.kind, subject: decision.subject&.key, student: decision.student&.key, payload: payload, via: decision.via,
          teacher: decision.teacher_login, token: payload["token"], created_at: decision.created_at.utc.iso8601 }.compact
      end

      def integer_param(name, default)
        raw = params[name]
        return default if raw.blank?
        return Integer(raw.to_s, 10) if raw.to_s.match?(/\A\d{1,15}\z/)

        refuse("E-FILES", name.to_s, "#{name} is a whole number", "banco decisions --since 0", 422)
        nil
      end
    end
  end
end
