# frozen_string_literal: true

require_relative "listeners"

module Banco
  # Rack middleware that tags every request with the listener it arrived on:
  # env["banco.listener"] is :web, :api, :harness or nil.
  #
  # The tag comes from the LOCAL port of the accepted socket (Puma exposes the
  # socket as env["puma.socket"]), never from request.port, SERVER_PORT or the
  # Host header: those are client-controlled and a request to the API port
  # could claim to be on the web port.
  #
  # Test seam: env["banco.test_listener"] is honoured only when constructed
  # with allow_test_seam: true (the test environment). In production the key is
  # ignored even if a client could somehow set it.
  class ListenerTag
    SOCKET_KEY = "puma.socket"
    TEST_SEAM_KEY = "banco.test_listener"
    TAG_KEY = "banco.listener"

    def initialize(app, allow_test_seam: false)
      @app = app
      @allow_test_seam = allow_test_seam
    end

    def call(env)
      env[TAG_KEY] = listener_for(env)
      @app.call(env)
    end

    private

    def listener_for(env)
      if @allow_test_seam && env.key?(TEST_SEAM_KEY)
        return env[TEST_SEAM_KEY]&.to_sym
      end

      socket = env[SOCKET_KEY]
      return nil unless socket.respond_to?(:local_address)

      Listeners.name_for_port(socket.local_address.ip_port)
    rescue StandardError
      nil
    end
  end
end
