# frozen_string_literal: true

require "base64"
require "digest"
require "openssl"

module Validation
  # The harness: what the harness listener (port 3200) serves to Chrome so that an
  # agent's generator.mjs and verify.mjs run only in the browser (firm rule 3).
  #
  #   /h/<run-token>/harness.html      the page (no cookie, no secret, CSP without connections)
  #   /h/<run-token>/runner.mjs        the runner
  #   /h/<run-token>/generator.mjs     the revision's files, by token
  #   /h/<run-token>/verify.mjs
  #   /lib/rng.mjs, /lib/fmt.mjs       the two libraries a generator may import
  #
  # The run token is an HMAC bound to what it serves (a stored revision, or a
  # dry-run's staged files) and to an expiry of 10 minutes. It is a capability in
  # the address of one run; it is never an API token and the page holds nothing else.
  module Harness
    DIR = File.expand_path("../harness", __dir__)
    PAGES = %w[harness.html runner.mjs].freeze
    MODULES = %w[generator.mjs verify.mjs].freeze
    LIBS = %w[rng.mjs fmt.mjs].freeze
    TTL = 600

    # No connection of any kind, no image, no frame, only the page's own scripts.
    CSP = "default-src 'none'; script-src 'self'; connect-src 'none'; img-src 'none'; base-uri 'none'; form-action 'none'"

    module_function

    def file(name) = File.read(File.join(DIR, name))

    # sha256 of the libraries and the runner: stored with every validation (A-07).
    def version
      @version ||= Digest::SHA256.hexdigest((LIBS + PAGES).sort.map { |n| "#{n}\n#{file(n)}" }.join("\n"))
    end

    def content_type(name) = name.end_with?(".html") ? "text/html; charset=utf-8" : "text/javascript; charset=utf-8"

    # Where Chrome reaches the harness listener: BANCO_HARNESS_URL in production
    # (http://banco-harness:3200 on the internal network), the local port otherwise.
    def base_url
      ENV["BANCO_HARNESS_URL"].presence || "http://127.0.0.1:#{Banco::Listeners.ports.fetch(:harness)}"
    end

    def page_url(token, generator: true, verify: false)
      query = []
      query << "generator=0" unless generator
      query << "verify=1" if verify
      "#{base_url}/h/#{token}/harness.html#{"?#{query.join('&')}" if query.any?}"
    end

    # ---- tokens ------------------------------------------------------------

    def key = Rails.application.key_generator.generate_key("banco/harness", 32)

    def issue(kind, id, ttl: TTL, now: Time.now.to_i)
      message = "#{kind}:#{id}:#{now + ttl}"
      "#{Base64.urlsafe_encode64(message, padding: false)}.#{sign(message)}"
    end

    # [kind, id] of a valid, unexpired token; nil otherwise.
    def verify(token, now: Time.now.to_i)
      encoded, signature = token.to_s.split(".", 2)
      return nil if encoded.blank? || signature.blank?

      message = Base64.urlsafe_decode64(encoded)
      return nil unless ActiveSupport::SecurityUtils.secure_compare(sign(message), signature)

      kind, id, expires = message.split(":", 3)
      return nil unless %w[rev stage].include?(kind) && expires.to_i >= now

      [ kind, id ]
    rescue ArgumentError
      nil
    end

    def sign(message) = OpenSSL::HMAC.hexdigest("SHA256", key, message)[0, 32]

    # ---- sources -------------------------------------------------------------

    # The text of generator.mjs or verify.mjs behind a token, or nil.
    def source(payload, name)
      kind, id = payload
      files = kind == "stage" ? Staging.fetch(id) : stored_files(id)
      files && files[name]
    end

    def stored_files(id)
      revision = ItemRevision.find_by(id: id)
      revision && JSON.parse(revision.files_json || "{}")
    end

    # The files of a dry run (nothing is written): in this process, for a few minutes.
    module Staging
      @items = Concurrent::Map.new

      class << self
        def put(files, ttl: TTL)
          sweep
          id = SecureRandom.hex(12)
          @items[id] = [ files.freeze, Time.now.to_i + ttl ]
          id
        end

        def fetch(id)
          files, expires = @items[id]
          files if files && expires >= Time.now.to_i
        end

        def drop(id) = @items.delete(id)

        private

        def sweep
          now = Time.now.to_i
          @items.each_pair { |id, (_, expires)| @items.delete(id) if expires < now }
        end
      end
    end
  end
end
