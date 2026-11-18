module Speech
  # The name of a clip (D-359): the lowercase hex SHA-256 of the UTF-8 string "<engine>|<voice name>|<text>". The browser computes the same
  # (lesson/speech_clips.js) and asks for <clip_path>/<key>.mp3; test/fixtures/speech/keys.json holds the vectors both sides must agree on.
  module Key
    PATTERN = /\A[0-9a-f]{64}\z/

    module_function

    def for(voice, text, engine: Voices.engine)
      Digest::SHA256.hexdigest("#{engine}|#{voice}|#{text}".encode(Encoding::UTF_8))
    end

    def valid?(key) = key.to_s.match?(PATTERN)

    # Where the browser asks for a clip.
    def url(key, path: Voices.clip_path, format: Voices.format) = "#{path}/#{key}.#{format}"
  end
end
