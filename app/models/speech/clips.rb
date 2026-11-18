module Speech
  # The files of the clips: storage/speech_clips/<key[0,2]>/<key>.mp3 (BANCO_SPEECH_CLIPS_DIR overrides, for tests), written once and never
  # changed (the name is the content's recipe). The append-only `speech_clips` rows say what each file is; a purged file is made again.
  module Clips
    module_function

    def dir
      ENV["BANCO_SPEECH_CLIPS_DIR"].presence || Rails.root.join("storage/speech_clips").to_s
    end

    # nil for anything that is not a key, so a request's text never builds a path.
    def path(key)
      return nil unless Key.valid?(key)

      File.join(dir, key[0, 2], "#{key}.#{Voices.format}")
    end

    def exist?(key)
      file = path(key)
      !file.nil? && File.file?(file)
    end

    # Stores the bytes under the key (atomically: a reader never meets half a file).
    def put(key, bytes)
      file = path(key) or raise ArgumentError, "not a clip key"
      FileUtils.mkdir_p(File.dirname(file))
      tmp = "#{file}.#{Process.pid}.#{SecureRandom.hex(4)}.tmp"
      File.binwrite(tmp, bytes)
      File.rename(tmp, file)
      file
    end
  end
end
