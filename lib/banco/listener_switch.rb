# frozen_string_literal: true

require_relative "listeners"
require_relative "listener_tag"

module Banco
  # Chooses the app by the LOCAL port of the accepted socket, exactly as ListenerTag does (never the Host header or
  # request.port for the choice of app), before any Rails middleware runs (D-281, SPEC B3):
  #
  #   pages listener (PAGES_PORT)               -> the production pages app
  #   harness listener, Host: banco-pages-internal -> the validation pages app (the mode is bound at construction)
  #   anything else                             -> Rails
  #
  # The Host header only picks between the two mounts of the internal harness listener, where the peer is Chrome inside
  # banco-internal; on the public side nothing depends on it. In the test environment the seam env["banco.test_listener"]
  # stands in for the socket, as it does for ListenerTag.
  class ListenerSwitch
    VALIDATION_HOST = "banco-pages-internal"

    def initialize(rails, production:, validation:, allow_test_seam: false)
      @rails = rails
      @production = production
      @validation = validation
      @allow_test_seam = allow_test_seam
    end

    def call(env)
      listener = listener_for(env)
      if listener == :pages
        @production.call(env)
      elsif listener == :harness && validation_host?(env)
        @validation.call(env)
      else
        @rails.call(env)
      end
    end

    private

    def validation_host?(env)
      env["HTTP_HOST"].to_s.downcase.split(":", 2).first == VALIDATION_HOST
    end

    def listener_for(env)
      if @allow_test_seam && env.key?(ListenerTag::TEST_SEAM_KEY)
        return env[ListenerTag::TEST_SEAM_KEY]&.to_sym
      end

      socket = env[ListenerTag::SOCKET_KEY]
      return nil unless socket.respond_to?(:local_address)

      Listeners.name_for_port(socket.local_address.ip_port)
    rescue StandardError
      nil
    end
  end
end
