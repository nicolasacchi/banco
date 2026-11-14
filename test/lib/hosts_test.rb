require "test_helper"

# Production host authorization (D-072): the list is the production config's own.
class HostsTest < ActiveSupport::TestCase
  def status_for(host, path = "/diagnosis", env: ENV)
    app = ->(_env) { [ 200, { "content-type" => "text/plain" }, [ "ok" ] ] }
    guarded = ActionDispatch::HostAuthorization.new(app, Banco::Hosts.allowed(env), exclude: ->(r) { Banco::Hosts.exclude(r) })
    guarded.call(Rack::MockRequest.env_for("http://#{host}#{path}", "HTTP_HOST" => host)).first
  end

  test "the public host, the container names and loopback with ports are allowed" do
    %w[banco.scc.im banco banco-harness:3200 127.0.0.1:3100 localhost:3100 localhost:3000].each do |host|
      assert_equal 200, status_for(host), host
    end
  end

  test "any other host is refused, except on the health check path" do
    assert_equal 403, status_for("evil.example.com")
    assert_equal 403, status_for("banco.scc.im.evil.example")
    assert_equal 403, status_for("10.0.0.5:3100", "/api/v1/schema")
    assert_equal 200, status_for("10.0.0.5:3000", "/up")
  end

  test "BANCO_EXTRA_HOSTS adds names" do
    env = { "BANCO_EXTRA_HOSTS" => "banco-staging, other.local" }
    assert_equal 200, status_for("other.local", env: env)
    assert_equal 403, status_for("other.local")
  end

  test "production config uses the list" do
    src = File.read(Rails.root.join("config/environments/production.rb"))
    assert_includes src, "config.hosts = Banco::Hosts.allowed"
    assert_includes src, "Banco::Hosts.exclude"
  end

  # ---- D-327: each public host belongs to one listener

  def listener_status(listener, host, path: "/api/v1/status", forwarded: nil, env: {})
    app = ->(_env) { [ 200, { "content-type" => "text/plain" }, [ "ok" ] ] }
    request_env = Rack::MockRequest.env_for("http://#{host}#{path}", "HTTP_HOST" => host)
    request_env["HTTP_X_FORWARDED_HOST"] = forwarded if forwarded
    request_env[Banco::ListenerTag::TAG_KEY] = listener
    saved = env.keys.to_h { |k| [ k, ENV[k] ] }
    env.each { |k, v| ENV[k] = v }
    Banco::Hosts::ListenerHosts.new(app).call(request_env).first
  ensure
    saved&.each { |k, v| v.nil? ? ENV.delete(k) : ENV[k] = v }
  end

  test "the API host is in the allowlist and BANCO_API_HOST replaces it" do
    assert_includes Banco::Hosts.allowed({}), "api.banco.scc.im"
    assert_equal 200, status_for("api.banco.scc.im:443")
    other = { "BANCO_API_HOST" => "Api.Staging.Banco.Test" }
    assert_includes Banco::Hosts.allowed(other), "api.staging.banco.test"
    assert_not_includes Banco::Hosts.allowed(other), "api.banco.scc.im"
  end

  test "the API host is accepted on the API listener and refused on every other" do
    assert_equal 200, listener_status(:api, "api.banco.scc.im")
    assert_equal 200, listener_status(:api, "API.banco.scc.im:443")
    %i[web harness pages].each { |listener| assert_equal 403, listener_status(listener, "api.banco.scc.im", path: "/today"), listener }
    assert_equal 403, listener_status(nil, "api.banco.scc.im")
  end

  test "the web host is refused on the API listener, and works elsewhere" do
    assert_equal 403, listener_status(:api, "banco.scc.im")
    assert_equal 403, listener_status(:api, "BANCO.scc.im:443")
    assert_equal 200, listener_status(:web, "banco.scc.im", path: "/today")
    assert_equal 200, listener_status(:harness, "banco-harness:3200", path: "/h/x")
  end

  test "a forwarded host that names the other listener's host is refused too" do
    assert_equal 403, listener_status(:api, "127.0.0.1:3100", forwarded: "banco.scc.im")
    assert_equal 403, listener_status(:web, "banco:3000", forwarded: "api.banco.scc.im")
    assert_equal 200, listener_status(:api, "127.0.0.1:3100", forwarded: "api.banco.scc.im")
  end

  test "loopback and the container names keep working on their listeners, and /up is never checked" do
    assert_equal 200, listener_status(:api, "127.0.0.1:3100")
    assert_equal 200, listener_status(:api, "localhost:3100")
    assert_equal 200, listener_status(:web, "api.banco.scc.im", path: "/up")
    assert_equal 200, listener_status(:api, "banco.scc.im", path: "/up")
  end

  test "BANCO_API_HOST moves the API's host for the listener check" do
    env = { "BANCO_API_HOST" => "api.staging.banco.test" }
    assert_equal 200, listener_status(:web, "api.banco.scc.im", path: "/today", env: env)
    assert_equal 403, listener_status(:web, "api.staging.banco.test", path: "/today", env: env)
    assert_equal 200, listener_status(:api, "api.staging.banco.test", env: env)
  end

  test "the middleware is installed in the application, after the listener tag" do
    names = Rails.application.middleware.map(&:name)
    assert_equal names.index("Banco::ListenerTag") + 1, names.index("Banco::Hosts::ListenerHosts")
  end

  test "through the whole stack, the web host on the API listener and the API host on the web listener are 403" do
    token = ApiToken.issue!(role: "bot_read", label: "hosts", expires_at: 1.day.from_now)
    integration = ActionDispatch::Integration::Session.new(Rails.application)
    integration.get("/api/v1/status", headers: { "Authorization" => "Bearer #{token}", "Host" => "banco.scc.im" }, env: { "banco.test_listener" => "api" })
    assert_equal 403, integration.response.status
    integration.get("/api/v1/status", headers: { "Authorization" => "Bearer #{token}", "Host" => "api.banco.scc.im" }, env: { "banco.test_listener" => "api" })
    assert_equal 200, integration.response.status
    integration.get("/today", headers: { "Host" => "api.banco.scc.im" }, env: { "banco.test_listener" => "web" })
    assert_equal 403, integration.response.status
  end
end
