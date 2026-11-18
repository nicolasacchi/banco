module Speech
  module Client
    # The Kokoro service (docs/tts.md): POST /synthesize {text, voice, lang, speed} answers 200 audio/mpeg (mono, 24 kHz source, about 64 kbps), 400 JSON
    # on bad input. No retries here: a failure raises and the job decides.
    class Http
      OPEN_TIMEOUT = 3.0
      READ_TIMEOUT = 120.0 # a long sentence on the CPU of the server

      attr_reader :url

      def initialize(url:, read_timeout: READ_TIMEOUT)
        @url = url.to_s.chomp("/")
        @read_timeout = read_timeout
      end

      def synthesize(text:, voice:, lang:, speed: 1.0)
        uri = URI.parse("#{url}/synthesize")
        request = Net::HTTP::Post.new(uri, "Content-Type" => "application/json", "Accept" => "audio/mpeg")
        request.body = JSON.generate(text: text, voice: voice, lang: lang, speed: speed)
        response = Net::HTTP.start(uri.host, uri.port, use_ssl: uri.scheme == "https", open_timeout: OPEN_TIMEOUT, read_timeout: @read_timeout,
                                   write_timeout: OPEN_TIMEOUT) { |http| http.request(request) }
        case response
        when Net::HTTPSuccess
          bytes = response.body.to_s.b
          raise Unavailable, "an empty answer" if bytes.empty?

          Result.new(bytes: bytes, duration_ms: nil)
        when Net::HTTPBadRequest
          raise Rejected, "HTTP 400: #{response.body.to_s.first(200)}"
        else
          raise Unavailable, "HTTP #{response.code}"
        end
      rescue SocketError, SystemCallError, Timeout::Error, IOError, OpenSSL::SSL::SSLError, Net::ProtocolError => e
        raise Unavailable, "#{e.class}: #{e.message.first(120)}"
      end
    end
  end
end
