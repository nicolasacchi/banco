# What the rest of the app reads of the validations of a page revision (SPEC B7): the API's status, the topic gate's
# reason, the teacher's line. The rows themselves are PageValidation (append-only).
module Pages
  module Validations
    module_function

    # { status: pending|passed|failed|error, ... }
    def summary(revision)
      row = revision.latest_validation
      return { status: "pending", next: "the job validates the revision soon; ask again with banco page status #{revision.id}" } unless row

      out = { status: row.status, validation_id: row.id, at: row.created_at.utc.iso8601, kit_version: row.kit_version, errors: row.errors_list, warnings: Array(row.result["warnings"]),
              shots: row.shots.size, shots_available: row.shots.count { |s| PageShots.exist?(s["sha256"]) }, elapsed_seconds: row.result["elapsed_seconds"],
              chrome_version: row.chrome_version, harness_version: row.harness_version }
      out[:message] = row.result["message"] if row.status == "error"
      out[:next] = case row.status
      when "passed" then "look at every screenshot: banco page shots #{revision.id} --dir DIR, then another session reviews: banco page-review open #{revision.id}"
      when "failed" then "fix the page named in errors, banco page submit DIR --dry-run, then submit (a new revision is validated again)"
      else "Chrome could not be reached; the job tries again, ask again with banco page status #{revision.id}"
      end
      out
    end

    # The gate's reason for a page revision pinned by a topic's lesson, or nil. The words matter: Teacher::Wording turns them into Italian.
    def gate_reason(revision, key:)
      verdict = revision.passed_validation
      return "the page #{key} (revision #{revision.id}) has not passed validation in Chrome" unless verdict
      return "the page #{key} (revision #{revision.id}) has no review by an independent session" if revision.reviews.empty?

      blockers = revision.reviews.max_by(&:id).findings.count { |f| f["severity"] == "blocker" }
      blockers.positive? ? "the page #{key} (revision #{revision.id}) has #{blockers} blocker finding(s) in its latest review" : nil
    end
  end
end
