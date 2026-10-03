# The reconciliation of decisions with the ledger (D-08, firm rule 2). It reports
# orphans:
#
#   - a decision without provenance: no teacher login, request id, remote address
#     or banco-teacher group, a kind that DecisionRecorder does not write, or a
#     payload that is not an object;
#   - a state change without a decision row: an attempt grading written by the
#     teacher that no decision names, a student run pinned to a blueprint revision
#     that no approve_blueprint decision approved before the run started, and a
#     student run that started before any release_diagnosis decision.
#
# Matching each decision to a line of the proxy's access log is the host's job
# (bin/reconcile-decisions on the server, later milestone); this class reads only
# the ledger.
class DecisionReconciliation
  Result = Struct.new(:since, :orphans, :items, keyword_init: true) do
    def to_h = { since: since.iso8601, orphans: orphans, unverifiable: 0, proxy_log: "not_checked", items: items }
  end

  # "1d", "36h", "90m" or a bare number of days.
  def self.parse_since(text, now: Time.current)
    match = text.to_s.strip.match(/\A(\d+)([dhm]?)\z/) or raise ArgumentError, "--since is a number with d, h or m (for example 1d)"
    amount = match[1].to_i
    now - { "d" => amount.days, "" => amount.days, "h" => amount.hours, "m" => amount.minutes }.fetch(match[2])
  end

  def self.call(since:) = new(since).call

  def initialize(since)
    @since = since
  end

  def call
    items = provenance_orphans + grading_orphans + run_orphans
    Result.new(since: @since, orphans: items.size, items: items)
  end

  private

  def provenance_orphans
    Decision.where("created_at >= ?", @since).order(:id).filter_map do |d|
      missing = %w[teacher_login request_id remote_addr].select { |f| d[f].to_s.strip.empty? }
      missing << "group" unless d.groups.split(",").include?(EdgeTrust::TEACHER_GROUP)
      missing << "kind" unless DecisionRecorder::KINDS.include?(d.kind)
      missing << "payload" unless JSON.parse(d.payload_json).is_a?(Hash)
      { type: "decision_without_provenance", decision_id: d.id, kind: d.kind, missing: missing } if missing.any?
    rescue JSON::ParserError
      { type: "decision_without_provenance", decision_id: d.id, kind: d.kind, missing: [ "payload" ] }
    end
  end

  # A grading whose source says the teacher wrote it, with no decision that names it.
  def grading_orphans
    named = Decision.pluck(:payload_json).filter_map { |j| (JSON.parse(j)["grading_id"] rescue nil) }.map(&:to_i)
    AttemptGrading.where("created_at >= ?", @since).where(source: "teacher").where.not(id: named).order(:id).map do |g|
      { type: "state_change_without_decision", table: "attempt_gradings", id: g.id }
    end
  end

  def run_orphans
    release = Decision.where(kind: "release_diagnosis").minimum(:created_at)
    DiagnosisRun.joins(:student).where(students: { kind: "student" }).where("diagnosis_runs.created_at >= ?", @since).order(:id).filter_map do |run|
      if release.nil? || run.created_at < release
        { type: "state_change_without_decision", table: "diagnosis_runs", id: run.id, reason: "started before release_diagnosis" }
      elsif !approved_before?(run)
        { type: "state_change_without_decision", table: "diagnosis_runs", id: run.id, reason: "pinned to a blueprint revision the teacher did not approve" }
      end
    end
  end

  def approved_before?(run)
    Decision.where(kind: "approve_blueprint", subject_id: run.subject_id).where("created_at <= ?", run.created_at).any? do |d|
      JSON.parse(d.payload_json)["revision_id"] == run.blueprint_revision_id
    end
  end
end
