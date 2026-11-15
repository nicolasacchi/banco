# frozen_string_literal: true

require "uri"

module Banco
  # Host header allowlist for production (DNS rebinding protection, D-072). The web
  # listener is reached through Traefik as banco.scc.im; the harness listener by the
  # Chrome container as banco-harness; the API listener by the CLI on loopback
  # (127.0.0.1 or localhost, any port) and, since D-327, by the public host of the API
  # (BANCO_API_HOST, default api.banco.scc.im) through Traefik. Since D-332 the host of
  # BANCO_VIEW_URL (view links; today the same name as the API's, Traefik sends the
  # non-/api/ paths to the view listener) is allowed too. BANCO_EXTRA_HOSTS adds
  # comma-separated names. /up is never checked, so the container health check
  # (Host: localhost:3000) works.
  #
  # The allowlist is one list for the process, but each public name belongs to its listeners
  # (ListenerHosts): the API's host only on the API and view listeners, the web host never on
  # the API or view listener, so a router that points banco.scc.im at the API or view port, or
  # the API's name at the web port (where Remote-User is trusted), is refused by the app too.
  module Hosts
    WEB_HOST = "banco.scc.im"
    API_HOST = "api.banco.scc.im"
    DEFAULT = [ WEB_HOST, "banco", "banco-harness", "127.0.0.1", "localhost" ].freeze

    module_function

    def api_host(env = ENV) = env.fetch("BANCO_API_HOST", API_HOST).strip.downcase.presence || API_HOST

    # The host of BANCO_VIEW_URL, lowercase; nil when it is unset, not a URL with a host, or the web host (a typo there
    # must not make the web listener refuse its own name).
    def view_host(env = ENV)
      host = URI.parse(env["BANCO_VIEW_URL"].to_s.strip).host&.downcase&.chomp(".").presence
      host unless host == WEB_HOST
    rescue URI::InvalidURIError
      nil
    end

    def allowed(env = ENV)
      DEFAULT + [ api_host(env), view_host(env) ].compact + env.fetch("BANCO_EXTRA_HOSTS", "").split(",").map(&:strip).reject(&:empty?)
    end

    def exclude(request) = request.path == "/up"

    # The host name of a Host or X-Forwarded-Host value: lowercase, no port, no trailing dot.
    def name_of(value)
      value.to_s.split(",").first.to_s.strip.downcase.sub(/\A\[(.*)\](:\d+)?\z/, '\1').sub(/:\d+\z/, "").chomp(".")
    end

    # True when this listener must not answer to this host: the web host on the API and view listeners, the API host
    # (and a view host of its own) on any listener but its own. The API host serves view too while the two share the
    # name; with a distinct view host the API host is refused on :view.
    def refused_on?(listener, host, env = ENV)
      name = name_of(host)
      api = api_host(env)
      view = view_host(env)
      case listener
      when :api then name == WEB_HOST || (name == view && name != api)
      when :view then name == WEB_HOST || (name == api && name != view)
      else name == api || name == view
      end
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
