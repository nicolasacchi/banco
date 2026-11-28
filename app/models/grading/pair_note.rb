module Grading
  # The words for a matching that is right but for one pair (D-301): which pair was off and what the right one is.
  # Pure; the texts come from the display of the instance or of the check ({"left" => [{id, text}], "right" => [...]}),
  # the ids from the grading's normalized (its "off_pair"). Without a text the id is said. A row's words are the ones the student reads: the item's
  # neutral `text` (the target text of a bilingual item, or a form material with no Italian beside it), a lesson's `text_en`/`text_es` (a row of a
  # `translate_material: false` check has no `text_it`), else the Italian `text_it` (round 10, D-408).
  #
  #   Grading::PairNote.line(display, normalized_json)
  #   # => "Giusto, tranne una coppia: «Tizio» va con «Caio», non con «Sempronio»." (config/locales/grading.*.yml: the page's language)
  module PairNote
    module_function

    # The off pair of a nearly_correct grading's normalized (a JSON string or a hash), or nil.
    def off_pair(normalized)
      data = normalized.is_a?(String) ? JSON.parse(normalized) : normalized
      data.is_a?(Hash) ? data["off_pair"] : nil
    rescue JSON::ParserError
      nil
    end

    TEXT_KEYS = %w[text text_en text_es text_it].freeze

    def line(display, normalized)
      off = off_pair(normalized) or return nil

      display = display.to_h.transform_keys(&:to_s)
      I18n.t("grading.pair_note", left: text(display["left"], off["left"]), key: text(display["right"], off["key"]),
                                  given: text(display["right"], off["given"]))
    end

    def text(options, id)
      found = Array(options).find { |o| o.is_a?(Hash) && o["id"].to_s == id.to_s }
      (found && TEXT_KEYS.filter_map { |k| found[k].presence }.first) || id.to_s
    end
  end
end
