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
    # [a-z0-9-]+ and the reserved keys "preview" and "all" are left out of the map, and student_map_problems
    # names their positions. Fails closed (D-219): once the variable is set and not blank the map
    # counts as configured, whatever is left in it. Only an unset or blank variable gives the old
    # fallback: any banco-student login is the official student.
    def student_map(env = ENV)
      parsed_student_pairs(env).each_with_object({}) do |(login, key, _position), map|
        map[login] = key if valid_student_pair?(login, key)
      end
    end

    def student_map_configured?(env = ENV) = !env["BANCO_STUDENT_USERS"].to_s.strip.empty?

    # 1-based positions (in the comma separated list) of the pairs that were left out. Positions only:
    # nothing from the value is echoed.
    def student_map_problems(env = ENV)
      parsed_student_pairs(env).filter_map { |login, key, position| position unless valid_student_pair?(login, key) }
    end

    # Where "Esci" goes, or nil (the link is hidden).
    def logout_url(env = ENV)
      url = env["BANCO_LOGOUT_URL"].to_s.strip
      url.match?(%r{\Ahttps?://\S+\z}) ? url : nil
    end

    def list(value) = value.to_s.split(",").map(&:strip).reject(&:empty?)

    # Helpers of student_map (public only because of module_function).
    def parsed_student_pairs(env)
      env["BANCO_STUDENT_USERS"].to_s.split(",").map(&:strip).reject(&:empty?).each_with_index.map do |pair, i|
        login, key = pair.split("=", 2).map { |part| part.to_s.strip }
        [ login, key, i + 1 ]
      end
    end

    def valid_student_pair?(login, key)
      !login.to_s.empty? && !key.to_s.empty? && key.match?(Student::KEY_FORMAT) && key != Student::PREVIEW_KEY && key != "all"
    end
  end
end
