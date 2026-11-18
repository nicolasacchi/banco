require "net/http"

module Speech
  # The TTS service's client (D-359, docs/tts.md): one place decides whether clips are made at all.
  #
  #   Speech::Client.current      # => Http (BANCO_TTS_URL set), Stub (config.x.speech.client = :stub) or nil
  #   Speech::Client.configured?  # => true when there is one
  #
  # nil means nothing is generated: the lessons then speak with an accepted device voice, or not at all. Only SpeakLessonRevisionJob and the
  # backfill use it, never a request (firm rule 1: the text is what the teacher approved, made once ahead of time).
  #
  # A client answers `synthesize(text:, voice:, lang:, speed:)` with a Result (MP3 bytes, duration in ms when known). A service that cannot answer
  # (down, slow, a 5xx) raises Unavailable: the caller tries again later. A service that refuses the input (400: an unknown voice, an empty or too long
  # text, a language that does not match the voice) raises Rejected: the same input is refused again, the caller leaves it.
  module Client
    class Unavailable < StandardError; end
    class Rejected < StandardError; end

    Result = Struct.new(:bytes, :duration_ms, keyword_init: true)

    @forced = false
    @client = nil
    @http = nil
    @stub = nil

    class << self
      def current
        return @client if @forced
        return nil if Rails.configuration.x.speech.client == :none
        return (@stub ||= Stub.new) if Rails.configuration.x.speech.client == :stub

        url = ENV["BANCO_TTS_URL"].to_s.strip
        return nil if url.empty?

        @http = nil if @http && @http.url != url.chomp("/")
        @http ||= Http.new(url: url)
      end

      def configured? = !current.nil?

      # Tests: use +client+ (or none, with nil) inside the block.
      def using(client)
        previous = [ @forced, @client ]
        @forced = true
        @client = client
        yield
      ensure
        @forced, @client = previous
      end
    end
  end
end
