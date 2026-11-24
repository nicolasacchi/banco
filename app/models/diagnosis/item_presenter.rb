module Diagnosis
  # What the browser is told about one served item (X-01, X-02). Built from the
  # stored instance after serve-time re-keying: only the display the student must
  # see. The key, the error values, the solution, the id map and any verdict never
  # appear here (diagnosis_payload_test scans the JSON for them).
  #
  # Only the named parts of a stored display are copied (see +part+), so a field
  # added to displays later cannot leak by accident.
  #
  # D-402: a bilingual item carries both layers of each text (Items::Part); the entry test is not served bilingual by default, the presenter supports it.
  #
  # Agent text travels as plain strings; the browser renders it escaped, with the
  # restricted markup of app/javascript/items/markup.js.
  class ItemPresenter
    # after_answer: the reader is the teacher (the frozen slot, the log) and not the student: a bilingual passage carries its Italian too (Items::Part).
    def initialize(served:, number:, subject:, not_studied: false, expression_input: "mathlive", formula_sheet_it: nil, after_answer: false)
      @served = served
      @number = number
      @subject = subject
      @not_studied = not_studied
      @expression_input = expression_input
      @formula_sheet_it = formula_sheet_it
      @after_answer = after_answer
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
        part(body, component, Rekey.replay(display: stored, component: component, shown_order: shown_order),
             answer: JSON.parse(@served.item_instance.answer_json), accept: Items::Part.accepted(body, own_accept))
          .merge(kind: body["kind"] == "short_answer" ? "short_answer" : "diagnosis_item")
      end
    end

    def testlet_payload(body, stored, shown_order)
      subs = Array(body["sub_items"]).map do |sub|
        display = Array(stored["sub_items"]).find { |s| s["id"] == sub["id"] }&.fetch("display", {}) || {}
        shown = Rekey.replay(display: display, component: sub["component"], shown_order: shown_order[sub["id"]] || {})
        answers = JSON.parse(@served.item_instance.answer_json)
        part(Items::Text.inherit_material(body, sub), sub["component"], shown, answer: answers.is_a?(Hash) ? answers[sub["id"]] : nil, accept: Items::Part.accepted(sub, nil)).merge(id: sub["id"])
      end
      # the passage of a bilingual testlet is served in its target language only: its Italian would be the text the sub items are answered from
      lang = Items::Text.lang(body, "passage")
      { kind: "testlet", component: "testlet", **(lang ? { lang: lang } : {}), **parts.passage(body), sub_items: subs }
    end

    def part(body, component, display, answer: nil, accept: []) = parts.call(body, component, display, answer: answer, accept: accept)

    def own_accept = (raw = @served.item_instance.accept_json).present? ? JSON.parse(raw) : []

    def figure(figure) = parts.figure(figure)

    def parts = @parts ||= Items::Part.new(subject: @subject, expression_input: @expression_input, after_answer: @after_answer,
                                           revision: @served&.item_instance&.item_revision)
  end
end
