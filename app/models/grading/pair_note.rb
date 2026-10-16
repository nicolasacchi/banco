module Grading
  # The words for a matching that is right but for one pair (D-301): which pair was off and what the right one is.
  # Pure; the texts come from the display of the instance or of the check ({"left" => [{id, text}], "right" => [...]}),
  # the ids from the grading's normalized (its "off_pair"). Without a text the id is said.
  #
  #   Grading::PairNote.line(display, normalized_json)
  #   # => "Giusto, tranne una coppia: «Tizio» va con «Caio», non con «Sempronio»."
  module PairNote
    LINE_IT = "Giusto, tranne una coppia: «%{left}» va con «%{key}», non con «%{given}».".freeze

    module_function

    # The off pair of a nearly_correct grading's normalized (a JSON string or a hash), or nil.
    def off_pair(normalized)
      data = normalized.is_a?(String) ? JSON.parse(normalized) : normalized
      data.is_a?(Hash) ? data["off_pair"] : nil
    rescue JSON::ParserError
      nil
    end

    def line(display, normalized)
      off = off_pair(normalized) or return nil

      display = display.to_h.transform_keys(&:to_s)
      format(LINE_IT, left: text(display["left"], off["left"]), key: text(display["right"], off["key"]),
                      given: text(display["right"], off["given"]))
    end

    def text(options, id)
      found = Array(options).find { |o| o.is_a?(Hash) && o["id"].to_s == id.to_s }
      (found && (found["text"] || found["text_it"])).presence || id.to_s
    end
  end
end
