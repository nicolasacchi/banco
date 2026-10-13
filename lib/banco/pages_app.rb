# frozen_string_literal: true

require "digest"
require "json"
require "rack"
require "concurrent"

module Banco
  # The free pages origin (D-289, SPEC B3): a plain Rack app with no Rails session, no cookies, no CSRF and no identity.
  # There is nothing to authenticate and nothing to protect but the bytes. It is mounted in config.ru, before Rails, by
  # ListenerSwitch, so no Rails middleware (session, cookies, the app CSP, default headers) ever touches a page response.
  # Two mounts, each with its mode fixed at construction (never a request parameter):
  #
  #   :production  the pages listener (PAGES_PORT), reached by Traefik: shells, bundle files, kit, vendored libraries
  #   :validate    the harness listener under Host: banco-pages-internal: the same, plus /harness/* (axe, the audit)
  #
  #   GET /p/:sha/k:kit/              the shell, generated from the stored manifest and the kit version
  #   GET /p/:sha/k:kit/:path         a file of the bundle, found by lookup in the manifest (never a path join)
  #   GET /kit/banco-page@:kit/:file  our kit, a released version
  #   GET /vendor/:lib@:ver/:path     vendored libraries for pages (vendor/pages/), found by listing
  #   GET /harness/:lib@:ver/:path    axe-core and the audit: validation mount only
  #   anything else                   404, no body
  #
  # No Set-Cookie, ever. A Cookie header is ignored and counted (cookie_headers_seen): a cookie reaching this app means a
  # layer in front of it (the Traefik strip) is broken, and health fails on it.
  class PagesApp
    SHA = /[0-9a-f]{64}/
    KIT = /\d+\.\d+/
    SHELL = %r{\A/p/(#{SHA})/k(#{KIT})/\z}o
    FILE = %r{\A/p/(#{SHA})/k(#{KIT})/(.+)\z}o
    KITFILE = %r{\A/kit/banco-page@(#{KIT})/(.+)\z}o
    LIBFILE = %r{\A/vendor/([a-z][a-z0-9-]*)@(\d+\.\d+\.\d+)/(.+)\z}
    HARNESS = %r{\A/harness/([a-z][a-z0-9-]*)@(\d+(?:\.\d+)*)/(.+)\z}
    AUDIT = File.expand_path("../harness/page_audit.mjs", __dir__)

    PERMISSIONS = "camera=(), microphone=(), geolocation=(), usb=(), serial=(), hid=(), bluetooth=(), payment=(), clipboard-read=(), display-capture=()"

    @cookie_headers = Concurrent::AtomicFixnum.new(0)

    class << self
      def cookie_headers_seen = @cookie_headers.value
      def count_cookie_header! = @cookie_headers.increment
      def reset_cookie_count! = @cookie_headers.value = 0
    end

    attr_reader :mode

    # origin and parent: strings, fixed per mount (the production pair is https://pages.banco.scc.im and
    # https://banco.scc.im; the validation pair the internal host names, B3).
    def initialize(mode:, origin:, parent:)
      raise ArgumentError, "mode is :production or :validate" unless %i[production validate].include?(mode)

      @mode = mode
      @origin = origin
      @parent = parent
    end

    def call(env)
      self.class.count_cookie_header! if env["HTTP_COOKIE"].to_s != ""
      method = env["REQUEST_METHOD"]
      return not_found unless %w[GET HEAD].include?(method)
      return not_found if @mode == :production && !Pages.enabled?

      path = Rack::Utils.unescape_path(env["PATH_INFO"].to_s)
      return not_found if path.include?("\0") || path.bytesize > 512

      reply = route(path)
      return not_found unless reply

      respond(reply, head: method == "HEAD")
    rescue StandardError => e
      Rails.logger.error("PagesApp: #{e.class}: #{e.message}") if defined?(Rails)
      not_found
    end

    private

    Reply = Struct.new(:body, :type, :csp, :cors, keyword_init: true)

    def route(path)
      if (m = SHELL.match(path)) then shell(m[1], m[2])
      elsif (m = FILE.match(path)) then bundle_file(m[1], m[2], m[3])
      elsif (m = KITFILE.match(path)) then static(Pages::Kit.read(m[1], m[2]), m[2])
      elsif (m = LIBFILE.match(path)) then static(lib_bytes(m[1], m[2], m[3], scope: "page"), m[3])
      elsif @mode == :validate && (m = HARNESS.match(path)) then harness(m[1], m[2], m[3])
      end
    end

    def lib_bytes(name, version, file, scope:)
      return nil unless Pages::Libs.config.dig(name, "scope") == scope

      Pages::Libs.read(name, version, file)
    end

    def static(bytes, name)
      return nil unless bytes

      Reply.new(body: bytes, type: Pages.media_type(name) || "application/octet-stream", csp: "sandbox; default-src 'none'", cors: true)
    end

    def harness(name, version, file)
      if name == "page-audit" && version == "1" && file == "audit.mjs"
        static(File.binread(AUDIT), file)
      else
        static(lib_bytes(name, version, file, scope: "harness"), file)
      end
    end

    # A revision is served on the production mount only with a kit that a passed validation of it ran with (what was
    # validated is what runs, B6); the validation mount serves any stored revision with any released kit.
    def servable(sha, kit)
      return nil unless Pages::Kit.released?(kit)

      ActiveRecord::Base.connection_pool.with_connection do
        revision = PageRevision.find_by(bundle_sha256: sha) or next nil
        # The browser matrix page (D-289, SPEC B10.8) is stored by the operator's console and never passes validation (it tries the
        # forbidden on purpose): only its key is served without a passed validation.
        next nil if @mode == :production && !selftest?(revision) && !revision.validations.exists?(status: "passed", kit_version: kit)

        revision
      end
    end

    def selftest?(revision) = Pages::Submit.reserved?(revision.page.key) && revision.author_session_id.nil?

    def shell(sha, kit)
      ActiveRecord::Base.connection_pool.with_connection do
        revision = servable(sha, kit) or next nil
        rendered = Pages::Shell.render(revision.manifest, paths: revision.files.pluck(:path), kit: kit, mode: @mode == :validate ? :validate : :production,
                                                          origin: @origin, parent: @parent)
        Reply.new(body: rendered.html, type: "text/html; charset=utf-8", csp: rendered.csp, cors: false)
      end
    end

    def bundle_file(sha, kit, path)
      ActiveRecord::Base.connection_pool.with_connection do
        revision = servable(sha, kit) or next nil
        file = revision.files.find_by(path: path) or next nil
        bytes = Pages::Store.read(file.sha256) or next nil
        Reply.new(body: bytes, type: file.media_type, csp: "sandbox; default-src 'none'", cors: true)
      end
    end

    def respond(reply, head:)
      body = reply.body
      headers = {
        "content-type" => reply.type, "content-length" => body.bytesize.to_s, "content-security-policy" => reply.csp,
        "x-content-type-options" => "nosniff", "referrer-policy" => "no-referrer", "permissions-policy" => PERMISSIONS,
        "cross-origin-resource-policy" => "cross-origin", "cache-control" => "public, max-age=31536000, immutable"
      }
      headers["access-control-allow-origin"] = "*" if reply.cors
      [ 200, headers, head ? [] : [ body ] ]
    end

    def not_found
      [ 404, { "content-length" => "0", "cache-control" => "no-store", "x-content-type-options" => "nosniff", "referrer-policy" => "no-referrer" }, [] ]
    end
  end
end
