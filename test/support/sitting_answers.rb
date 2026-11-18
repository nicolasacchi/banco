# The right answer to the item on screen in a sitting, for any component: the test needs `run_row` (the student's run).
# Shared by the system tests that play a subject to its end (diagnosis_subject_test, back_navigation_sitting_test).
module SittingAnswers
  def current_event = run_row.events.where(kind: "item_served").order(:seq).last

  def stored_text(display, id)
    %w[options elements left right].flat_map { |k| Array(display[k]) }.find { |e| e["id"] == id }["text"]
  end

  # Fills in the item on screen with its right answer and sends it; returns the component.
  def answer_correctly
    event = current_event
    served = ItemServed.find_by!(diagnosis_event_id: event.id)
    instance = served.item_instance
    body = JSON.parse(instance.item_revision.body_json)
    display = JSON.parse(instance.display_json)
    answer = JSON.parse(instance.answer_json)
    component = body["kind"] == "testlet" ? "testlet" : body["kind"] == "short_answer" ? "short_answer" : body["component"]
    assert_selector "[data-sitting-target=itemBox] .item-body .answer"
    fill_component(component, display, answer)
    click_button "Invia"
    component
  end

  def fill_component(component, display, answer)
    case component
    when "number" then find("input[inputmode=decimal]").set(answer)
    when "fraction"
      all(".fraction input")[0].set(answer["n"].to_s)
      all(".fraction input")[1].set(answer["d"].to_s)
    when "choice" then pick_option(stored_text(display, answer), within: find("fieldset.options"))
    when "ordering" then order_rows(answer.map { |id| stored_text(display, id) })
    when "matching"
      all(".match-row").each do |row|
        left_text = row.find("label").text
        left_id = display["left"].find { |l| l["text"] == left_text }["id"]
        row.find("select").select(stored_text(display, answer[left_id]))
      end
    when "normalized_text" then find("input[type=text][lang]").set(answer)
    when "expression"
      find("math-field").click
      type_keys(*answer.chars)
    when "testlet"
      all(".sub-item").each do |section|
        sub = display["sub_items"].find { |s| s["id"] == section["data-sub"] }
        pick_option(stored_text(sub["display"], answer[sub["id"]]), within: section.find("fieldset.options"))
      end
    when "short_answer" then find("textarea").set("Una risposta di prova scritta dallo studente.")
    else flunk "no way to answer #{component}"
    end
  end

  def pick_option(text, within:)
    within.find(".option-text", text: text, exact_text: true).click
  end

  def order_rows(texts)
    texts.each_with_index do |text, target|
      loop do
        shown = all("ol.ordering .row-text").map(&:text)
        position = shown.index(text)
        break if position <= target

        all("ol.ordering li")[position].click_button("Su")
      end
    end
  end
end
