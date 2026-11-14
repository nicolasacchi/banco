# frozen_string_literal: true

require "digest"

module Banco
  # Agent token authentication for the API listener (D-05).
  #
  # Token format: bnc_<id>_<secret>. Only the sha256 of the secret is ever
  # stored (api_tokens.secret_sha256). The lookup is a replaceable seam; by
  # default it reads the registry through ApiToken.lookup, which knows no revoked
  # token. A row may carry expires_at (the public API's tokens, D-327; the effective expiry, renewals included, D-330):
  # an expired token is refused like a wrong one, never renewed. A row may carry renew, a callable (now) that records a
  # renewal when one is due (D-330); the result keeps it for Api::BaseController, which calls Result#renew! once the
  # request passed the role checks. Tests may install a lookup through Banco::TokenAuth.lookup=.
  module TokenAuth
    FORMAT = /\Abnc_([A-Za-z0-9]{8})_([A-Za-z0-9_-]{43})\z/

    # id is the token's public id; teacher_login is set for role teacher only; renewal is nil or a callable without arguments.
    Result = Struct.new(:id, :role, :teacher_login, :renewal, keyword_init: true) do
      # Records a renewal of the token when one is due (ApiToken#renew_on_use!); nothing for a token that does not renew.
      def renew! = renewal&.call
    end

    class << self
      # Callable (id) -> { secret_sha256:, role:, [teacher_login:, expires_at:, renew:] } or nil.
      attr_writer :lookup

      def lookup
        @lookup ||= ->(id) { ApiToken.lookup(id) }
      end

      def reset!
        @lookup = nil
      end

      def authenticate(header, now: Time.current)
        token = header.to_s[/\ABearer (\S+)\z/, 1]
        return nil unless token
        m = FORMAT.match(token)
        return nil unless m

        row = lookup.call(m[1])
        return nil unless row

        digest = Digest::SHA256.hexdigest(m[2])
        return nil unless ActiveSupport::SecurityUtils.secure_compare(digest, row.fetch(:secret_sha256))

        expires_at = row[:expires_at]
        return nil if expires_at && expires_at <= now

        renew = row[:renew]
        Result.new(id: m[1], role: row.fetch(:role), teacher_login: row[:teacher_login], renewal: renew && -> { renew.call(now) })
      end
    end
  end
end
