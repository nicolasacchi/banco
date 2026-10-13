require "test_helper"
require "support/page_world"

# The pages origin (D-289, SPEC B3): exact headers per mount, lookup by manifest, 404 shapes, no cookies.
class PagesAppTest < ActiveSupport::TestCase
  include PageWorld

  ORIGIN = "https://pages.example.test"
  PARENT = "https://app.example.test"

  setup do
    Banco::PagesApp.reset_cookie_count!
    @prod = Banco::PagesApp.new(mode: :production, origin: ORIGIN, parent: PARENT)
    @validate = Banco::PagesApp.new(mode: :validate, origin: "http://banco-pages-internal:3200", parent: "http://banco-harness:3200")
    @rev = store_page!
    @sha = @rev.bundle_sha256
    @dir = Dir.mktmpdir
    @env = { "BANCO_PAGES_DIR" => nil }
  end

  teardown do
    FileUtils.rm_rf(@dir)
    Banco::PagesApp.reset_cookie_count!
  end

  def get(app, path, headers = {}, method: "GET")
    status, h, body = app.call(Rack::MockRequest.env_for(path, { method: method }.merge(headers)))
    [ status, h, body.each.to_a.join ]
  end

  def enabled(&) = with_env({ "BANCO_PAGES_ENABLED" => "1" }, &)

  test "the production mount answers 404 to everything while BANCO_PAGES_ENABLED is 0" do
    pass_page!(@rev)
    with_env("BANCO_PAGES_ENABLED" => "0") do
      status, headers, body = get(@prod, "/p/#{@sha}/k1.0/")
      assert_equal 404, status
      assert_equal "", body
      assert_equal "no-store", headers["cache-control"]
      assert_equal 404, get(@prod, "/kit/banco-page@1.0/bridge.mjs").first
    end
  end

  test "the shell of a validated revision carries the exact headers" do
    pass_page!(@rev)
    enabled do
      status, h, body = get(@prod, "/p/#{@sha}/k1.0/")
      assert_equal 200, status
      assert_equal "text/html; charset=utf-8", h["content-type"]
      assert_equal "nosniff", h["x-content-type-options"]
      assert_equal "no-referrer", h["referrer-policy"]
      assert_equal "cross-origin", h["cross-origin-resource-policy"]
      assert_equal "public, max-age=31536000, immutable", h["cache-control"]
      assert_match(/camera=\(\), microphone=\(\)/, h["permissions-policy"])
      assert_nil h["set-cookie"]
      assert_nil h["access-control-allow-origin"]
      importmap = body[%r{<script type="importmap">(.*?)</script>}, 1]
      hash = Base64.strict_encode64(Digest::SHA256.digest(importmap))
      csp = h["content-security-policy"]
      assert_equal [ "sandbox allow-scripts", "default-src 'none'", "script-src #{ORIGIN} 'sha256-#{hash}'", "style-src #{ORIGIN} 'unsafe-inline'", "img-src #{ORIGIN} data: blob:",
                     "font-src #{ORIGIN}", "media-src #{ORIGIN} blob:", "connect-src 'none'", "worker-src 'none'", "frame-src 'none'", "child-src 'none'", "object-src 'none'",
                     "manifest-src 'none'", "form-action 'none'", "base-uri 'none'", "frame-ancestors #{PARENT}" ], csp.split("; ")
      assert_includes body, %(<script type="module" src="/kit/banco-page@1.0/boot.mjs"></script><script type="module" src="main.mjs"></script>)
      assert_includes body, %(<html lang="it" data-theme="cream">)
      assert_includes body, %(href="/kit/banco-page@1.0/page.css")
      assert_no_match(/axe|audit/, body) # the audit is the validation mount's
    end
  end

  test "the shell is generated from the manifest: libs in the import map, the texts escaped, style.css only when the bundle has one" do
    files = page_files do |f|
      f["page.json"] = JSON.generate(JSON.parse(f["page.json"]).merge("libs" => [ "three@0.186.1" ], "webgl" => true, "fallback_it" => "Non parte qui & ora. Nella scheda trovi la figura ferma e il testo \"pronto\"."))
      f["main.mjs"] = "import * as THREE from 'three'\n#{f['main.mjs']}"
      f["style.css"] = "p { margin: 0 }"
    end
    rev = store_page!(files, key: "math.pages-sample")
    pass_page!(rev)
    enabled do
      _, _, body = get(@prod, "/p/#{rev.bundle_sha256}/k1.0/")
      assert_includes body, "/vendor/three@0.186.1/three.module.js"
      assert_includes body, %(<link rel="stylesheet" href="style.css">)
      assert_includes body, "Non parte qui &amp; ora."
      assert_includes body, "&quot;pronto&quot;"
    end
  end

  test "the production mount serves only a revision that passed validation with that kit; the validation mount any stored one" do
    enabled do
      assert_equal 404, get(@prod, "/p/#{@sha}/k1.0/").first
      pass_page!(@rev, kit: "1.0")
      assert_equal 200, get(@prod, "/p/#{@sha}/k1.0/").first
      assert_equal 404, get(@prod, "/p/#{@sha}/k1.1/").first, "an unreleased kit"
    end
    other = store_page!(page_files { |f| f["maths.mjs"] += "\n// two" })
    assert_equal 200, get(@validate, "/p/#{other.bundle_sha256}/k1.0/").first
  end

  test "an operator-stored selftest revision is served unvalidated, a validated-less agent revision under a normal key is not" do
    subject = page_subject!
    files = page_files { |f| f["page.json"] = f["page.json"].sub("math.pages-sample", "math.pages-selftest") }
    outcome = Validation::PageChecks.call(files, key: "math.pages-selftest", subject: "math", operator: true)
    rev, = Pages::Submit.store(key: "math.pages-selftest", subject: subject, outcome: outcome, warnings: [], author: nil, operator: true)
    enabled do
      assert_equal 200, get(@prod, "/p/#{rev.bundle_sha256}/k1.0/").first
      assert_equal 404, get(@prod, "/p/#{@sha}/k1.0/").first, "an unvalidated revision under another key"
    end
    page = rev.page
    sneaky = PageRevision.create!(page: page, seq: 2, base_revision_id: rev.id, manifest_json: rev.manifest_json, bundle_sha256: "a" * 64, rules_version: "x", warnings_json: "[]", author_session: page_author!)
    enabled { assert_equal 404, get(@prod, "/p/#{sneaky.bundle_sha256}/k1.0/").first, "a revision under the key that an agent session wrote" }
  end

  test "a file of the bundle is found by lookup in the manifest, with CORS and a sandboxing CSP" do
    pass_page!(@rev)
    enabled do
      status, h, body = get(@prod, "/p/#{@sha}/k1.0/main.mjs")
      assert_equal 200, status
      assert_equal "text/javascript; charset=utf-8", h["content-type"]
      assert_equal "*", h["access-control-allow-origin"]
      assert_equal "sandbox; default-src 'none'", h["content-security-policy"]
      assert_includes body, 'import { banco } from "banco"'
      assert_equal 200, get(@prod, "/p/#{@sha}/k1.0/maths.mjs").first
      %w[../main.mjs nope.mjs page.json assets/ %2e%2e/main.mjs main.mjs/x].each { |p| assert_equal 404, get(@prod, "/p/#{@sha}/k1.0/#{p}").first, p }
      assert_equal 404, get(@prod, "/p/#{'0' * 64}/k1.0/main.mjs").first
    end
  end

  test "the kit and the vendored libraries are served by listing, harness files only on the validation mount" do
    enabled do
      status, h, = get(@prod, "/kit/banco-page@1.0/bridge.mjs")
      assert_equal 200, status
      assert_equal "*", h["access-control-allow-origin"]
      assert_equal "font/woff2", get(@prod, "/kit/banco-page@1.0/fonts/atkinson-hyperlegible-latin-400-normal.woff2")[1]["content-type"]
      assert_equal 404, get(@prod, "/kit/banco-page@1.0/../1.0/bridge.mjs").first
      assert_equal 404, get(@prod, "/kit/banco-page@2.0/bridge.mjs").first
      assert_equal 200, get(@prod, "/vendor/three@0.186.1/three.module.js").first
      assert_equal 200, get(@prod, "/vendor/three@0.186.1/three.core.js").first
      assert_equal 404, get(@prod, "/vendor/three@0.186.1/SHA256SUMS").first
      assert_equal 404, get(@prod, "/vendor/three@0.1.0/three.module.js").first
      assert_equal 404, get(@prod, "/vendor/axe-core@4.14.0/axe.min.js").first, "a harness library is not a page library"
      assert_equal 404, get(@prod, "/harness/axe-core@4.14.0/axe.min.js").first
    end
    assert_equal 200, get(@validate, "/harness/axe-core@4.14.0/axe.min.js").first
    assert_equal 200, get(@validate, "/harness/page-audit@1/audit.mjs").first
    assert_equal 404, get(@validate, "/harness/axe-core@4.14.0/nope.js").first
    assert_equal 404, get(@validate, "/harness/page-audit@2/audit.mjs").first
  end

  test "the validation shell loads axe and the audit before main.mjs" do
    _, _, body = get(@validate, "/p/#{@sha}/k1.0/")
    assert_includes body, %(<script src="/harness/axe-core@4.14.0/axe.min.js"></script>)
    assert body.index("audit.mjs") < body.index("main.mjs")
  end

  test "other methods and paths are a bare 404, a HEAD has no body" do
    pass_page!(@rev)
    enabled do
      %w[POST PUT DELETE OPTIONS PATCH].each { |m| assert_equal 404, get(@prod, "/p/#{@sha}/k1.0/", method: m).first, m }
      %w[/ /up /p /p/x /api/v1/schema /teacher /h/x/harness.html /p/ABC/k1.0/].each { |p| assert_equal [ 404, "" ], get(@prod, p).then { |s, _, b| [ s, b ] }, p }
      status, h, body = get(@prod, "/p/#{@sha}/k1.0/", method: "HEAD")
      assert_equal [ 200, "" ], [ status, body ]
      assert_operator h["content-length"].to_i, :>, 100
    end
  end

  test "no response ever sets a cookie, and a Cookie header is ignored and counted" do
    pass_page!(@rev)
    enabled do
      assert_equal 0, Banco::PagesApp.cookie_headers_seen
      [ "/p/#{@sha}/k1.0/", "/kit/banco-page@1.0/page.css", "/vendor/three@0.186.1/three.module.js", "/nope" ].each do |path|
        _, h, = get(@prod, path, { "HTTP_COOKIE" => "authelia_session=abc" })
        assert_nil h["set-cookie"], path
      end
      assert_equal 4, Banco::PagesApp.cookie_headers_seen
      get(@prod, "/p/#{@sha}/k1.0/")
      assert_equal 4, Banco::PagesApp.cookie_headers_seen
    end
  end

  test "the listener switch: the pages port is the production app, the harness port with the internal host the validation app, the rest Rails" do
    rails = ->(_env) { [ 200, {}, [ "rails" ] ] }
    pages = ->(_env) { [ 200, {}, [ "pages" ] ] }
    validation = ->(_env) { [ 200, {}, [ "validation" ] ] }
    switch = Banco::ListenerSwitch.new(rails, production: pages, validation: validation, allow_test_seam: true)
    call = ->(listener, host) { switch.call(Rack::MockRequest.env_for("/x", "HTTP_HOST" => host, "banco.test_listener" => listener)).last.first }
    assert_equal "pages", call.call("pages", "banco.scc.im")
    assert_equal "validation", call.call("harness", "banco-pages-internal:3200")
    assert_equal "rails", call.call("harness", "banco-harness:3200")
    assert_equal "rails", call.call("web", "banco-pages-internal")
    assert_equal "rails", call.call("api", "banco-pages-internal")
    assert_equal "rails", call.call(nil, "pages.banco.scc.im")
    socket = Struct.new(:port) { def local_address = Addrinfo.tcp("127.0.0.1", port) }
    prod = Banco::ListenerSwitch.new(rails, production: pages, validation: validation)
    with_env("WEB_PORT" => "3000", "API_PORT" => "3100", "HARNESS_PORT" => "3200", "PAGES_PORT" => "3300") do
      assert_equal "pages", prod.call(Rack::MockRequest.env_for("/x", "puma.socket" => socket.new(3300))).last.first
      assert_equal "rails", prod.call(Rack::MockRequest.env_for("/x", "HTTP_HOST" => "pages.banco.scc.im", "puma.socket" => socket.new(3000))).last.first
      assert_equal "rails", prod.call(Rack::MockRequest.env_for("/x", "HTTP_HOST" => "banco-pages-internal", "banco.test_listener" => "pages", "puma.socket" => socket.new(3000))).last.first, "the test seam is off in production"
    end
  end
end
