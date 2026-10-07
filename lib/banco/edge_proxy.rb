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

    def teacher_users(env = ENV) = list(env["BANCO_TEACHER_USERS"])

    def guest_users(env = ENV) = list(env["BANCO_GUEST_USERS"])

    # BANCO_STUDENT_USERS: "login=student_key,login=student_key". The key "student" is the official
    # student, any other key a trial student (D-217). A pair that is malformed, a key that is not
    # [a-z0-9-]+ and the reserved key "preview" are ignored. Empty when unset: then any
    # banco-student login is the official student, as before.
    def student_map(env = ENV)
      list(env["BANCO_STUDENT_USERS"]).each_with_object({}) do |pair, map|
        login, key = pair.split("=", 2).map { |part| part.to_s.strip }
        next if login.to_s.empty? || key.to_s.empty? || !key.match?(/\A[a-z0-9-]+\z/) || key == "preview"

        map[login] = key
      end
    end

    # Where "Esci" goes, or nil (the link is hidden).
    def logout_url(env = ENV)
      url = env["BANCO_LOGOUT_URL"].to_s.strip
      url.match?(%r{\Ahttps?://\S+\z}) ? url : nil
    end

    def list(value) = value.to_s.split(",").map(&:strip).reject(&:empty?)
  end
end
