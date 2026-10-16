module Teacher
  # The texts the student typed that were refused as unreadable (D-298), kept in the app events
  # `invalid_input` (diagnosis, by served_event_id) and `practice_invalid_input` (by serve_id). Only the
  # teacher's pages read them, like the answers themselves (operator Q8): the agent API never does.
  module RefusedTries
    Try = Data.define(:text, :count)

    module_function

    # {served_event_id => [text, ...]} in the order they were typed.
    def diagnosis(student, served_event_ids)
      group("invalid_input", "served_event_id", student, served_event_ids)
    end

    # {serve_id => [[text, at], ...]} in the order they were typed.
    def practice(student, serve_ids)
      group("practice_invalid_input", "serve_id", student, serve_ids, with_time: true)
    end

    # Deduplicated, in the order of the first time each text was typed, with how many times.
    def collapse(texts)
      texts.tally.map { |text, count| Try.new(text, count) }
    end

    def group(kind, key, student, ids, with_time: false)
      wanted = ids.to_set
      return {} if wanted.empty? || student.nil?

      AppEvent.where(kind: kind, student_id: student.id).order(:id).each_with_object(Hash.new { |h, k| h[k] = [] }) do |event, out|
        payload = JSON.parse(event.payload_json.to_s)
        text = payload["text"]
        next unless text.is_a?(String) && wanted.include?(payload[key])

        out[payload[key]] << (with_time ? [ text, event.created_at ] : text)
      end
    end
  end
end
