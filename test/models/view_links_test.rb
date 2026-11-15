require "test_helper"

# D-332: the view link service. A link is created with a raw token that only the caller holds (the ledger keeps its sha256),
# is active until it expires or is revoked or the feature is switched off, and is redeemed by appending one row.
class ViewLinksTest < ActiveSupport::TestCase
  VIEW_URL = "https://api.banco.test".freeze

  setup do
    @saved_env = ENV.to_h.slice("BANCO_VIEW_URL", "BANCO_VIEW_LINKS_ENABLED", "BANCO_TEACHER_USERS")
    ENV["BANCO_VIEW_URL"] = VIEW_URL
    ENV["BANCO_VIEW_LINKS_ENABLED"] = "1"
    ENV["BANCO_TEACHER_USERS"] = "nik"
    @token = make_token("vlinkaaa")
  end

  teardown do
    %w[BANCO_VIEW_URL BANCO_VIEW_LINKS_ENABLED BANCO_TEACHER_USERS].each { |k| @saved_env.key?(k) ? ENV[k] = @saved_env[k] : ENV.delete(k) }
  end

  def make_token(public_id, expires_at: 30.days.from_now)
    ApiToken.create!(public_id: public_id, secret_sha256: "e" * 64, role: "bot_read", label: "view links test", expires_at: expires_at)
  end

  def make_teacher_token(public_id, login: "nik", expires_at: 30.days.from_now)
    ApiToken.create!(public_id: public_id, secret_sha256: "e" * 64, role: "teacher", teacher_login: login, label: "view links test", expires_at: expires_at)
  end

  # A link of one day for the token, redeemable now.
  def day_link(token) = ViewLinks.create!(token: token, minutes: 1440)

  def assert_dead(link, raw)
    assert_nil ViewLinks.active(link.id)
    assert_nil ViewLinks.redeem(raw)
    refute ViewLink.find(link.id).active?
  end

  def counts = [ ViewLink.count, ViewLinkRedemption.count, ViewLinkRevocation.count ]

  # ---- the feature flag and the origin

  test "enabled needs the flag and an https origin; the base url has no trailing slash" do
    assert ViewLinks.enabled?
    assert_equal VIEW_URL, ViewLinks.base_url
    ENV["BANCO_VIEW_URL"] = "#{VIEW_URL}/"
    assert_equal VIEW_URL, ViewLinks.base_url
    ENV["BANCO_VIEW_URL"] = "https://api.banco.test:8443"
    assert_equal "https://api.banco.test:8443", ViewLinks.base_url

    ENV["BANCO_VIEW_LINKS_ENABLED"] = "0"
    refute ViewLinks.enabled?
    ENV["BANCO_VIEW_LINKS_ENABLED"] = nil
    refute ViewLinks.enabled?
    ENV["BANCO_VIEW_LINKS_ENABLED"] = "1"

    [ nil, "", "api.banco.test", "https://#{Banco::Hosts::WEB_HOST}", "https://#{Banco::Hosts::WEB_HOST.upcase}/", "https://#{Banco::Hosts::WEB_HOST}.", "ftp://api.banco.test", "https://", "https://api.banco.test/teacher", "https://api.banco.test?x=1", "https://u:p@api.banco.test" ].each do |url|
      url.nil? ? ENV.delete("BANCO_VIEW_URL") : ENV["BANCO_VIEW_URL"] = url
      assert_nil ViewLinks.base_url, url.inspect
      refute ViewLinks.enabled?, url.inspect
    end
  end

  # ---- create

  test "create returns the link and a raw token whose sha256 is the only thing stored" do
    link, raw = ViewLinks.create!(token: @token)
    assert_predicate link, :persisted?
    assert_equal "/teacher", link.path
    assert_in_delta 60.minutes.from_now.to_f, link.expires_at.to_f, 5
    assert_equal Digest::SHA256.hexdigest(raw), link.token_digest
    assert_operator raw.length, :>=, 43
    assert ViewLink.connection.select_rows("SELECT * FROM view_links").flatten.none? { |v| v.to_s.include?(raw) }
    assert_equal "#{VIEW_URL}/v?view_token=#{raw}", link.url(raw)
    assert_not_equal raw, ViewLinks.create!(token: @token).last
  end

  test "create takes a path and minutes" do
    link, = ViewLinks.create!(token: @token, path: "/teacher/subjects/math/course?tab=a%20b&x=1", minutes: 5)
    assert_equal "/teacher/subjects/math/course?tab=a%20b&x=1", link.path
    assert_in_delta 5.minutes.from_now.to_f, link.expires_at.to_f, 5
    assert_in_delta 1440.minutes.from_now.to_f, ViewLinks.create!(token: @token, minutes: 1440).first.expires_at.to_f, 5
    assert_in_delta 90.minutes.from_now.to_f, ViewLinks.create!(token: @token, minutes: "90").first.expires_at.to_f, 5
    %w[/teacher /teacher/ /teacher/today.x /teacher/items/12 /teacher/preview-not /teacher/a_b-c~d].each { |p| assert ViewLinks.create!(token: @token, path: p), p }
  end

  test "create refuses a path that is not a teacher page, naming the field" do
    [ "/today", "/", "", "teacher", "/teacher/preview", "/teacher/preview/x", "/teacher/Preview", "/teacher/preview/?a=1", "//evil", "/teacher//x",
      "/teacher/../x", "/teacher/./x", "/teacher/..", "https://evil.test/teacher", "/teacher/x y", "/teacher/a\nb", "/teacher?a=1\n", "/teacher#frag",
      "/teachers", "/teacher/" + "a" * 300, 5, [ "/teacher" ] ].each do |path|
      error = assert_raises(ViewLinks::Invalid, path.inspect) { ViewLinks.create!(token: @token, path: path) }
      assert_equal "path", error.field, path.inspect
      assert_match(/\w/, error.message)
    end
    assert_equal 0, ViewLink.count
  end

  test "create accepts a path of exactly 300 characters" do
    path = "/teacher/" + "a" * 291
    assert_equal 300, path.length
    assert_equal path, ViewLinks.create!(token: @token, path: path).first.path
  end

  test "create refuses minutes outside 5..1440 or not a whole number, naming the field" do
    [ 4, 0, -5, 1441, "x", "4", "1441", "", 60.5, "60.5", true, [ 60 ] ].each do |minutes|
      error = assert_raises(ViewLinks::Invalid, minutes.inspect) { ViewLinks.create!(token: @token, minutes: minutes) }
      assert_equal "minutes", error.field, minutes.inspect
    end
    assert_equal 0, ViewLink.count
  end

  test "a token has at most 20 active links; expired and revoked ones do not count, another token's do not either" do
    links = Array.new(ViewLinks::LIMIT) { ViewLinks.create!(token: @token, minutes: 5).first }
    assert_raises(ViewLinks::Limit) { ViewLinks.create!(token: @token) }
    assert_equal ViewLinks::LIMIT, ViewLink.count

    ViewLinks.create!(token: make_token("vlinkbbb"))
    ViewLinks.revoke!(links.first, by: @token)
    ViewLinks.create!(token: @token, minutes: 5)
    assert_raises(ViewLinks::Limit) { ViewLinks.create!(token: @token) }

    travel 6.minutes
    assert_equal 0, ViewLinks.active_count(@token)
    ViewLinks.create!(token: @token)
  end

  # ---- redeem and active

  test "redeem returns the active link and appends one redemption row per use" do
    link, raw = ViewLinks.create!(token: @token)
    assert_equal link, ViewLinks.redeem(raw)
    assert_equal [ link.id ], ViewLinkRedemption.pluck(:view_link_id)
    assert_equal link, ViewLinks.redeem(raw)
    assert_equal 2, ViewLinkRedemption.count
  end

  test "redeem answers nil, and appends nothing, for an unknown, expired or revoked token or when the feature is off" do
    link, raw = ViewLinks.create!(token: @token, minutes: 5)
    other, other_raw = ViewLinks.create!(token: @token)
    before = counts

    [ nil, "", "nope", "x" * 5000, [ raw ], raw.reverse, raw.upcase ].each { |bad| assert_nil ViewLinks.redeem(bad), bad.inspect }

    ENV["BANCO_VIEW_LINKS_ENABLED"] = "0"
    assert_nil ViewLinks.redeem(raw)
    assert_nil ViewLinks.active(link.id)
    ENV["BANCO_VIEW_LINKS_ENABLED"] = "1"
    ENV["BANCO_VIEW_URL"] = "not a url"
    assert_nil ViewLinks.redeem(raw)
    ENV["BANCO_VIEW_URL"] = VIEW_URL
    assert_equal before, counts

    ViewLinks.revoke!(other, by: nil)
    assert_nil ViewLinks.redeem(other_raw)
    assert_nil ViewLinks.active(other.id)

    travel 6.minutes
    assert_nil ViewLinks.redeem(raw)
    assert_nil ViewLinks.active(link.id)
    assert_equal 0, ViewLinkRedemption.count
  end

  test "active answers the link while it is not expired, revoked or switched off" do
    link, = ViewLinks.create!(token: @token, minutes: 5)
    assert_equal link, ViewLinks.active(link.id)
    assert_predicate link, :active?
    assert_nil ViewLinks.active(0)
    assert_nil ViewLinks.active(nil)
    assert_equal 0, ViewLinkRedemption.count, "active only reads"
    travel 4.minutes
    assert_equal link, ViewLinks.active(link.id)
    travel 2.minutes
    assert_nil ViewLinks.active(link.id)
    assert_predicate link, :expired?
  end

  # ---- a link dies with its token

  test "a link stops being active when its token is revoked" do
    link, raw = day_link(@token)
    assert_equal link, ViewLinks.active(link.id)
    ApiTokenRevocation.create!(api_token: @token, reason: "test")
    assert_dead(link, raw)
    assert_equal 0, ViewLinkRedemption.count
    assert_equal 0, ViewLinks.active_count(@token)
  end

  test "a link stops being active when its token expires, renewals counted" do
    token = make_token("vlinkexp", expires_at: 2.hours.from_now)
    link, raw = day_link(token)
    ApiTokenRenewal.create!(api_token: token, expires_at: 5.hours.from_now, created_at: Time.current)
    travel 3.hours
    assert_equal link, ViewLinks.active(link.id), "the renewal moved the token's expiry"
    assert_equal link, ViewLinks.redeem(raw)
    travel 3.hours
    assert_dead(link, raw)
    assert_equal 1, ViewLinkRedemption.count
  end

  test "a link of a teacher token stops being active when the teacher leaves the teacher list" do
    token = make_teacher_token("vlinkteo")
    link, raw = day_link(token)
    assert_equal link, ViewLinks.active(link.id)
    ENV["BANCO_TEACHER_USERS"] = "someone-else"
    assert_dead(link, raw)
    ENV["BANCO_TEACHER_USERS"] = "nik"
    assert_equal link, ViewLinks.active(link.id), "listed again"
  end

  test "the teacher list matters only for a teacher token" do
    ENV["BANCO_TEACHER_USERS"] = ""
    link, = day_link(@token)
    assert_equal link, ViewLinks.active(link.id)
  end

  test "an expired link of a usable token and a usable link of an expired token are both inactive in the count" do
    token = make_token("vlinkcnt", expires_at: 2.hours.from_now)
    day_link(token)
    assert_equal 1, ViewLinks.active_count(token)
    travel 3.hours
    assert_equal 0, ViewLinks.active_count(token)
  end

  # ---- revoke and list

  test "revoke appends one row and answers the same row the second time" do
    link, raw = ViewLinks.create!(token: @token)
    first = ViewLinks.revoke!(link, by: @token)
    assert_equal @token, first.api_token
    assert_equal first, ViewLinks.revoke!(link, by: @token)
    assert_equal first, ViewLinks.revoke!(ViewLink.find(link.id), by: nil)
    assert_equal 1, ViewLinkRevocation.count
    assert_predicate link, :revoked?
    refute_predicate link, :active?
    assert_nil ViewLinks.redeem(raw)
  end

  test "for_token is bounded to the newest 100 and listing does not query per row" do
    token = make_token("vlinklst")
    now = Time.current
    rows = Array.new(ViewLinks::LIST_LIMIT + 5) { |i| { api_token_id: token.id, token_digest: Digest::SHA256.hexdigest("t#{i}"), path: "/teacher", expires_at: now + 1.day, created_at: now + i.seconds } }
    ViewLink.insert_all!(rows)
    links = ViewLinks.for_token(token).to_a
    assert_equal ViewLinks::LIST_LIMIT, links.size
    assert_equal ViewLink.order(created_at: :desc).limit(ViewLinks::LIST_LIMIT).pluck(:id), links.map(&:id)
    queries = 0
    counter = ->(*, payload) { queries += 1 unless payload[:name] == "SCHEMA" }
    ActiveSupport::Notifications.subscribed(counter, "sql.active_record") do
      usable = ViewLinks.token_usable?(token)
      links = ViewLinks.for_token(token).to_a
      links.each { |l| l.active?(token_usable: usable) }
    end
    assert_operator queries, :<=, 6, "a fixed number of queries, not one per row"
  end

  test "for_token lists the token's own links, newest first" do
    mine = Array.new(3) { ViewLinks.create!(token: @token).first }
    ViewLinks.create!(token: make_token("vlinkbbb"))
    assert_equal mine.reverse.map(&:id), ViewLinks.for_token(@token).map(&:id)
  end

  # ---- the ledger

  test "the three tables reject UPDATE and DELETE" do
    link, raw = ViewLinks.create!(token: @token)
    ViewLinks.redeem(raw)
    ViewLinks.revoke!(link, by: @token)
    [ ViewLink, ViewLinkRedemption, ViewLinkRevocation ].each do |model|
      row = model.first
      assert_raises(ActiveRecord::StatementInvalid, model.name) { row.update_column(:created_at, 1.day.ago) }
      assert_raises(ActiveRecord::StatementInvalid, model.name) { row.delete }
      assert_raises(ActiveRecord::StatementInvalid, model.name) { model.delete_all }
    end
    assert_equal [ 1, 1, 1 ], counts
  end

  test "a link must expire after its creation, and a token digest is unique" do
    now = Time.current
    assert_raises(ActiveRecord::StatementInvalid) { ViewLink.create!(api_token: @token, token_digest: "a" * 64, path: "/teacher", expires_at: now, created_at: now) }
    ViewLink.create!(api_token: @token, token_digest: "a" * 64, path: "/teacher", expires_at: now + 1.minute, created_at: now)
    assert_raises(ActiveRecord::RecordNotUnique) { ViewLink.create!(api_token: @token, token_digest: "a" * 64, path: "/teacher", expires_at: now + 1.minute, created_at: now) }
  end
end
