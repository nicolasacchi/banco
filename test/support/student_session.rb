# System tests act as the student (or the teacher) the way the edge proxy would say
# so: the test server's peer is 127.0.0.1, so that address is the trusted edge for
# the test, and Remote-User / Remote-Groups travel as extra headers of every request
# the browser makes, fetch included.
module StudentSession
  STUDENT_HEADERS = { "Remote-User" => "student", "Remote-Groups" => "banco-student" }.freeze
  TEACHER_HEADERS = { "Remote-User" => "nik", "Remote-Groups" => "banco-teacher" }.freeze

  def sign_in_as(role = :student)
    # Only the first call saves: a test that signs in again (setup as the student, the test as the teacher) must not
    # save the values the first call set, or sign_out_env restores them and they leak into the next test.
    @saved_edge_env ||= ENV.to_h.slice("BANCO_EDGE_PROXY", "BANCO_TEACHER_USERS")
    ENV["BANCO_EDGE_PROXY"] = "127.0.0.1/32"
    ENV["BANCO_TEACHER_USERS"] = "nik"
    page.driver.headers = role == :teacher ? TEACHER_HEADERS : STUDENT_HEADERS
  end

  def sign_out_env
    return unless @saved_edge_env

    %w[BANCO_EDGE_PROXY BANCO_TEACHER_USERS].each do |k|
      @saved_edge_env.key?(k) ? ENV[k] = @saved_edge_env[k] : ENV.delete(k)
    end
    @saved_edge_env = nil
  end

  # Requests the pages made, as URLs (not the browser's own chrome:// pages).
  def requested_urls = page.driver.network_traffic.map { |r| r.url.to_s }.grep(%r{\Ahttps?://})

  def origin = "http://127.0.0.1:#{Capybara.server_port}"

  # Real keyboard events into the focused element (MathLive listens to them).
  def type_keys(*keys) = page.driver.browser.keyboard.type(*keys)
end
