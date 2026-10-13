# frozen_string_literal: true

module Banco
  # One Puma process serves four listeners (D-04, D-289). The names are WEB_PORT,
  # API_PORT, HARNESS_PORT and PAGES_PORT (the free pages origin, release 2), never
  # PORT: PORT would let a platform default collapse the binds into one.
  module Listeners
    DEFAULTS = { web: 3000, api: 3100, harness: 3200, pages: 3300 }.freeze
    ENV_KEYS = { web: "WEB_PORT", api: "API_PORT", harness: "HARNESS_PORT", pages: "PAGES_PORT" }.freeze

    module_function

    def ports(env = ENV)
      DEFAULTS.to_h { |name, default| [ name, Integer(env.fetch(ENV_KEYS.fetch(name), default)) ] }
    end

    # Startup assertion: the ports must differ.
    def assert_distinct!(env = ENV)
      p = ports(env)
      raise ArgumentError, "WEB_PORT, API_PORT, HARNESS_PORT and PAGES_PORT must differ: #{p.inspect}" if p.values.uniq.size != p.size
      p
    end

    def name_for_port(port, env = ENV)
      ports(env).key(port)
    end
  end
end
