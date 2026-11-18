require "test_helper"
require_relative "../support/multi_user"
require_relative "../support/decision_world"
require_relative "../support/topic_world"

# D-332: the view listener. A view link is a bearer capability for the guest role: it opens the teacher's pages
# read-only, on a listener of its own, without login and without ever being the teacher. Every request re-checks the
# link in the ledger and the feature flag.
class ViewListenerTest < ActionDispatch::IntegrationTest
  include MultiUser
  include DecisionWorld
  include TopicWorld

  VIEW_ENV = { "BANCO_VIEW_LINKS_ENABLED" => "1", "BANCO_VIEW_URL" => "https://api.banco.scc.im" }.freeze
  COURSE = "/teacher/subjects/math/course".freeze

  setup do
    @saved_view_env = ENV.to_h.slice(*VIEW_ENV.keys)
    VIEW_ENV.each { |k, v| ENV[k] = v }
    ENV["BANCO_LOGOUT_URL"] = "https://auth.example.test/logout"
    build_decision_world
    approve_graph_row!
    make_blueprint_approvable!
    build_topic_world
    raw = ApiToken.issue!(role: "bot_read", label: "view test", expires_at: 30.days.from_now)
    @bot = ApiToken.find_by!(public_id: Banco::TokenAuth::FORMAT.match(raw)[1])
  end

  teardown do
    VIEW_ENV.each_key { |k| @saved_view_env.key?(k) ? ENV[k] = @saved_view_env[k] : ENV.delete(k) }
  end

  def new_link(path: "/teacher", minutes: 60)
    ViewLinks.create!(token: @bot, path: path, minutes: minutes)
  end

  def view_get(path, headers: {}, remote_addr: EDGE)
    on(:view, path, headers: headers, remote_addr: remote_addr)
  end

  # Redeems a fresh link and keeps its cookie in the session; returns [link, raw].
  def open_session!(path: "/teacher", minutes: 60)
    link, raw = new_link(path: path, minutes: minutes)
    view_get("/v?view_token=#{raw}")
    assert_response :see_other
    [ link, raw ]
  end

  # What a view session must leave untouched: every row a reader could cause.
  def counts
    [ Decision, Attempt, DiagnosisRun, DiagnosisEvent, AppEvent, Student, ItemServed, ViewLink, ViewLinkRevocation ].map(&:count)
  end

  def assert_error_page(status, text = nil)
    assert_response status
    assert_select "#error-page[data-status=#{status}]"
    assert_select "#error-page a", 0
    assert_select "#error-page p", text if text
  end

  test "a valid token redeems: 303 to the link's page, an encrypted host-only cookie, no referrer, no cache, one redemption row" do
    _, raw = new_link(path: COURSE, minutes: 30)
    assert_difference -> { ViewLinkRedemption.count }, 1 do
      view_get("/v?view_token=#{raw}")
    end
    assert_response :see_other
    assert_equal COURSE, URI(response.location).request_uri
    assert_equal "no-referrer", response.headers["Referrer-Policy"]
    assert_equal "no-store", response.headers["Cache-Control"]
    cookie = response.headers["Set-Cookie"]
    assert_match(/banco_view=/, cookie)
    assert_match(/httponly/i, cookie)
    assert_match(/samesite=lax/i, cookie)
    assert_match(/expires=/i, cookie)
    assert_no_match(/domain=/i, cookie)
    assert_not_includes cookie, raw, "the token is never in the cookie"
    assert_no_match(/"id"/, cookie, "the cookie is encrypted")
  end

  test "after redemption the teacher's pages answer 200 as a guest: no form, no Esci, the read-only notice" do
    open_session!(path: COURSE)
    before = counts
    redemptions = ViewLinkRedemption.count
    [ "/teacher", COURSE, "/teacher/subjects/math/graph", "/teacher/subjects/math/test", "/teacher/subjects/math/test/all",
      "/teacher/subjects/math/test/skills/math.number", "/teacher/subjects/math/topics/#{TopicWorld::TOPIC_KEY}", "/teacher/subjects/math/report",
      "/teacher/corrections", "/teacher/items/#{@short.id}", "/teacher/items/#{@short.id}/play", "/teacher/refs/math.number" ].each do |path|
      view_get(path)
      assert_response :success, path
      assert_select "form", 0, path
      assert_select "button[type=submit]", 0, path
      assert_select "#read-only-notice", /Sei in sola lettura/, path
      assert_select "#logout-link", 0, path
      assert_select "[data-controller=activity]", 0, path
      assert_select "a[href^='/teacher/preview']", 0, path
      assert_match(/ospite/, css_select("#access-line").text, path)
    end
    assert_equal before, counts, "a view session records nothing"
    assert_equal redemptions, ViewLinkRedemption.count, "only the redemption of the link is counted"
  end

  test "the teacher's pages record nothing for a view link, with or without teacher headers" do
    open_session!
    events = AppEvent.count
    [ "/teacher/items/#{@short.id}", "/teacher/subjects/math/test/all", "/teacher/subjects/math/topics/#{TopicWorld::TOPIC_KEY}" ].each do |path|
      view_get(path)
      assert_response :success, path
      view_get(path, headers: TEACHER)
      assert_response :success, path
    end
    assert_equal events, AppEvent.count
  end

  test "the same page on the web listener still shows Esci to a guest (nothing changes there)" do
    on(:web, "/teacher", headers: GUEST, remote_addr: EDGE)
    assert_response :success
    assert_select "#logout-link"
    assert_select "#read-only-notice"
  end

  test "an unknown, expired, revoked or missing token is the same 410 page, with no cookie" do
    link, raw = new_link
    ViewLinks.revoke!(link, by: @bot)
    _, expiring = new_link(minutes: 5)
    [ "/v?view_token=#{'x' * 43}", "/v?view_token=#{raw}", "/v", "/v?view_token=", "/v?view_token[]=#{raw}", "/v?view_token[a]=#{raw}" ].each do |path|
      assert_no_difference -> { ViewLinkRedemption.count } do
        view_get(path)
      end
      assert_error_page :gone, "Il link è scaduto o non è valido. Chiedi un link nuovo."
      assert_equal "no-referrer", response.headers["Referrer-Policy"], path
      assert_nil response.headers["Set-Cookie"], path
    end
    travel 6.minutes do
      view_get("/v?view_token=#{expiring}")
      assert_error_page :gone, "Il link è scaduto o non è valido. Chiedi un link nuovo."
    end
  end

  test "a page without a session is a designed 403, and /v with a teacher's headers still opens nothing" do
    %w[/teacher /teacher/subjects/math/course /teacher/items/1].each do |path|
      view_get(path)
      assert_error_page :forbidden
    end
    view_get("/v", headers: TEACHER)
    assert_response :gone
  end

  test "Remote-User and Remote-Groups are never read on the view listener: a teacher's headers without a cookie are 403" do
    [ TEACHER, TEACHER_B, GUEST, OFFICIAL ].each do |headers|
      view_get("/teacher", headers: headers)
      assert_response :forbidden, headers["Remote-User"]
      view_get("/teacher/subjects/math/graph", headers: headers)
      assert_response :forbidden, headers["Remote-User"]
    end
  end

  test "with a cookie and the teacher's headers the visitor is still only the view link: guest, no decision form" do
    link, = open_session!
    view_get("/teacher/subjects/math/graph", headers: TEACHER)
    assert_response :success
    assert_select "form.decide", 0
    assert_select "#read-only-notice"
    assert_includes css_select("#access-line").text, "view-link-#{link.id}"
  end

  test "a revoked link's cookie is refused on the next request" do
    link, = open_session!
    view_get(COURSE)
    assert_response :success
    ViewLinks.revoke!(link, by: @bot)
    view_get(COURSE)
    assert_error_page :forbidden
    view_get("/teacher")
    assert_response :forbidden
  end

  test "an expired link's cookie is refused, even when the browser still sends it" do
    open_session!(minutes: 5)
    cookie = cookies["banco_view"]
    view_get("/teacher")
    assert_response :success
    travel 6.minutes do
      cookies["banco_view"] = cookie
      view_get("/teacher")
      assert_error_page :forbidden
    end
  end

  test "a forged or foreign cookie opens nothing" do
    link, = new_link
    cookies["banco_view"] = "garbage"
    view_get("/teacher")
    assert_response :forbidden
    cookies["banco_view"] = { "id" => link.id }.to_json # not encrypted: the id alone is no session
    view_get("/teacher")
    assert_response :forbidden
  end

  test "feature off: every request on the view listener is 404, existing sessions die at once" do
    link, raw = open_session!
    view_get("/teacher")
    assert_response :success
    [ { "BANCO_VIEW_LINKS_ENABLED" => nil }, { "BANCO_VIEW_LINKS_ENABLED" => "0" }, { "BANCO_VIEW_URL" => nil } ].each do |off|
      with_env(off) do
        [ "/teacher", COURSE, "/v?view_token=#{raw}", "/v" ].each do |path|
          view_get(path)
          assert_error_page :not_found
        end
        on(:view, "/teacher", method: :post, remote_addr: EDGE)
        assert_response :not_found
      end
    end
    assert_equal 1, ViewLinkRedemption.where(view_link_id: link.id).count, "a disabled feature redeems nothing"
    view_get("/teacher")
    assert_response :success, "switched back on, the same session works again"
  end

  test "any method but GET and HEAD is a 403 with a valid cookie, and nothing is written" do
    open_session!
    before = counts
    view_get("/teacher")
    token = css_select("meta[name=csrf-token]").first&.[]("content")
    %i[post put patch delete].each do |verb|
      [ "/teacher/activity", "/teacher/consent", "/teacher/subjects/math/follow-opinions", "/teacher/comments/1/reply", "/v", "/today", "/teacher",
        "/api/v1/view-links" ].each do |path|
        on(:view, path, method: verb, headers: { "X-CSRF-Token" => token.to_s }, params: { reason_it: "Prova.", acknowledged: true }, remote_addr: EDGE)
        assert_response :forbidden, "#{verb.upcase} #{path}"
      end
    end
    assert_equal before, counts
  end

  test "a POST without a session is a 403 too, never a 404 or a 422" do
    on(:view, "/teacher/consent", method: :post, params: { acknowledged: true }, remote_addr: EDGE)
    assert_error_page :forbidden
  end

  test "a HEAD to /v redeems nothing: no redemption row, no cookie, even with a valid token" do
    _, raw = new_link
    assert_no_difference -> { ViewLinkRedemption.count } do
      on(:view, "/v?view_token=#{raw}", method: :head, remote_addr: EDGE)
    end
    assert_response :success
    assert_nil response.headers["Set-Cookie"]
    view_get("/teacher")
    assert_response :forbidden
    assert_difference -> { ViewLinkRedemption.count }, 1 do
      view_get("/v?view_token=#{raw}")
    end
    assert_response :see_other
  end

  test "HEAD is served like GET" do
    open_session!
    on(:view, "/teacher", method: :head, remote_addr: EDGE)
    assert_response :success
  end

  test "a peer outside BANCO_EDGE_PROXY gets 404 for every request, cookie or not" do
    _, raw = open_session!
    [ "127.0.0.1", "10.0.0.5", "172.29.250.1" ].each do |peer|
      view_get("/teacher", remote_addr: peer)
      assert_error_page :not_found
      view_get("/v?view_token=#{raw}", remote_addr: peer)
      assert_error_page :not_found
      view_get("/teacher", headers: TEACHER, remote_addr: peer)
      assert_response :not_found
    end
    with_env("BANCO_EDGE_PROXY" => nil) do
      view_get("/teacher")
      assert_response :not_found
    end
  end

  test "the student's pages, the preview, the API and the rest are 404 on the view listener, with a valid session" do
    open_session!
    %w[/today /subjects /diagnosis /topics/x /settings /search /comments /teacher/preview /teacher/preview/today /teacher/preview/test
       /api/v1/status /api/v1/schema /api/v1/view-links /up / /nope].each do |path|
      view_get(path)
      assert_response :not_found, path
    end
    view_get("/teacher/preview", headers: TEACHER)
    assert_response :not_found
  end

  test "the figures and posters the teacher's pages use are served to a view session, and need one" do
    view_get("/assets/items/#{'0' * 64}.svg")
    assert_response :forbidden
    view_get("/page-posters/#{'0' * 64}")
    assert_response :forbidden
    open_session!
    view_get("/assets/items/#{'0' * 64}.svg")
    assert_response :not_found # allowed to ask; there is no such figure
    view_get("/page-posters/#{'0' * 64}")
    assert_response :not_found
  end

  test "the spoken clips of the lessons (D-359) are served to a view session, and need one" do
    Dir.mktmpdir do |dir|
      ENV["BANCO_SPEECH_CLIPS_DIR"] = dir
      key = Speech::Key.for("im_nicola", "Ciao.")
      Speech::Clips.put(key, "ID3clip")
      view_get("/speech/clips/#{key}.mp3")
      assert_response :forbidden
      open_session!
      view_get("/speech/clips/#{key}.mp3")
      assert_response :success
      assert_equal "audio/mpeg", response.media_type
      view_get("/speech/clips/#{'0' * 64}.mp3")
      assert_response :not_found
    ensure
      ENV.delete("BANCO_SPEECH_CLIPS_DIR")
    end
  end

  test "the web host is refused on the view listener, the API host is served" do
    _, raw = new_link
    on(:view, "/v?view_token=#{raw}", headers: { "Host" => "banco.scc.im" }, remote_addr: EDGE)
    assert_response :forbidden
    on(:view, "/v?view_token=#{raw}", headers: { "Host" => "api.banco.scc.im", "X-Forwarded-Host" => "banco.scc.im" }, remote_addr: EDGE)
    assert_response :forbidden
    assert_equal 0, ViewLinkRedemption.count
    on(:view, "/v?view_token=#{raw}", headers: { "Host" => "api.banco.scc.im" }, remote_addr: EDGE)
    assert_response :see_other
    assert_equal 1, ViewLinkRedemption.count
  end

  test "the API host is refused on the web listener still" do
    on(:web, "/teacher", headers: GUEST.merge("Host" => "api.banco.scc.im"), remote_addr: EDGE)
    assert_response :forbidden
  end

  test "on the web listener nothing changes: /v is 404 and a view cookie is no identity" do
    _, raw = open_session!
    on(:web, "/v?view_token=#{raw}", remote_addr: EDGE)
    assert_response :not_found
    on(:web, "/teacher", remote_addr: EDGE)
    assert_response :forbidden
    on(:web, "/teacher", headers: TEACHER, remote_addr: EDGE)
    assert_response :success
    assert_select "#read-only-notice", 0
    on(:web, "/teacher/preview", headers: TEACHER, remote_addr: EDGE)
    assert_response :success
  end

  test "the api and harness listeners do not serve /v" do
    _, raw = new_link
    %i[api harness].each do |listener|
      on(listener, "/v?view_token=#{raw}", remote_addr: EDGE)
      assert_response :not_found, listener.to_s
    end
    assert_equal 0, ViewLinkRedemption.count
  end

  test "the token parameter never reaches the request log" do
    filter = ActiveSupport::ParameterFilter.new(Rails.application.config.filter_parameters)
    assert_equal "[FILTERED]", filter.filter(view_token: "secret")[:view_token]
    assert_equal "[FILTERED]", filter.filter("view_token" => "secret")["view_token"]
  end
end
