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
    def initialize(served:, number:, subject:, not_studied: false, expression_input: "mathlive", formula_sheet_it: nil)
      @served = served
      @number = number
      @subject = subject
      @not_studied = not_studied
      @expression_input = expression_input
      @formula_sheet_it = formula_sheet_it
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
        formula_sheet_it: @formula_sheet_it,
        item: item_payload(body, stored, shown_order)
      }.compact
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

    def part(body, component, display) = parts.call(body, component, display)

    def figure(figure) = parts.figure(figure)

    def parts = @parts ||= Items::Part.new(subject: @subject, expression_input: @expression_input)
  end
end
