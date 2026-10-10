require "test_helper"

# The harness listener (port 3200): the page and the files Chrome loads to run an
# agent's generator or verify. Internal, cookie-less, token in the address (A-02).
class HarnessListenerTest < ActionDispatch::IntegrationTest
  GENERATOR = "export function generate(seed, rng) { return { display: {}, answer: 1 }; }".freeze

  setup do
    @stage = Validation::Harness::Staging.put({ "generator.mjs" => GENERATOR })
    @token = Validation::Harness.issue("stage", @stage)
  end

  test "the page is served with a CSP that allows no connection, and sets no cookie" do
    on(:harness, "/h/#{@token}/harness.html")
    assert_response :success
    assert_equal "text/html; charset=utf-8", response.headers["Content-Type"]
    csp = response.headers["Content-Security-Policy"]
    assert_includes csp, "default-src 'none'"
    assert_includes csp, "script-src 'self'"
    assert_includes csp, "connect-src 'none'"
    assert_includes csp, "img-src 'none'"
    assert_includes csp, "base-uri 'none'"
    assert_includes csp, "form-action 'none'"
    assert_nil response.headers["Set-Cookie"]
    assert_equal "no-store", response.headers["Cache-Control"]
    assert_equal "nosniff", response.headers["X-Content-Type-Options"]
    assert_no_match(/token|secret|csrf|authenticity/i, response.body.sub(/<!--.*?-->/m, ""))
  end

  test "the runner and the modules are JavaScript, the revision's files come from the token" do
    on(:harness, "/h/#{@token}/runner.mjs")
    assert_response :success
    assert_equal "text/javascript; charset=utf-8", response.headers["Content-Type"]
    assert_includes response.body, "bancoHarness"
    on(:harness, "/h/#{@token}/generator.mjs")
    assert_equal GENERATOR, response.body
    on(:harness, "/h/#{@token}/verify.mjs")
    assert_response :not_found
  end

  test "a stored revision's files are served by a rev token" do
    subject = Subject.create!(key: "math", name_it: "Matematica", position: 1)
    item = Item.create!(subject: subject, key: "x", kind: "diagnosis_item")
    revision = ItemRevision.create!(item: item, seq: 1, body_json: "{}", files_json: JSON.generate("generator.mjs" => "export const a = 1;"), file_sessions_json: "{}")
    on(:harness, "/h/#{Validation::Harness.issue('rev', revision.id)}/generator.mjs")
    assert_equal "export const a = 1;", response.body
  end

  test "the lesson render host: only for a lesson/2 revision's token, with a CSP that allows no connection, no cookie, the student's body" do
    revision = begin
      subject = Subject.create!(key: "math", name_it: "Matematica", position: 1)
      lesson = Lesson.create!(subject: subject, key: "ripasso.math.host", kind: "ripasso")
      body = JSON.parse(File.read(Rails.root.join("test/fixtures/lesson2/served/equations.json"))).merge("key" => "ripasso.math.host")
      LessonRevision.create!(lesson: lesson, seq: 1, source_md: "x", source_sha256: "a" * 64, body_json: JSON.generate(body), rules_version: "8", warnings_json: "[]")
    end
    token = Validation::Harness.issue("lrev", revision.id)
    on(:harness, "/h/#{token}/lesson-render.html?theme=dark")
    assert_response :success
    assert_nil response.headers["Set-Cookie"]
    assert_equal "no-store", response.headers["Cache-Control"]
    csp = response.headers["Content-Security-Policy"]
    assert_includes csp, "connect-src 'none'"
    assert_includes csp, "default-src 'none'"
    assert_match(/script-src 'self' 'sha256-/, csp)
    assert_no_match(/unsafe-inline.*script|script-src[^;]*unsafe-inline/, csp)
    assert_select "html[data-theme=dark]"
    assert_select "script[type=importmap]"
    assert_select "script#lesson-body[type='application/json']"
    assert_no_match(/csrf|authenticity|token/i, response.body.sub(/<!--.*?-->/m, ""))
    # the page carries the student's projection of the body: nothing from the stored answers
    assert_no_match(/"answer"|solution_it|final_it/, css_select("script#lesson-body").first.text)
    # every inline script the page runs is covered by a hash of the CSP
    css_select("script:not([src]):not([type='application/json'])").each do |node|
      assert_includes csp, "'sha256-#{Base64.strict_encode64(Digest::SHA256.digest(node.children.map(&:to_s).join))}'"
    end
    # a token has one use: a lesson token opens no item file, an item token opens no lesson host
    on(:harness, "/h/#{token}/generator.mjs")
    assert_response :not_found
    item_token = Validation::Harness.issue("rev", 1)
    on(:harness, "/h/#{item_token}/lesson-render.html")
    assert_response :not_found
    on(:harness, "/h/#{Validation::Harness.issue('stage', Validation::Harness::Staging.put({}))}/lesson-render.html")
    assert_response :not_found
    on(:harness, "/h/#{Validation::Harness.issue('lrev', 0)}/lesson-render.html")
    assert_response :not_found
    on(:harness, "/h/not-a-token/lesson-render.html")
    assert_response :not_found
    on(:web, "/h/#{token}/lesson-render.html")
    assert_response :not_found
    on(:api, "/h/#{token}/lesson-render.html")
    assert_response :not_found
  end

  test "the libraries are public, and only the two libraries" do
    on(:harness, "/lib/rng.mjs")
    assert_response :success
    assert_includes response.body, "export function makeRng"
    on(:harness, "/lib/fmt.mjs")
    assert_response :success
    on(:harness, "/lib/other.mjs")
    assert_response :not_found
    on(:harness, "/lib/..%2F..%2Fconfig%2Fdatabase.yml")
    assert_response :not_found
  end

  test "a bad, expired or foreign token is 404" do
    on(:harness, "/h/nonsense/harness.html")
    assert_response :not_found
    expired = Validation::Harness.issue("stage", @stage, ttl: -5)
    on(:harness, "/h/#{expired}/harness.html")
    assert_response :not_found
    encoded, signature = @token.split(".")
    forged = "#{Base64.urlsafe_encode64(Base64.urlsafe_decode64(encoded).sub('stage', 'stage'), padding: false)}.#{signature.reverse}"
    on(:harness, "/h/#{forged}/harness.html")
    assert_response :not_found
    on(:harness, "/h/#{@token}/item.json")
    assert_response :not_found
  end

  test "the harness routes exist only on the harness listener" do
    %i[web api].each do |listener|
      on(listener, "/h/#{@token}/harness.html")
      assert_response :not_found, listener.to_s
      on(listener, "/lib/rng.mjs")
      assert_response :not_found, listener.to_s
    end
  end

  test "the harness listener serves nothing of the app" do
    [ "/api/v1/schema", "/diagnosis", "/teacher", "/" ].each do |path|
      on(:harness, path)
      assert_response :not_found, path
    end
  end

  test "a token binds what it names: a rev token is not a stage token" do
    assert_equal [ "stage", @stage ], Validation::Harness.verify(@token)
    assert_nil Validation::Harness.verify(Validation::Harness.issue("other", 1))
    assert_nil Validation::Harness.verify("")
    assert_nil Validation::Harness.verify(nil)
  end

  test "the harness version changes with the libraries (it is stored with every validation)" do
    assert_match(/\A\h{64}\z/, Validation::Harness.version)
  end
end
