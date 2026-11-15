require "digest"
require "securerandom"

# View links (D-332): temporary URLs that open the teacher's pages read-only on the view listener, as the guest role,
# without login. A link is created over the API by a bot_read or teacher token; the raw token is shown once and only its
# sha256 is stored. Active = not revoked, not expired, and the feature on (the kill switch: BANCO_VIEW_LINKS_ENABLED and
# BANCO_VIEW_URL) and the token that minted the link still works. Redeeming and every later request on the view listener re-check this against the ledger.
module ViewLinks
  # A field ("path" or "minutes") the caller got wrong; message is English, for the API's answer.
  class Invalid < StandardError
    attr_reader :field

    def initialize(field, message)
      @field = field
      super(message)
    end
  end

  # The token already has LIMIT active links.
  class Limit < StandardError; end

  DEFAULT_PATH = "/teacher".freeze
  DEFAULT_MINUTES = 60
  MINUTES = (5..1440)
  MAX_PATH = 300
  LIMIT = 20
  LIST_LIMIT = 100
  # A teacher page: /teacher and below, plain segments, an optional query. Dot segments and /teacher/preview are refused by hand.
  PATH_FORMAT = %r{\A/teacher(/[A-Za-z0-9._~\-]+)*/?(\?[A-Za-z0-9._~\-=&%]*)?\z}

  module_function

  # The feature is on: the flag is "1" and BANCO_VIEW_URL is an origin to build links with.
  def enabled? = ENV["BANCO_VIEW_LINKS_ENABLED"] == "1" && !base_url.nil?

  # The origin of BANCO_VIEW_URL without a trailing slash; nil when unset, not an https origin (http only in test and
  # development) or on the web host (banco.scc.im: a view listener there would take the web listener down).
  def base_url
    uri = URI.parse(ENV["BANCO_VIEW_URL"].to_s.strip)
    schemes = Rails.env.production? ? %w[https] : %w[https http]
    return nil unless schemes.include?(uri.scheme) && uri.host.present?
    return nil if uri.host.downcase.chomp(".") == Banco::Hosts::WEB_HOST
    return nil unless uri.userinfo.nil? && uri.query.nil? && uri.fragment.nil? && [ "", "/" ].include?(uri.path)

    "#{uri.scheme}://#{uri.host}#{":#{uri.port}" unless uri.port == uri.default_port}"
  rescue URI::InvalidURIError
    nil
  end

  # Creates a link for the ApiToken and returns [link, raw_token]. The raw token exists only here.
  def create!(token:, path: nil, minutes: nil)
    path = check_path(path.nil? ? DEFAULT_PATH : path)
    minutes = check_minutes(minutes.nil? ? DEFAULT_MINUTES : minutes)
    ViewLink.transaction do
      raise Limit, "a token may have at most #{LIMIT} active view links" if active_count(token) >= LIMIT

      raw = SecureRandom.urlsafe_base64(32)
      now = Time.current
      link = ViewLink.create!(api_token: token, token_digest: digest(raw), path: path, expires_at: now + minutes.minutes, created_at: now)
      [ link, raw ]
    end
  end

  # The link a raw token opens, with a redemption row appended; nil for an unknown, expired or revoked token, or the feature off.
  def redeem(raw_token)
    return nil unless enabled? && raw_token.is_a?(String) && !raw_token.empty?

    link = ViewLink.find_by(token_digest: digest(raw_token))
    return nil unless link&.active?

    link.redemptions.create!
    link
  end

  # The link with this id when it is active now, else nil: what a view session re-checks on every request.
  def active(link_id)
    link = ViewLink.includes(:api_token).find_by(id: link_id)
    link if link&.active?
  end

  # Appends the revocation by the ApiToken (nil: not over the API); an already revoked link answers its existing row.
  def revoke!(link, by:)
    ViewLinkRevocation.find_by(view_link_id: link.id) || ViewLinkRevocation.create!(view_link: link, api_token: by)
  rescue ActiveRecord::RecordNotUnique
    ViewLinkRevocation.find_by!(view_link_id: link.id)
  end

  # The token's newest LIST_LIMIT links, newest first, with their revocations loaded.
  def for_token(token) = ViewLink.where(api_token_id: token.id).includes(:revocation).order(created_at: :desc, id: :desc).limit(LIST_LIMIT)

  # The rule the API applies to a request's token (Banco::TokenAuth: known, not revoked, not past its effective expiry, D-330;
  # Api::BaseController: a teacher token's teacher is still on BANCO_TEACHER_USERS). A link lives only while this holds.
  def token_usable?(token, now = Time.current)
    return false if token.revoked? || token.expired?(now)

    token.role != "teacher" || Banco::EdgeProxy.teacher_users.include?(token.teacher_login.to_s)
  end

  def digest(raw_token) = Digest::SHA256.hexdigest(raw_token)

  def active_count(token, now = Time.current)
    return 0 unless token_usable?(token, now)

    ViewLink.where(api_token_id: token.id).where("expires_at > ?", now)
            .where.not(id: ViewLinkRevocation.select(:view_link_id)).count
  end

  def check_path(path)
    raise Invalid.new("path", "path is a string") unless path.is_a?(String)
    raise Invalid.new("path", "path is at most #{MAX_PATH} characters") if path.length > MAX_PATH
    raise Invalid.new("path", "path is a teacher page: /teacher, /teacher/subjects/math/course, ...") unless PATH_FORMAT.match?(path)

    segments = path.split("?", 2).first.split("/")
    raise Invalid.new("path", "path has no . or .. segment") if segments.any? { |s| s.match?(/\A\.+\z/) }
    raise Invalid.new("path", "a view link never opens /teacher/preview") if segments[2].to_s.casecmp?("preview")

    path
  end

  # An Integer, or the digits of one (a CLI flag), in MINUTES.
  def check_minutes(minutes)
    minutes = Integer(minutes, 10) if minutes.is_a?(String) && minutes.match?(/\A\d{1,6}\z/)
    raise Invalid.new("minutes", "minutes is a whole number from #{MINUTES.min} to #{MINUTES.max}") unless minutes.is_a?(Integer) && MINUTES.cover?(minutes)

    minutes
  end
end
