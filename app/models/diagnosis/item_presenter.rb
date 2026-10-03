module Diagnosis
  # What the browser is told about one served item (X-01, X-02). Built from the
  # stored instance after serve-time re-keying: only the display the student must
  # see. The key, the error values, the solution, the id map and any verdict never
  # appear here (diagnosis_payload_test scans the JSON for them).
  #
  # Only the named parts of a stored display are copied (see +part+), so a field
  # added to displays later cannot leak by accident.
  #
  # Agent text travels as plain strings; the browser renders it escaped, with the
  # restricted markup of app/javascript/items/markup.js.
  class ItemPresenter
    ACCENT_SETS = { "spanish" => "es", "italian" => "it" }.freeze
    SHA256 = /\A[0-9a-f]{64}\z/

    def initialize(served:, number:, subject:, not_studied: false, expression_input: "mathlive")
      @served = served
      @number = number
      @subject = subject
      @not_studied = not_studied
      @expression_input = expression_input
    end

    def as_json(*)
      instance = @served.item_instance
      body = JSON.parse(instance.item_revision.body_json)
      stored = JSON.parse(instance.display_json)
      shown_order = @served.shown_order_json ? JSON.parse(@served.shown_order_json) : {}
      {
        served_event_id: @served.diagnosis_event_id,
        subject: @subject.name_it,
        number: @number,
        not_studied_button: @not_studied,
        item: item_payload(body, stored, shown_order)
      }
    end

    private

    def item_payload(body, stored, shown_order)
      if body["kind"] == "testlet"
        testlet_payload(body, stored, shown_order)
      else
        component = body["kind"] == "short_answer" ? "short_answer" : body["component"]
        part(body, component, Rekey.replay(display: stored, component: component, shown_order: shown_order))
          .merge(kind: body["kind"] == "short_answer" ? "short_answer" : "diagnosis_item")
      end
    end

    def testlet_payload(body, stored, shown_order)
      subs = Array(body["sub_items"]).map do |sub|
        display = Array(stored["sub_items"]).find { |s| s["id"] == sub["id"] }&.fetch("display", {}) || {}
        shown = Rekey.replay(display: display, component: sub["component"], shown_order: shown_order[sub["id"]] || {})
        part(sub, sub["component"], shown).merge(id: sub["id"])
      end
      { kind: "testlet", component: "testlet", passage_it: body["passage_it"], sub_items: subs }
    end

    # One answerable part: its prompt, the parts of its shown display and the
    # settings of its input. +body+ is the revision or one sub item.
    def part(body, component, display)
      prompt = body["prompt"] || {}
      out = {
        component: component,
        stem_it: prompt["stem_it"],
        instance_stem_it: display["stem_it"]
      }
      %w[table quote].each { |k| out[k.to_sym] = display[k] || prompt[k] }
      out[:figure] = figure(display["figure"] || prompt["figure"])
      %w[options elements left right].each { |k| out[k.to_sym] = display[k] if display[k] }
      out[:unit] = body["unit"] if body["unit"]
      out[:mixed] = true if component == "fraction" && Array(body["form"]).include?("mixed")
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
