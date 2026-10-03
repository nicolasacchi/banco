# Test-only: stands in for the edge proxy when the student's Authelia session has
# lapsed (or the network drops). While SessionExpiry.mode is set, a POST to
# .../answers is answered the way the real world would answer it, and never reaches
# the application. Off (nil) by default; loaded by config/environments/test.rb only.
#
#   :redirect      302 to the login page (what Authelia sends; fetch with
#                  redirect "manual" sees an opaque redirect)
#   :html          200 with the login page as HTML
#   :unauthorized  401
#   :lose_reply    the application records the answer, the reply is replaced by a 503
#                  (an answer that arrived but whose reply was lost)
module SessionExpiry
  class << self
    attr_accessor :mode
    attr_reader :hits

    def reset!
      @mode = nil
      @hits = 0
    end

    def hit! = @hits = hits.to_i + 1
  end

  class Middleware
    def initialize(app)
      @app = app
    end

    def call(env)
      mode = SessionExpiry.mode
      return @app.call(env) unless mode && env["REQUEST_METHOD"] == "POST" && env["PATH_INFO"].end_with?("/answers")

      SessionExpiry.hit!
      case mode
      when :redirect then [ 302, { "location" => "/signin-expired", "content-type" => "text/html" }, [ "" ] ]
      when :html then [ 200, { "content-type" => "text/html" }, [ "<html><body><h1>Sign in</h1></body></html>" ] ]
      when :unauthorized then [ 401, { "content-type" => "text/plain" }, [ "Unauthorized" ] ]
      when :lose_reply
        @app.call(env)
        [ 503, { "content-type" => "text/plain" }, [ "Service unavailable" ] ]
      end
    end
  end
end
