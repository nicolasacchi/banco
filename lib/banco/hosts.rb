# frozen_string_literal: true

module Banco
  # Host header allowlist for production (DNS rebinding protection, D-072). The web
  # listener is reached through Traefik as banco.scc.im; the harness listener by the
  # Chrome container as banco-harness; the API listener by the CLI on loopback
  # (127.0.0.1 or localhost, any port) and, since D-327, by the public host of the API
  # (BANCO_API_HOST, default api.banco.scc.im) through Traefik. BANCO_EXTRA_HOSTS adds
  # comma-separated names. /up is never checked, so the container health check
  # (Host: localhost:3000) works.
  #
  # The allowlist is one list for the process, but each public name belongs to one
  # listener (ListenerHosts): the API's host only on the API listener, the web host
  # never on it, so a router that points banco.scc.im at the API port, or the API's
  # name at the web port (where Remote-User is trusted), is refused by the app too.
  module Hosts
    WEB_HOST = "banco.scc.im"
    API_HOST = "api.banco.scc.im"
    DEFAULT = [ WEB_HOST, "banco", "banco-harness", "127.0.0.1", "localhost" ].freeze

    module_function

    def api_host(env = ENV) = env.fetch("BANCO_API_HOST", API_HOST).strip.downcase.presence || API_HOST

    def allowed(env = ENV)
      DEFAULT + [ api_host(env) ] + env.fetch("BANCO_EXTRA_HOSTS", "").split(",").map(&:strip).reject(&:empty?)
    end

    def exclude(request) = request.path == "/up"

    # The host name of a Host or X-Forwarded-Host value: lowercase, no port, no trailing dot.
    def name_of(value)
      value.to_s.split(",").first.to_s.strip.downcase.sub(/\A\[(.*)\](:\d+)?\z/, '\1').sub(/:\d+\z/, "").chomp(".")
    end

    # True when this listener must not answer to this host: the web host on the API listener, the API host anywhere else.
    def refused_on?(listener, host, env = ENV)
      name = name_of(host)
      listener == :api ? name == WEB_HOST : name == api_host(env)
    end

    # Rack middleware after ListenerTag: 403 for a request whose Host (or X-Forwarded-Host) names the other listener's host.
    class ListenerHosts
      def initialize(app) = @app = app

      def call(env)
        return @app.call(env) if env["PATH_INFO"] == "/up"

        listener = env[ListenerTag::TAG_KEY]
        if [ env["HTTP_HOST"], env["HTTP_X_FORWARDED_HOST"] ].any? { |host| Hosts.refused_on?(listener, host) }
          return [ 403, { "content-type" => "text/plain" }, [ "Blocked host" ] ]
        end

        @app.call(env)
      end
    end
  end
end
