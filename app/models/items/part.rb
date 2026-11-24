module Items
  # What the browser is told about one answerable part of an item: its prompt, the parts of its shown
  # display and the settings of its input. Shared by the diagnosis (Diagnosis::ItemPresenter) and the
  # practice pages (A9.3), so both tell the browser exactly the same things.
  #
  # Only the named parts of a stored display are copied, so a field added to displays later cannot leak
  # by accident. The key, the error values, the hints and the solution are never among them.
  #
  # D-402: a bilingual revision of english or spanish is served with both layers of each text, the target one under `<base>_<lang>` and its
  # Italian under `<base>_it`, and with `lang`; a legacy revision is served exactly as before (no `lang`, no sibling). The passage of a bilingual
  # item is a comprehension text: its Italian is NOT served here (the student would answer from it), only with `after_answer: true`, for the
  # readers that have the answer already (the teacher's log); the replies after an answer carry it through Practice::Payload.
  class Part
    ACCENT_SETS = { "spanish" => "es", "italian" => "it" }.freeze
    SHA256 = /\A[0-9a-f]{64}\z/

    # +revision+ (an ItemRevision) is where a figure's asset is read from; without it only a display
    # that carries its own sha256 shows a picture.
    def initialize(subject:, expression_input: "mathlive", revision: nil, after_answer: false)
      @subject = subject
      @after_answer = after_answer
      @revision = revision
      @expression_input = expression_input
    end

    # +body+ is the revision or one sub item; +display+ the shown (re-keyed) display. +answer+ and +accept+ (the key and the accepted forms of this
    # instance) are read for one fact only, whether the answer is always a whole number (`integer`, D-335); they are never served.
    def call(body, component, display, answer: nil, accept: [])
      prompt = body["prompt"] || {}
      out = { component: component }
      lang = lang_of(body, prompt, display)
      out[:lang] = lang if lang
      out.merge!(passage(body, display))
      out.merge!(Items::Text.pair(prompt, "stem"))
      out.merge!(Items::Text.pair(display, "stem", "instance_stem"))
      out.delete(:instance_stem_it) if Items::Text.material_off?(body) # the sentence with its blank is form material: target only
      out.merge!(Items::Text.pair(display, "task")) # the instance's own task line (a pair), drawn above its sentence: the one line of Italian that a material instance has
      %w[table quote].each { |k| out[k.to_sym] = display[k] || prompt[k] }
      out[:figure] = figure(display["figure"] || prompt["figure"])
      %w[options elements left right].each { |k| out[k.to_sym] = Items::Text.shown_entries(display[k], body) if display[k] }
      out[:reuse_right] = true if display["reuse_right"] == true
      out[:unit] = display["unit"] || body["unit"] if display["unit"] || body["unit"]
      out[:scientific] = true if component == "number" && Array(body["form"]).include?("scientific")
      # a whole-number key (and every accepted form whole): the box does not tell about decimals. A boolean about the key's kind, never the key.
      out[:integer] = true if component == "number" && !out[:scientific] && whole?(answer) && Array(accept).all? { |v| whole?(v) }
      out[:mixed] = true if component == "fraction" && Array(body["form"]).include?("mixed")
      out.merge!(Items::Text.pair(Items::Text.holder("answer_format", display, body), "answer_format"))
      out.merge!(Items::Text.pair(Items::Text.holder("steps", display, body), "steps"))
      out[:accents] = ACCENT_SETS[@subject.key] if component == "normalized_text"
      out[:input] = @expression_input if component == "expression"
      out.compact
    end

    # The passage of an instance (D-402): its own `display.passage_*` when it has one (a reading text per instance, three to five questions on each), else
    # the item's. `passage_it` alone for a legacy item; for a bilingual one `passage_<lang>` only, and `passage_it` with it when the reader asked for the
    # after-answer layer. {} when there is none.
    def passage(body, display = {})
      holder = Items::Text.holder("passage", display, body)
      lang = Items::Text.lang(holder, "passage")
      return { passage_it: holder["passage_it"] }.compact unless lang

      out = { "passage_#{lang}": holder["passage_#{lang}"] }
      out[:passage_it] = holder["passage_it"] if @after_answer
      out.compact
    end

    # A figure is shown only as an image from /assets/items/<sha256>.svg. A display's own sha256 is
    # honoured; otherwise its asset is read from the revision's files and stored under its digest
    # (Items::Figures, D-321). A figure that cannot be shown keeps its alt text only.
    def figure(figure)
      return nil unless figure.is_a?(Hash)

      sha = figure["sha256"].to_s
      sha = "" unless SHA256.match?(sha) && Items::Figures.stored?(sha)
      sha = Items::Figures.digest_for(figure["asset"], files).to_s if sha.empty?
      out = Items::Text.pair(figure, "alt")
      out[:src] = "/assets/items/#{sha}.svg" if SHA256.match?(sha)
      out
    end

    # A key that is a whole number as the grader reads one: digits with an optional minus (the ASCII hyphen or U+2212).
    def self.whole?(value) = value.is_a?(String) || value.is_a?(Integer) ? value.to_s.strip.match?(/\A[-\u2212]?\d+\z/) : false

    # The forms an instance's number key is also accepted in: the item's own and the instance's.
    def self.accepted(body, instance_accept) = Array(body["accept"]) + Array(instance_accept)

    private

    def whole?(value) = self.class.whole?(value)

    # The language of the siblings of the texts served (nil for a legacy item): the first text of the part that has one.
    def lang_of(body, prompt, display)
      Items::Text.lang(prompt, "stem") || Items::Text.lang(display, "stem") || Items::Text.lang(display, "task") || Items::Text.lang(Items::Text.holder("passage", display, body), "passage") ||
        Items::Text.lang(Items::Text.holder("answer_format", display, body), "answer_format") || Items::Text.lang(Items::Text.holder("steps", display, body), "steps")
    end

    def files = @files ||= @revision ? @revision.other_files : {}
  end
end
