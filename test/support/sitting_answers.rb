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
    when "expression" then type_expression(answer)
    when "testlet"
      all(".sub-item").each do |section|
        sub = display["sub_items"].find { |s| s["id"] == section["data-sub"] }
        pick_option(stored_text(sub["display"], answer[sub["id"]]), within: section.find("fieldset.options"))
      end
    when "short_answer" then find("textarea").set("Una risposta di prova scritta dallo studente.")
    else flunk "no way to answer #{component}"
    end
  end

  MATH_FIELD_STATE = <<~JS.freeze
    (() => { const f = document.querySelector("math-field"); return { value: f.value, mounted: f.mathVirtualKeyboardPolicy === "manual" && !!f.shadowRoot, focused: !!(f.shadowRoot && f.shadowRoot.activeElement) } })()
  JS

  # Types into the MathLive field and waits until it holds what was typed. The field is drawn once its module has loaded and is configured when the
  # item is mounted; a key sent before that, or before the click has given it the focus, is lost, and Invia would then say «Scrivi una risposta».
  def type_expression(text)
    assert_selector "math-field", wait: 30
    assert math_field_poll(30) { |state| state["mounted"] }, "the math field was not ready: #{page.evaluate_script(MATH_FIELD_STATE).inspect}"
    find("math-field").click
    page.execute_script("document.querySelector('math-field').focus()") unless math_field_poll(2) { |state| state["focused"] }
    assert math_field_poll(5) { |state| state["focused"] }, "the math field has no focus: #{page.evaluate_script(MATH_FIELD_STATE).inspect}"
    type_keys(*text.chars)
    plain = ->(latex) { latex.to_s.gsub(/\\[A-Za-z]+/, "").delete("{}\\ ") } # MathLive may wrap letters in \operatorname{..}
    assert math_field_poll(10) { |state| plain.call(state["value"]) == plain.call(text) },
           "the math field holds #{page.evaluate_script(MATH_FIELD_STATE).inspect}, not #{text.inspect}"
  end

  def math_field_poll(seconds)
    deadline = Process.clock_gettime(Process::CLOCK_MONOTONIC) + seconds
    until yield(page.evaluate_script(MATH_FIELD_STATE))
      return false if Process.clock_gettime(Process::CLOCK_MONOTONIC) > deadline

      sleep 0.05
    end
    true
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
