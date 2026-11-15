require "test_helper"

class ListenerTest < ActionDispatch::IntegrationTest
  test "web routes answer on the web listener" do
    on(:web, "/up")
    assert_response :success
  end

  test "web routes are 404 on the api listener" do
    %w[/up /diagnosis /teacher].each do |path|
      on(:api, path)
      assert_response :not_found, "#{path} on api"
    end
  end

  test "web routes are 404 on the harness listener" do
    %w[/up /diagnosis /teacher].each do |path|
      on(:harness, path)
      assert_response :not_found, "#{path} on harness"
    end
  end

  test "api schema is 404 on the web listener" do
    on(:web, "/api/v1/schema")
    assert_response :not_found
  end

  test "api schema is 404 on the harness listener" do
    on(:harness, "/api/v1/schema")
    assert_response :not_found
  end

  test "api schema without token is 401" do
    on(:api, "/api/v1/schema")
    assert_response :unauthorized
    assert_equal "E-AUTH", response.parsed_body["code"]
    assert_nil response.headers["X-Banco-Contract"] # D-327: the digest goes to a caller with a good token only
  end

  test "api schema with an unknown token is 401" do
    on(:api, "/api/v1/schema", headers: { "Authorization" => "Bearer bnc_abcd1234_#{'x' * 43}" })
    assert_response :unauthorized
  end

  test "api schema with a valid token serves the contract" do
    secret = "s" * 43
    Banco::TokenAuth.lookup = ->(id) {
      id == "abcd1234" ? { secret_sha256: Digest::SHA256.hexdigest(secret), role: "agent_claude" } : nil
    }
    on(:api, "/api/v1/schema", headers: { "Authorization" => "Bearer bnc_abcd1234_#{secret}" })
    assert_response :success
    assert_equal Contract.parsed, response.parsed_body
    assert_equal Contract.digest, response.headers["X-Banco-Contract"]
  ensure
    Banco::TokenAuth.reset!
  end

  test "a request with no listener tag is 404 everywhere" do
    get "/up"
    assert_response :not_found
  end

  test "the test seam is the only way to name a listener in the test env" do
    # SERVER_PORT / Host claims never select a listener.
    get "/diagnosis", headers: { "Host" => "localhost:3000" }, env: { "SERVER_PORT" => "3000" }
    assert_response :not_found
  end

  test "the listener comes from the accepted socket's local port, not request.port" do
    socket = Struct.new(:port) do
      def local_address = Addrinfo.tcp("127.0.0.1", port)
    end
    tag = Banco::ListenerTag.new(->(env) { [ 200, {}, [ env["banco.listener"].inspect ] ] })
    with_env("WEB_PORT" => "3000", "API_PORT" => "3100", "HARNESS_PORT" => "3200", "PAGES_PORT" => "3300", "VIEW_PORT" => "3400") do
      { 3000 => ":web", 3100 => ":api", 3200 => ":harness", 3300 => ":pages", 3400 => ":view", 4000 => "nil" }.each do |port, expected|
        env = Rack::MockRequest.env_for("http://localhost:3000/up", "puma.socket" => socket.new(port))
        assert_equal expected, tag.call(env).last.first, "local port #{port}"
      end
    end
  end

  test "the test seam is ignored when the middleware is not built for tests" do
    app = ->(env) { [ 200, {}, [ env["banco.listener"].inspect ] ] }
    env = Rack::MockRequest.env_for("/up", "banco.test_listener" => "web")
    assert_equal "nil", Banco::ListenerTag.new(app).call(env).last.first
  end

  test "the ports must differ" do
    assert_raises(ArgumentError) { Banco::Listeners.assert_distinct!("WEB_PORT" => "3000", "API_PORT" => "3000") }
    assert_equal({ web: 3000, api: 3100, harness: 3200, pages: 3300, view: 3400 }, Banco::Listeners.assert_distinct!({}))
  end

  # D-332: five listeners, five distinct ports, VIEW_PORT among them (never PORT).
  test "the view listener has its own port, VIEW_PORT, distinct from the other four" do
    ports = Banco::Listeners.ports({})
    assert_equal 5, ports.values.uniq.size
    assert_equal 3400, ports.fetch(:view)
    assert_equal "VIEW_PORT", Banco::Listeners::ENV_KEYS.fetch(:view)
    assert_equal 3999, Banco::Listeners.ports("VIEW_PORT" => "3999").fetch(:view)
    assert_equal :view, Banco::Listeners.name_for_port(3400, {})
    error = assert_raises(ArgumentError) { Banco::Listeners.assert_distinct!("VIEW_PORT" => "3000") }
    assert_includes error.message, "VIEW_PORT"
    assert_raises(ArgumentError) { Banco::Listeners.assert_distinct!("VIEW_PORT" => "3300") }
  end

  test "a route constraint takes several listener names" do
    both = Banco::ListenerConstraint.new(:web, :view)
    request = ->(listener) { Struct.new(:env).new({ Banco::ListenerTag::TAG_KEY => listener }) }
    assert both.matches?(request.call(:web))
    assert both.matches?(request.call(:view))
    %i[api harness pages].each { |listener| assert_not both.matches?(request.call(listener)), listener }
    assert_not both.matches?(request.call(nil))
    assert Banco::ListenerConstraint.new(:web).matches?(request.call(:web))
    assert_not Banco::ListenerConstraint.new(:web).matches?(request.call(:view))
  end

  test "the listener switch sends the view listener to Rails" do
    rails = ->(_env) { [ 200, {}, [ "rails" ] ] }
    other = ->(_env) { [ 200, {}, [ "other" ] ] }
    switch = Banco::ListenerSwitch.new(rails, production: other, validation: other, allow_test_seam: true)
    assert_equal "rails", switch.call(Rack::MockRequest.env_for("/v", "banco.test_listener" => "view")).last.first
  end

  test "the teacher's GET pages are 404 on the api and harness listeners, and the student's pages are web only" do
    %w[/teacher /teacher/subjects/math/course /teacher/corrections].each do |path|
      %i[api harness].each do |listener|
        on(listener, path)
        assert_response :not_found, "#{path} on #{listener}"
      end
    end
    %w[/today /diagnosis /teacher/preview /subjects /up /].each do |path|
      on(:view, path, remote_addr: ListenerHelpers::EDGE_IP)
      assert_response :not_found, "#{path} on view"
    end
  end

  test "unknown paths are 404 on every listener" do
    %i[web api harness].each do |l|
      on(l, "/nope")
      assert_response :not_found
    end
  end
end
