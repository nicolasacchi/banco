class ItemValidation < ApplicationRecord
  belongs_to :item_revision

  WAITING_FOR_VERIFIER = %w[E-VERIFY-MISSING E-VERIFY-STALE].freeze

  # Failed only for the missing or stale verify.mjs: the item is clean, a verifier is next (D-141).
  def awaiting_verifier?
    status == "failed" && (codes = JSON.parse(codes_json || "[]")).any? && (codes - WAITING_FOR_VERIFIER).empty?
  end

  # What `banco status`, `banco items list` and `banco work status` show (D-157); the stored status stays failed.
  def display_status = awaiting_verifier? ? "awaiting_verifier" : status
end
