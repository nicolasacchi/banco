module Items
  # The one reader of the text of an item that the student sees (D-402). In a bilingual revision of english or spanish each student text is a
  # pair, the target language under `<base>_en|_es` and its authored Italian under `<base>_it`; in a legacy revision the field is `<base>_it`
  # alone. Every reader of a stem, a passage, a hint, a catalogue message or a solution step goes through here, so the grader, the validators'
  # frames, the lists and the search read the TARGET layer of a bilingual item and the one text of a legacy item, without asking which it is
  # (`Lessons::Lang.pick`). The Italian layer is read only through `translation`, `both` and `pair`.
  #
  # R2 fields (an option's `text`, `final`, a table's `header`/`rows`, `quote.text`) keep the target text under the bare key and are read as
  # they are; their Italian is `<key>_it` (`option_both`, `final_both`).
  module Text
    # The two layers of a text for a reader that shows both (the teacher's pages and logs).
    SEPARATOR = " — ".freeze

    module_function

    # The text of +base+ that the target layer shows, for any hash that holds it (a prompt, a display, a body, a catalogue entry, a step).
    def pick(hash, base) = hash.is_a?(Hash) ? Lessons::Lang.pick(hash, base) : nil

    # The Italian translation of +base+ when +hash+ holds the pair; nil for a legacy field (its `_it` text IS the shown text).
    def translation(hash, base) = hash.is_a?(Hash) && Lessons::Lang.pair?(hash, base) ? hash["#{base}_it"] : nil

    # The language of the target sibling of +base+ in +hash+ ("en", "es"), nil for a legacy field.
    def lang(hash, base) = hash.is_a?(Hash) ? Lessons::Lang.sibling_lang(hash, base) : nil

    # The stem the student was shown: a prompt's or an instance display's.
    def stem(hash) = pick(hash, "stem")

    # The item's own stem (prompt.stem) and the instance's, as the target layer shows them.
    def stems(body, display) = [ stem(body.is_a?(Hash) ? body["prompt"] : nil), stem(display) ]

    def passage(hash) = pick(hash, "passage")

    def message(entry) = pick(entry, "message")

    def step(step) = pick(step, "text")

    def hints(hash) = Array(pick(hash, "hints"))

    # The served keys of the pair `base` of +hash+, under the name +as+: `{<as>_<lang>:, <as>_it:}`, or `{<as>_it:}` for a legacy field.
    # A legacy item is served exactly as it was before D-402.
    def pair(hash, base, as = base)
      lang = lang(hash, base)
      out = {}
      out[:"#{as}_#{lang}"] = hash["#{base}_#{lang}"] if lang
      out[:"#{as}_it"] = hash["#{base}_it"]
      out
    end

    # The first of +hashes+ that holds +base+ at all (an instance's own answer format before the item's), else the last.
    def holder(base, *hashes) = hashes.find { |h| !pick(h, base).nil? } || hashes.last

    # The target text and its Italian on one line, for the teacher's reading; the text alone when it has no translation or the same one.
    def both(target, italian)
      return target if italian.nil? || italian.to_s.strip.empty? || italian == target

      target.nil? ? italian : "#{target}#{SEPARATOR}#{italian}"
    end

    # `base` of +hash+ in both layers (a legacy field gives its one text).
    def both_of(hash, base) = both(pick(hash, base), translation(hash, base))

    # An option, element or row as the teacher reads it: the neutral `text` (target) and its `text_it`.
    def option_both(entry) = entry.is_a?(Hash) ? both(entry["text"], entry["text_it"]) : entry

    # A solution's `final` (target) and its `final_it`.
    def final_both(solution) = both(solution["final"], solution["final_it"])

    # The keys of a body's passage that exist: `passage_it` alone in a legacy item, `passage_<lang>` and `passage_it` in a bilingual one.
    def passage_keys(body) = body.is_a?(Hash) ? body.slice("passage_it", *Lessons::Lang::PAIR_LANGS.map { |l| "passage_#{l}" }) : {}
  end
end
