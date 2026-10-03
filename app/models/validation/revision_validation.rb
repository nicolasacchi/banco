module Validation
  # Validates one stored item revision and appends what it found: the
  # item_validations row and, when the instances are clean, the item_instances
  # rows (append-only; once per revision). It runs the ItemRunner outside any
  # database transaction (the grader and Chrome can wait), then writes in one short
  # transaction. Infrastructure trouble is raised, never written as a verdict; the
  # job records it as an `error` row and retries.
  class RevisionValidation
    def initialize(revision, attempt: 1)
      @revision = revision
      @attempt = attempt
    end

    def call
      subject = @revision.item.subject
      files = @revision.files
      result = ItemRunner.new(files: files, context: CourseContext.for(subject), harness_token: Harness.issue("rev", @revision.id),
                              chrome: { wait: Rules.get(:generator, :batch_timeout_seconds) * 60 }).call
      persist(result)
    end

    # An infrastructure failure of one attempt: an `error` row, never a pass.
    def record_error(error)
      append(status: "error", codes: [], findings: [ { code: nil, message: "#{error.class}: #{error.message}".first(300) } ])
    end

    # The last attempt timed out inside the page: the generator is what is slow.
    def record_timeout(error)
      Findings # Zeitwerk loads lib/validation/findings.rb through this name; it also defines Validation::Finding
      finding = Finding.new(code: "E-GEN-TIMEOUT", field: "/generator.mjs", message: "the harness timed out: #{error.message}".first(300), detail: {})
      append(status: "failed", codes: [ "E-GEN-TIMEOUT" ], findings: [ finding.to_h ])
    end

    private

    def persist(result)
      ItemValidation.transaction do
        insert_instances(result.instances) if result.instances.any? && !@revision.instances.exists?
        append(status: result.status, codes: result.codes, findings: result.findings.map(&:to_h), result: result)
      end
    end

    def insert_instances(instances)
      now = Time.current
      ItemInstance.insert_all!(instances.map do |i|
        { item_revision_id: @revision.id, seed: i[:seed], display_json: JSON.generate(i[:display]), answer_json: JSON.generate(i[:answer]),
          errors_json: i[:errors].nil? ? nil : JSON.generate(i[:errors]), solution_json: i[:solution].nil? ? nil : JSON.generate(i[:solution]),
          fingerprint: i[:fingerprint], created_at: now }
      end)
    end

    def append(status:, codes:, findings:, result: nil)
      seq = (@revision.validations.maximum(:seq) || 0) + 1
      ItemValidation.create!(
        item_revision: @revision, seq: seq, status: status, codes_json: JSON.generate(codes), findings_json: JSON.generate(findings),
        rules_version: Rules.version.to_s, grader_version: Grading.git_sha, harness_version: Harness.version,
        chrome_version: result&.chrome_version, instances_sha256: result&.instances_sha256, attempt: @attempt
      )
    end
  end
end
