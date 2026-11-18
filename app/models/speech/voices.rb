module Speech
  # The server voices of config/banco/voices.yml (`server:`, D-359): which engine makes the clips, which voices each language has, where the
  # browser asks for them. The browser reads the same block from the generated lesson/voices.js (bin/build-lesson-types).
  module Voices
    FILE = Rails.root.join("config/banco/voices.yml")

    module_function

    def config = @config ||= YAML.safe_load_file(FILE).fetch("server").freeze

    def engine = config.fetch("engine")
    def clip_path = config.fetch("clip_path")
    def format = config.fetch("format")

    # The voices of a language in order, [] when the server has none (la).
    def for_language(lang) = Array(config.fetch("voices")[lang.to_s])

    # The server voice of a segment of +lang+ spoken by speaker +number+ (1 when none): the list is used round and round, so speaker 1 is the first
    # voice, speaker 2 the second, speaker 3 the first again. nil for a language with no server voice.
    def voice_for(lang, number = 1)
      list = for_language(lang)
      return nil if list.empty?

      list[(number.to_i.clamp(1, 1000) - 1) % list.size]
    end

    # The language a voice name belongs to, or nil.
    def language_of(voice) = config.fetch("voices").find { |_lang, list| list.include?(voice) }&.first
  end
end
