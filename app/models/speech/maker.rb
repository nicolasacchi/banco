module Speech
  # Makes the clip of one Plan::Entry (D-359): asks the service for it unless the file is already stored, stores the file and appends its
  # `speech_clips` row. Idempotent: a clip that exists costs nothing, a file stored without its row (a crash between the two) gets the row, a row whose
  # file was purged gets the file again. Raises Client::Unavailable (try later) or Client::Rejected (the service will not make this one).
  module Maker
    # Failures in a row that mean the service is down, not that one text is a problem.
    DOWN_AFTER = 3

    module_function

    # Makes every entry, one failing not stopping the others, and logs what was done under +label+. A clip the service refuses is logged and left;
    # a service that is down (DOWN_AFTER failures in a row) ends the run early. Raises the last Client::Unavailable at the end when any clip
    # could not be made for that reason, so the caller's job is tried again later (what is made is skipped then). Answers { made:, present:, refused: }.
    def all(entries, client, label:)
      made = present = refused = 0
      unavailable = nil
      streak = 0
      entries.each do |entry|
        call(entry, client) == :made ? made += 1 : present += 1
        streak = 0
      rescue Client::Unavailable => e
        unavailable = e
        streak += 1
        break if streak >= DOWN_AFTER # the rest would only wait for timeouts
      rescue Client::Rejected => e
        refused += 1
        Rails.logger.warn("speech: the service refused a clip of #{label} (#{entry.voice}, #{entry.text.size} characters): #{e.message.first(160)}")
      end
      Rails.logger.info("speech: #{label}: #{made} clips made, #{present} already there, #{refused} refused, #{entries.size} in all")
      raise unavailable if unavailable

      { made: made, present: present, refused: refused }
    end

    # :present when nothing was asked of the service, :made otherwise.
    def call(entry, client)
      if Clips.exist?(entry.key)
        append(entry, File.size(Clips.path(entry.key)), nil) unless SpeechClip.exists?(key: entry.key)
        return :present
      end

      result = client.synthesize(text: entry.text, voice: entry.voice, lang: entry.lang, speed: 1.0)
      Clips.put(entry.key, result.bytes)
      append(entry, result.bytes.bytesize, result.duration_ms) unless SpeechClip.exists?(key: entry.key)
      :made
    end

    def append(entry, bytes, duration_ms)
      SpeechClip.create!(key: entry.key, engine: Voices.engine, voice: entry.voice, lang: entry.lang, bytes: bytes, duration_ms: duration_ms)
    rescue ActiveRecord::RecordNotUnique
      nil # another job made it at the same time
    end
  end
end
