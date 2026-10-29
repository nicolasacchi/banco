module Items
  # What the browser is told about one answerable part of an item: its prompt, the parts of its shown
  # display and the settings of its input. Shared by the diagnosis (Diagnosis::ItemPresenter) and the
  # practice pages (A9.3), so both tell the browser exactly the same things.
  #
  # Only the named parts of a stored display are copied, so a field added to displays later cannot leak
  # by accident. The key, the error values, the hints and the solution are never among them.
  class Part
    ACCENT_SETS = { "spanish" => "es", "italian" => "it" }.freeze
    SHA256 = /\A[0-9a-f]{64}\z/

    # +revision+ (an ItemRevision) is where a figure's asset is read from; without it only a display
    # that carries its own sha256 shows a picture.
    def initialize(subject:, expression_input: "mathlive", revision: nil)
      @subject = subject
      @revision = revision
      @expression_input = expression_input
    end

    # +body+ is the revision or one sub item; +display+ the shown (re-keyed) display.
    def call(body, component, display)
      prompt = body["prompt"] || {}
      out = {
        component: component,
        passage_it: body["passage_it"],
        stem_it: prompt["stem_it"],
        instance_stem_it: display["stem_it"]
      }
      %w[table quote].each { |k| out[k.to_sym] = display[k] || prompt[k] }
      out[:figure] = figure(display["figure"] || prompt["figure"])
      %w[options elements left right].each { |k| out[k.to_sym] = display[k] if display[k] }
      out[:reuse_right] = true if display["reuse_right"] == true
      out[:unit] = display["unit"] || body["unit"] if display["unit"] || body["unit"]
      out[:scientific] = true if component == "number" && Array(body["form"]).include?("scientific")
      out[:mixed] = true if component == "fraction" && Array(body["form"]).include?("mixed")
      out[:answer_format_it] = display["answer_format_it"] || body["answer_format_it"]
      out[:steps_it] = display["steps_it"] || body["steps_it"]
      out[:accents] = ACCENT_SETS[@subject.key] if component == "normalized_text"
      out[:input] = @expression_input if component == "expression"
      out.compact
    end

    # A figure is shown only as an image from /assets/items/<sha256>.svg. A display's own sha256 is
    # honoured; otherwise its asset is read from the revision's files and stored under its digest
    # (Items::Figures, D-321). A figure that cannot be shown keeps its alt text only.
    def figure(figure)
      return nil unless figure.is_a?(Hash)

      sha = figure["sha256"].to_s
      sha = Items::Figures.digest_for(figure["asset"], files).to_s unless SHA256.match?(sha)
      out = { alt_it: figure["alt_it"] }
      out[:src] = "/assets/items/#{sha}.svg" if SHA256.match?(sha)
      out
    end

    private

    def files = @files ||= @revision ? @revision.other_files : {}
  end
end
