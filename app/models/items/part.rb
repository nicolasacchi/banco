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

    def initialize(subject:, expression_input: "mathlive")
      @subject = subject
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

    # Only a figure that the validation stored by digest can be shown, and only as
    # an image from /assets/items/<sha256>.svg.
    def figure(figure)
      return nil unless figure.is_a?(Hash)

      sha = figure["sha256"].to_s
      out = { alt_it: figure["alt_it"] }
      out[:src] = "/assets/items/#{sha}.svg" if SHA256.match?(sha)
      out
    end
  end
end
