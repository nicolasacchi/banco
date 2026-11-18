module Speech
  module Client
    # A deterministic stand-in for tests, development and CI (config.x.speech.client = :stub, BANCO_TTS_STUB=1): the "MP3" is a tag and the request,
    # so two voices or two texts never share bytes. It remembers what it was asked (`calls`) and refuses what the service refuses: an empty or too
    # long text, a voice the engine does not have, a language that does not match the voice. `down` makes it raise Unavailable for the texts
    # it answers true for (`down: ->(text) { ... }`), or for every text with `down: true`.
    class Stub
      MAX_CHARS = 1000

      attr_reader :calls

      def initialize(down: nil)
        @down = down
        @calls = []
        @mutex = Mutex.new
      end

      def synthesize(text:, voice:, lang:, speed: 1.0)
        @mutex.synchronize { @calls << { text: text, voice: voice, lang: lang, speed: speed } }
        raise Rejected, "empty text" if text.to_s.strip.empty?
        raise Rejected, "text longer than #{MAX_CHARS} characters" if text.to_s.size > MAX_CHARS
        raise Rejected, "unknown voice #{voice}" unless Voices.language_of(voice)
        raise Rejected, "voice #{voice} does not speak #{lang}" unless Voices.language_of(voice) == lang
        raise Unavailable, "the stub service is down" if @down == true || (@down.respond_to?(:call) && @down.call(text))

        bytes = "ID3stub|#{voice}|#{lang}|#{speed}|#{text}".b
        Result.new(bytes: bytes, duration_ms: 40 * text.to_s.size)
      end
    end
  end
end
