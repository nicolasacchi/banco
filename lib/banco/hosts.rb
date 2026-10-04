# frozen_string_literal: true

module Banco
  # Host header allowlist for production (DNS rebinding protection, D-072). The web
  # listener is reached through Traefik as banco.scc.im; the harness listener by the
  # Chrome container as banco-harness; the API listener by the CLI on loopback
  # (127.0.0.1 or localhost, any port). BANCO_EXTRA_HOSTS adds comma-separated names.
  # /up is never checked, so the container health check (Host: localhost:3000) works.
  module Hosts
    DEFAULT = %w[banco.scc.im banco banco-harness 127.0.0.1 localhost].freeze

    module_function

    def allowed(env = ENV)
      DEFAULT + env.fetch("BANCO_EXTRA_HOSTS", "").split(",").map(&:strip).reject(&:empty?)
    end

    def exclude(request) = request.path == "/up"
  end
end
