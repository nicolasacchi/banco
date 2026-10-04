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
end
