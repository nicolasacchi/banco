require "test_helper"
require_relative "../support/student_ui_rows"

# X-02: the policy of the app pages and of agent figures, exactly.
class CspHeaderTest < ActionDispatch::IntegrationTest
  include StudentUiRows

  EDGE = ListenerHelpers::EDGE_IP
  STUDENT = { "Remote-User" => "student", "Remote-Groups" => "banco-student" }.freeze

  # The policy, with the nonce left as a placeholder.
  EXPECTED = "default-src 'self'; script-src 'self' 'nonce-NONCE'; style-src 'self' 'unsafe-inline'; img-src 'self' data:; " \
             "font-src 'self'; connect-src 'self'; frame-src 'none'; object-src 'none'; base-uri 'none'; form-action 'self'".freeze

  setup do
    @saved = ENV.to_h.slice("BANCO_EDGE_PROXY", "BANCO_TEACHER_USERS")
    ENV["BANCO_EDGE_PROXY"] = "#{EDGE}/32"
  end

  teardown do
    %w[BANCO_EDGE_PROXY BANCO_TEACHER_USERS].each { |k| @saved.key?(k) ? ENV[k] = @saved[k] : ENV.delete(k) }
  end

  def student_get(path) = on(:web, path, headers: STUDENT, remote_addr: EDGE)

  def nonce_of(header) = header[/'nonce-([^']+)'/, 1]

  test "/diagnosis carries the exact policy with a nonce" do
    student_get("/diagnosis")
    assert_response :success
    header = response.headers["Content-Security-Policy"]
    nonce = nonce_of(header)
    assert_match(/\A[A-Za-z0-9+\/=]{16,}\z/, nonce)
    assert_equal EXPECTED.sub("NONCE", nonce), header
  end

  test "script-src never allows unsafe-inline, and unsafe-inline is only in style-src" do
    student_get("/diagnosis")
    directives = response.headers["Content-Security-Policy"].split("; ").to_h { |d| d.split(" ", 2) }
    refute_includes directives.fetch("script-src"), "unsafe-inline"
    refute_includes directives.fetch("script-src"), "unsafe-eval"
    assert_equal %w[style-src], directives.select { |_k, v| v.include?("unsafe-inline") }.keys
  end

  test "the nonce changes on every request" do
    nonces = 3.times.map { student_get("/diagnosis"); nonce_of(response.headers["Content-Security-Policy"]) }
    assert_equal 3, nonces.uniq.size
  end

  test "every script tag of the page carries the nonce of its response" do
    student_get("/diagnosis")
    nonce = nonce_of(response.headers["Content-Security-Policy"])
    scripts = Nokogiri::HTML(response.body).css("script")
    assert_operator scripts.size, :>=, 2 # the importmap and the module that starts it
    scripts.each { |s| assert_equal nonce, s["nonce"], "script without the nonce: #{s.to_html[0, 80]}" }
    refute Nokogiri::HTML(response.body).css("script").any? { |s| s["src"].to_s =~ %r{\Ahttps?://} }
  end

  test "the page does not load Turbo and points only at the app's own vendor files" do
    student_get("/diagnosis")
    refute_includes response.body, "turbo.min"
    assert_includes response.body, "/vendor/katex@0.19.0/katex.min.css"
    assert_no_match(%r{https?://(?!www\.w3\.org)}, response.body)
  end

  test "an agent figure is served as an image with nosniff and a sandbox policy" do
    Dir.mktmpdir do |dir|
      svg = '<svg xmlns="http://www.w3.org/2000/svg" width="10" height="10"><script>alert(1)</script></svg>'
      sha = Digest::SHA256.hexdigest(svg)
      File.write(File.join(dir, "#{sha}.svg"), svg)
      Rails.application.config.x.item_assets_dir = dir
      student_get("/assets/items/#{sha}.svg")
      assert_response :success
      assert_equal "image/svg+xml", response.media_type
      assert_equal "nosniff", response.headers["X-Content-Type-Options"]
      assert_equal "default-src 'none'; style-src 'unsafe-inline'; sandbox", response.headers["Content-Security-Policy"]
    ensure
      Rails.application.config.x.item_assets_dir = nil
    end
  end

  test "a figure that does not exist, or is not named by a digest, is a 404; anyone else is refused" do
    student_get("/assets/items/#{'0' * 64}.svg")
    assert_response :not_found
    student_get("/assets/items/..%2F..%2Fetc%2Fpasswd.svg")
    assert_response :not_found
    on(:web, "/assets/items/#{'0' * 64}.svg", remote_addr: "10.0.0.5")
    assert_response :forbidden
  end

  test "figures are not served on the API listener" do
    on(:api, "/assets/items/#{'0' * 64}.svg", headers: STUDENT, remote_addr: EDGE)
    assert_response :not_found
  end
end
