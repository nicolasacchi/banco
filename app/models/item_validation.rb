class ItemValidation < ApplicationRecord
  include Searchable

  belongs_to :item_revision

  WAITING_FOR_VERIFIER = %w[E-VERIFY-MISSING E-VERIFY-STALE].freeze

  # Failed only for the missing or stale verify.mjs: the item is clean, a verifier is next (D-141).
  def awaiting_verifier?
    status == "failed" && (codes = JSON.parse(codes_json || "[]")).any? && (codes - WAITING_FOR_VERIFIER).empty?
  end

  # Failed only because Chrome timed out inside the page on every attempt (RevisionValidation#record_timeout): the server's limit, not what the author wrote,
  # so the verdict is not final (ValidateItemRevisionJob draws it again; the author may ask: `banco work retry REV`).
  def timeout_only?
    status == "failed" && JSON.parse(codes_json || "[]") == [ "E-GEN-TIMEOUT" ] && JSON.parse(findings_json || "[]").all? { |f| f.dig("detail", "server_limit") == true }
  end

  # How many verdicts at the end of the revision's rows are timeout-only failures (the job stops asking again after ValidateItemRevisionJob::TIMEOUT_DRAWS).
  def self.timeout_streak(revision)
    where(item_revision_id: revision.id, status: %w[passed failed]).order(:seq).to_a.reverse.take_while(&:timeout_only?).size
  end

  # What `banco status`, `banco items list` and `banco work status` show (D-157); the stored status stays failed.
  def display_status = awaiting_verifier? ? "awaiting_verifier" : status
end
