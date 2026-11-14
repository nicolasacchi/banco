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
  has_many :renewals, class_name: "ApiTokenRenewal"

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

  # Row for Banco::TokenAuth: { secret_sha256:, role:, teacher_login:, expires_at:, renew: } or nil (unknown or revoked).
  # expires_at is the effective expiry (renewals included); an expired token is refused by Banco::TokenAuth, which compares
  # it with the clock. renew is called once the request is accepted (Api::BaseController): see #renew_on_use!.
  def self.lookup(public_id)
    token = find_by(public_id: public_id)
    return nil if token.nil? || ApiTokenRevocation.exists?(api_token_id: token.id)

    expires_at = token.effective_expires_at
    { secret_sha256: token.secret_sha256, role: token.role, teacher_login: token.teacher_login, expires_at: expires_at,
      renew: ->(now) { token.renew_on_use!(now, effective: expires_at) } }
  end

  # The latest of the token's own expiry and its renewals' (D-330); nil for a token that never expires.
  def effective_expires_at
    return nil if expires_at.nil?

    [ expires_at, renewals.maximum(:expires_at) ].compact.max
  end

  # The lifetime the operator gave the token at issuance, in whole days, at least 1; nil for a token that never expires.
  def lifetime_days
    return nil if expires_at.nil?

    [ ((expires_at - created_at) / 1.day).round, 1 ].max
  end

  # The public roles renew on use (D-330); the content roles keep the expiry they were issued with.
  def renews_on_use? = READERS.include?(role) && !expires_at.nil?

  # Records a renewal (expiry now + lifetime) when the token renews on use, is neither expired nor revoked (no
  # resurrection), and has less than its lifetime minus one day left (half its lifetime for a one-day token): so at most
  # about one row a day, and a token used at least once per lifetime never expires while an idle one still does. Two
  # concurrent requests may both write a row; the later expiry wins, which is harmless. Returns the row or nil.
  def renew_on_use!(now = Time.current, effective: effective_expires_at)
    return nil unless renews_on_use? && effective > now

    lifetime = lifetime_days.days
    return nil if effective - now >= [ lifetime - 1.day, lifetime / 2 ].max
    return nil if revoked?

    renewals.create!(expires_at: now + lifetime, created_at: now)
  end

  def expired?(now = Time.current)
    at = effective_expires_at
    !at.nil? && at <= now
  end

  def revoked? = ApiTokenRevocation.exists?(api_token_id: id)
end
