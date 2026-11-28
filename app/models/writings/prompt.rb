module Writings
  # The task of a writing item as the student reads it (D-407, D-410): what «Scrivi tu» on the topic page and the item's shot draw, from the one reader.
  # stem and format are the language he studies when the item has the pair, else Italian; stem_tr and format_tr their Italian when it is a translation to
  # offer (the «Traduzione» button), nil otherwise. The format is the item's `answer_format_*`, the advice on how to write (tenses, connectives, register),
  # which the rubric grades and so he is told; nil when the item has none. `lang` / `format_lang` is the language of the text drawn (nil for Italian).
  #
  #   Writings::Prompt.of(body, "en")   # body: the parsed item revision; the language the subject teaches, or nil
  Prompt = Data.define(:stem, :stem_tr, :lang, :format, :format_tr, :format_lang, :words_min, :words_max) do
    def self.of(body, lang)
      prompt = body["prompt"] || {}
      stem = lang && prompt["stem_#{lang}"].presence
      format = lang && body["answer_format_#{lang}"].presence
      format_it = body["answer_format_it"].presence
      new(stem: stem || prompt["stem_it"].to_s, stem_tr: (prompt["stem_it"].presence if stem), lang: (lang if stem),
          format: format || format_it, format_tr: (format_it if format), format_lang: (lang if format),
          words_min: body["words_min"], words_max: body["words_max"])
    end

    # Whether the page has an Italian translation to offer for this task.
    def translations? = !(stem_tr || format_tr).nil?
  end
end
