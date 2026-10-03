require "test_helper"

class EdgeTrustTest < ActionDispatch::IntegrationTest
  EDGE = ListenerHelpers::EDGE_IP
  TEACHER = { "Remote-User" => "nik", "Remote-Groups" => "banco-teacher" }.freeze
  STUDENT = { "Remote-User" => "student", "Remote-Groups" => "banco-student" }.freeze

  setup do
    @saved_env = ENV.to_h.slice("BANCO_EDGE_PROXY", "BANCO_TEACHER_USERS")
    ENV["BANCO_EDGE_PROXY"] = "#{EDGE}/32"
    ENV["BANCO_TEACHER_USERS"] = "nik"
  end

  teardown do
    %w[BANCO_EDGE_PROXY BANCO_TEACHER_USERS].each { |k| @saved_env.key?(k) ? ENV[k] = @saved_env[k] : ENV.delete(k) }
  end

  test "teacher from the edge proxy on the web listener is 200" do
    on(:web, "/teacher", headers: TEACHER, remote_addr: EDGE)
    assert_response :success
  end

  test "student from the edge proxy sees the diagnosis page" do
    on(:web, "/diagnosis", headers: STUDENT, remote_addr: EDGE)
    assert_response :success
  end

  test "student is forbidden on the teacher page" do
    on(:web, "/teacher", headers: STUDENT, remote_addr: EDGE)
    assert_response :forbidden
  end

  test "forged teacher headers from any other peer are 403" do
    [ "127.0.0.1", "172.29.250.3", "10.0.0.5", "172.29.250.1" ].each do |peer|
      on(:web, "/teacher", headers: TEACHER, remote_addr: peer)
      assert_response :forbidden, "peer #{peer}"
    end
  end

  test "a forged X-Forwarded-For does not make a peer trusted" do
    on(:web, "/teacher", headers: TEACHER.merge("X-Forwarded-For" => EDGE), remote_addr: "10.0.0.5")
    assert_response :forbidden
  end

  test "headers from the edge address on a non-web listener are ignored" do
    on(:api, "/teacher", headers: TEACHER, remote_addr: EDGE)
    assert_response :not_found
    on(:harness, "/teacher", headers: TEACHER, remote_addr: EDGE)
    assert_response :not_found
  end

  test "a comma in Remote-User is 400" do
    on(:web, "/teacher", headers: TEACHER.merge("Remote-User" => "nik,mallory"), remote_addr: EDGE)
    assert_response :bad_request
  end

  test "a forged group alone is not enough: the user must be on the teacher list" do
    on(:web, "/teacher", headers: { "Remote-User" => "mallory", "Remote-Groups" => "banco-teacher" }, remote_addr: EDGE)
    assert_response :forbidden
  end

  test "a listed user without the teacher group is not a teacher" do
    on(:web, "/teacher", headers: { "Remote-User" => "nik", "Remote-Groups" => "users" }, remote_addr: EDGE)
    assert_response :forbidden
  end

  test "multiple groups are accepted from the trusted peer" do
    on(:web, "/teacher", headers: { "Remote-User" => "nik", "Remote-Groups" => "users,banco-teacher" }, remote_addr: EDGE)
    assert_response :success
  end

  test "no headers means no identity" do
    on(:web, "/teacher", remote_addr: EDGE)
    assert_response :forbidden
    on(:web, "/diagnosis", remote_addr: EDGE)
    assert_response :forbidden
  end

  test "nobody is trusted when BANCO_EDGE_PROXY is unset" do
    with_env("BANCO_EDGE_PROXY" => nil) do
      on(:web, "/teacher", headers: TEACHER, remote_addr: EDGE)
      assert_response :forbidden
    end
  end

  test "trusted_proxies is the edge address only" do
    proxies = Banco::EdgeProxy.trusted_proxies("BANCO_EDGE_PROXY" => "#{EDGE}/32")
    assert_equal 1, proxies.size
    assert proxies.first.include?(IPAddr.new(EDGE))
    assert_not proxies.first.include?(IPAddr.new("10.0.0.1"))
    assert_not Banco::EdgeProxy.trusted_proxies({}).first.include?(IPAddr.new("10.0.0.1"))
  end

  test "remote_ip is never consulted for trust" do
    assert_no_match(/remote_ip/, File.read(Rails.root.join("app/controllers/concerns/edge_trust.rb")).gsub(/^\s*#.*$/, ""))
  end
end
