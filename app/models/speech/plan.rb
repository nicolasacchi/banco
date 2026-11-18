module Speech
  # What a lesson revision says aloud with a server voice (D-359): the segments the render check collected (lesson/speech_segments.js, drawn in every
  # state of every card), each with its voice and key. Segments of a language with no server voice (la) have no clip; a text the service would refuse
  # for its length (MAX_CHARS) has none either, and the browser falls back to a device voice for it.
  module Plan
    MAX_CHARS = 1000

    Entry = Data.define(:lang, :text, :number, :voice, :key)

    module_function

    # The segments of the revision's latest verdict when it passed and collected them, else nil (not drawn yet, drawn before D-359, or a failed draw).
    def segments(revision)
      row = LessonRender.verdict_for(revision)
      row&.passed? ? row.segments : nil
    end

    # The clips to make, one per key, in the order the lesson says them; [] when there are no segments yet.
    def entries(revision)
      seen = {}
      Array(segments(revision)).each do |segment|
        text = segment["text"].to_s
        next if text.strip.empty? || text.size > MAX_CHARS

        number = segment["voice"].to_i.clamp(1, 1000)
        voice = Voices.voice_for(segment["lang"], number) or next
        key = Key.for(voice, text)
        seen[key] ||= Entry.new(lang: segment["lang"], text: text, number: number, voice: voice, key: key)
      end
      seen.values
    end

    # { ready:, total: } for the teacher's line (clips with a row against the clips the revision needs), or nil while its segments are not known.
    def coverage(revision)
      return nil if segments(revision).nil?

      keys = entries(revision).map(&:key)
      { ready: SpeechClip.where(key: keys).count, total: keys.size }
    end
  end
end
