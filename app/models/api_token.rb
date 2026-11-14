require "digest"
require "securerandom"

# Agent token registry (D-05). A token is bnc_<public_id>_<secret>; only the
# sha256 of the secret is stored, so a token can be shown once, at issuance.
class ApiToken < ApplicationRecord
  # bot_read and teacher are the public API's roles (D-327): bot_read only reads; teacher reads the same and, for the login
  # stored on the token, records teacher decisions and comment actions. Neither opens a session or writes content.
  ROLES = %w[agent_claude agent_omp ci bot_read teacher].freeze
  READERS = %w[bot_read teacher].freeze
  # The session roles each token role may open and use (D-071). ci, bot_read and teacher: none.
  SESSION_ROLES = {
    "agent_claude" => %w[author verifier reviewer solver grader arbiter],
    "agent_omp" => %w[author verifier reviewer solver],
    "ci" => [],
    "bot_read" => [],
    "teacher" => []
  }.freeze
  ALPHABET = [ *"a".."z", *"A".."Z", *"0".."9" ].freeze

  has_one :revocation, class_name: "ApiTokenRevocation"

  validates :role, inclusion: { in: ROLES }
  validates :teacher_login, presence: true, if: -> { role == "teacher" }
  validates :teacher_login, absence: true, unless: -> { role == "teacher" }
  # The public roles always expire (the database says the same: api_tokens_reader_expiry).
  validates :expires_at, presence: true, if: -> { READERS.include?(role) }

  # Creates a token and returns it as a string. The only time the secret exists. expires_at: nil is a token that never
  # expires (banco:token:issue sets one: 90 days by default); teacher_login: the teacher a role teacher token acts as.
  def self.issue!(role:, label:, expires_at: nil, teacher_login: nil)
    public_id = Array.new(8) { ALPHABET[SecureRandom.random_number(ALPHABET.size)] }.join
    secret = SecureRandom.urlsafe_base64(32)
    create!(public_id: public_id, secret_sha256: Digest::SHA256.hexdigest(secret), role: role, label: label,
            expires_at: expires_at, teacher_login: teacher_login.presence)
    "bnc_#{public_id}_#{secret}"
  end

  def self.session_roles(token_role) = SESSION_ROLES.fetch(token_role.to_s, [])

  def self.reader?(token_role) = READERS.include?(token_role.to_s)

  # Row for Banco::TokenAuth: { secret_sha256:, role:, teacher_login:, expires_at: } or nil (unknown or revoked).
  # An expired token is refused by Banco::TokenAuth, which compares expires_at with the clock.
  def self.lookup(public_id)
    token = find_by(public_id: public_id)
    return nil if token.nil? || ApiTokenRevocation.exists?(api_token_id: token.id)

    { secret_sha256: token.secret_sha256, role: token.role, teacher_login: token.teacher_login, expires_at: token.expires_at }
  end

  def expired?(now = Time.current) = !expires_at.nil? && expires_at <= now

  def revoked? = ApiTokenRevocation.exists?(api_token_id: id)
end
