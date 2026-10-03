ENV["RAILS_ENV"] ||= "test"
require_relative "../config/environment"
require "rails/test_help"
require "minitest/mock"
require_relative "support/contract_examples"

module ActiveSupport
  class TestCase
    parallelize(workers: :number_of_processors)

    fixtures :all

    # Temporarily set environment variables (restored after the block).
    def with_env(vars)
      saved = vars.keys.to_h { |k| [ k, ENV[k] ] }
      vars.each { |k, v| v.nil? ? ENV.delete(k) : ENV[k] = v }
      yield
    ensure
      saved.each { |k, v| v.nil? ? ENV.delete(k) : ENV[k] = v }
    end
  end
end

module ListenerHelpers
  EDGE_IP = "172.29.250.2"

  # Request on a given listener (test seam env["banco.test_listener"]).
  # Rails' integration Http::Headers maps "Remote-User" to the CGI variable
  # REMOTE_USER; a real server (Puma) delivers it as HTTP_REMOTE_USER. So the
  # Remote-* headers are put into the Rack env under their HTTP_ names here.
  def on(listener, path, method: :get, headers: {}, remote_addr: "127.0.0.1", **options)
    http_env = {}
    plain = {}
    headers.each do |name, value|
      if name.to_s.downcase.start_with?("remote-")
        http_env["HTTP_#{name.to_s.upcase.tr('-', '_')}"] = value
      else
        plain[name] = value
      end
    end
    send(method, path, headers: plain, **options,
         env: http_env.merge("banco.test_listener" => listener.to_s, "REMOTE_ADDR" => remote_addr))
  end
end

class ActionDispatch::IntegrationTest
  include ListenerHelpers
end
