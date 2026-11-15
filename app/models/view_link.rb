# A temporary URL that opens the teacher's pages read-only, as a guest, without login (D-332). Append-only: only the sha256
# of the token is stored, so the URL exists in full once, in the answer that created the link (ViewLinks.create!). A link's
# state is derived: active = not revoked, not expired, feature on, and the token that minted it still usable (a link dies
# with its token); nothing here is ever rewritten.
class ViewLink < ApplicationRecord
  belongs_to :api_token
  has_many :redemptions, class_name: "ViewLinkRedemption"
  has_one :revocation, class_name: "ViewLinkRevocation"

  # The URL for the raw token, which only the creator holds; nil when the feature is off.
  def url(raw_token)
    base = ViewLinks.base_url
    "#{base}/v?view_token=#{raw_token}" if base
  end

  # Uses the loaded revocation (a listing preloads it) and asks the database otherwise.
  def revoked? = association(:revocation).loaded? ? !revocation.nil? : ViewLinkRevocation.exists?(view_link_id: id)

  def expired?(now = Time.current) = expires_at <= now

  # token_usable: the answer of ViewLinks.token_usable? when the caller already has it (a listing of one token's links).
  def active?(now = Time.current, token_usable: nil)
    return false unless ViewLinks.enabled? && !expired?(now) && !revoked?

    token_usable.nil? ? ViewLinks.token_usable?(api_token, now) : token_usable
  end
end
