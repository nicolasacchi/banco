module Api
  module V1
    # The content agent's cycle on one item (A-04, A-06, E-05): open the item, write
    # files, submit them, read the validation. No endpoint approves anything.
    class WorkController < Api::BaseController
      # The answers carry teacher_comments: what the teacher sent back on any revision of
      # the item ("Rimanda": reason code and comment), oldest first.
      #
      # GET /api/v1/work/items/:item?role=author|verifier
      # The author gets every file. The verifier gets item.json, verify.mjs (if
      # any), the tests and every stored instance (the whole pool) with their expected answers: never generator.mjs.
      # The role is the session's (A-04): a verifier session gets the verifier's view
      # whatever the query says, and a session that already authored the item cannot
      # open it as its verifier.
      def open
        item = Item.find_by(key: params[:item])
        return refuse("E-NOT-FOUND", "item", "no item #{params[:item].to_s.first(64).inspect}", "write item.json and run banco work submit DIR --item KEY", 404) unless item

        role = params[:role].presence || (current_session_role || "author")
        return refuse("E-FILES", "role", "role is author or verifier", "banco work open ITEM --role verifier", 422) unless %w[author verifier].include?(role)

        if role == "verifier" || current_session_role
          session = require_session(role, next_step: "banco session new --role #{role} --agent NAME --model MODEL") or return
          held = ItemSessions.new(item).conflicts(session.id, role)
          return refuse("E-SESSION-NOT-INDEPENDENT", "X-Banco-Session", "session #{session.id} already acted as #{held.join(' and ')} on #{item.key}", "banco session new --role #{role} --agent NAME --model MODEL", 422) if held.any?
        end

        revision = item.latest_revision
        body = { item: item.key, subject: item.subject.key, kind: item.kind, role: role, revision_id: revision.id, seq: revision.seq,
                 base: revision.id, status: revision.status, brief: brief_row }
        body.merge!(role == "verifier" ? verifier_view(revision) : { files: revision.files })
        render json: body.merge(validation: validation_row(revision), teacher_comments: Teacher::SendBacks.for_item(item))
      end

      # POST /api/v1/work/submit {item, base, files}. X-Banco-Dry-Run: 1 validates in
      # the request and writes nothing.
      def submit
        body = parse_json_body or return
        session = require_session("author", "verifier") or return
        submission = Validation::Submission.new(key: body["item"], base: body["base"], files: body["files"], session: session).prepare!
        return dry_run(submission) if dry_run?

        revision, replayed = submission.store!(brief_sha256: Brief.find("diagnosis-item")&.sha256)
        ValidateItemRevisionJob.perform_later(revision.id) unless replayed
        render json: { item: revision.item.key, revision_id: revision.id, seq: revision.seq, status: revision.status, replayed: replayed,
                       next: "banco work status #{revision.id} --wait" }, status: replayed ? :ok : :accepted
      rescue Validation::Submission::Refused => e
        refuse(e.code, e.field, e.message, e.next_step, e.http)
      end

      # GET /api/v1/work/revisions/:revision
      def status
        revision = ItemRevision.find_by(id: params[:revision])
        return refuse("E-NOT-FOUND", "revision", "no revision #{params[:revision].to_s.first(20).inspect}", "banco work open ITEM", 404) unless revision

        settled = settled?(revision) ? true : false
        # An unsettled `error` is one failed attempt (Chrome busy or slow); the job tries again by itself.
        render json: { revision_id: revision.id, item: revision.item.key, seq: revision.seq, status: revision.status,
                       settled: settled, retrying: revision.status == "error" && !settled, instances: revision.instances.count,
                       teacher_comments: Teacher::SendBacks.for_item(revision.item) }.merge(validation_row(revision) || {})
      end

      private

      # The role of the session in X-Banco-Session when it is a work role, else nil.
      def current_session_role
        raw = request.headers["X-Banco-Session"].to_s
        found = raw.match?(AgentSession::ID) ? AgentSession.find_by(id: raw) : nil
        role = found.role if found && (found.token_id.nil? || found.token_id == @token.id)
        role if %w[author verifier].include?(role)
      end

      def dry_run(submission)
        result = Validation::DryRun.call(submission.subject, submission.files)
        findings = result.findings.map(&:to_h)
        if result.passed?
          render json: { dry_run: true, status: "passed", codes: [], warnings: result.findings.warnings.map(&:to_h), instances: result.instances.size, details: result.details }
        else
          first = result.findings.errors.first
          refuse(first.code, first.field, first.message, "fix the files and run banco work submit DIR --dry-run again", 422,
                 dry_run: true, status: "failed", codes: result.codes, findings: findings, instances: result.instances.size)
        end
      rescue Validation::ChromeRunner::Busy
        refuse("E-CHROME-BUSY", "chrome", "Chrome is busy", "retry in 30 s", 409)
      rescue Validation::ChromeRunner::Unavailable, Validation::ChromeRunner::Timeout, Validation::Roundtrip::Unavailable => e
        refuse("E-CHROME-UNAVAILABLE", "chrome", "Chrome or the grader did not answer: #{e.message.first(120)}", "retry in 30 s; banco health", 503)
      end

      def verifier_view(revision)
        files = revision.files.except("generator.mjs")
        instances = revision.instances.order(:id).map do |i|
          { seed: i.seed, display: JSON.parse(i.display_json), answer: JSON.parse(i.answer_json),
            errors: i.errors_json && JSON.parse(i.errors_json), solution: i.solution_json && JSON.parse(i.solution_json) }
            .tap { |row| row[:accept] = JSON.parse(i.accept_json) if i.accept_json.present? }
        end
        item = JSON.parse(revision.body_json)
        { files: files, instances: instances, tests: item["tests"],
          note: instances.empty? ? "no instances yet: the author's revision is still validating" : nil }.compact
      end

      def validation_row(revision)
        v = revision.latest_validation or return nil
        findings = v.findings_json ? JSON.parse(v.findings_json) : []
        { codes: JSON.parse(v.codes_json || "[]"), findings: findings, rules_version: v.rules_version, harness_version: v.harness_version,
          chrome_version: v.chrome_version, attempt: v.attempt, validated_at: v.created_at }
      end

      # passed and failed are final; an error is final only after the last retry.
      def settled?(revision)
        v = revision.latest_validation
        v && (%w[passed failed].include?(v.status) || v.attempt.to_i >= ValidateItemRevisionJob::ATTEMPTS)
      end

      def brief_row
        brief = Brief.find("diagnosis-item") or return nil
        { name: brief.name, version: brief.version, sha256: brief.sha256 }
      end
    end
  end
end
