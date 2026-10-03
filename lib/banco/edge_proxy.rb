# frozen_string_literal: true

require "ipaddr"

module Banco
  # The only peer allowed to speak for users is the edge proxy (Traefik), a
  # single address on the dedicated banco-edge network (D-02).
  module EdgeProxy
    # IPAddr that matches nothing: Rails treats an empty trusted_proxies list as
    # "use the defaults" (all private ranges), so "trust nobody" needs a value.
    NOBODY = IPAddr.new("0.0.0.0/32")

    module_function

    def cidr(env = ENV)
      value = env["BANCO_EDGE_PROXY"].to_s.strip
      value.empty? ? nil : IPAddr.new(value)
    end

    def trusted_proxies(env = ENV)
      [ cidr(env) || NOBODY ]
    end

    def include?(remote_addr, env = ENV)
      net = cidr(env)
      return false unless net && remote_addr
      net.include?(IPAddr.new(remote_addr))
    rescue IPAddr::Error
      false
    end

    def teacher_users(env = ENV)
      env["BANCO_TEACHER_USERS"].to_s.split(",").map(&:strip).reject(&:empty?)
    end
  end
end
