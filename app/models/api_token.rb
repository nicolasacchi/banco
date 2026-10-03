require "digest"
require "securerandom"

# Agent token registry (D-05). A token is bnc_<public_id>_<secret>; only the
# sha256 of the secret is stored, so a token can be shown once, at issuance.
class ApiToken < ApplicationRecord
  ROLES = %w[agent_claude agent_omp ci].freeze
  ALPHABET = [ *"a".."z", *"A".."Z", *"0".."9" ].freeze

  has_one :revocation, class_name: "ApiTokenRevocation"

  validates :role, inclusion: { in: ROLES }

  # Creates a token and returns it as a string. The only time the secret exists.
  def self.issue!(role:, label:)
    public_id = Array.new(8) { ALPHABET[SecureRandom.random_number(ALPHABET.size)] }.join
    secret = SecureRandom.urlsafe_base64(32)
    create!(public_id: public_id, secret_sha256: Digest::SHA256.hexdigest(secret), role: role, label: label)
    "bnc_#{public_id}_#{secret}"
  end

  # Row for Banco::TokenAuth: { secret_sha256:, role: } or nil (unknown or revoked).
  def self.lookup(public_id)
    token = find_by(public_id: public_id)
    return nil if token.nil? || ApiTokenRevocation.exists?(api_token_id: token.id)

    { secret_sha256: token.secret_sha256, role: token.role }
  end
end
