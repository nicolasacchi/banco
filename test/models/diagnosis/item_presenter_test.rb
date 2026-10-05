require "test_helper"
require_relative "../../support/student_ui_rows"

# What the browser is told about a served item: only what the student must see.
class DiagnosisItemPresenterTest < ActiveSupport::TestCase
  include StudentUiRows

  setup do
    @rows = build_ui_subject(components: %w[number normalized_text expression])
    @run = Diagnosis::Conductor.run_for(@rows[:student], @rows[:subject])
    @conductor = Diagnosis::Conductor.new(@run)
  end

  def served_payload(skill_suffix)
    loop do
      step = @conductor.step!
      raise "item not reached" unless step.type == :item

      payload = @conductor.presentation(step.event, student: @rows[:student])
      return payload if ItemServed.find_by!(diagnosis_event_id: step.event.id).skill_key.end_with?(skill_suffix)

      Diagnosis::AnswerRecorder.new(student: @rows[:student], context: "diagnosis")
                               .call(served_event_id: step.event.id, client_attempt_id: SecureRandom.uuid, raw: Grading::DONT_KNOW_RAW, source: "button")
    end
  end

  test "a number carries its prompt and unit and nothing of the key" do
    item = served_payload("number")[:item]
    assert_equal "number", item[:component]
    assert_equal "Calcola e scrivi il risultato.", item[:stem_it]
    assert_equal "cm", item[:unit]
    assert_match(/\A\$\d\+4\$\z/, item[:instance_stem_it])
    assert_equal %i[component instance_stem_it kind stem_it unit], item.keys.sort
  end

  test "an instance display unit wins over the item unit (D-103)" do
    presenter = Diagnosis::ItemPresenter.allocate
    out = presenter.send(:part, { "unit" => "g" }, "number", { "unit" => "mg" })
    assert_equal "mg", out[:unit]
    assert_equal "g", presenter.send(:part, { "unit" => "g" }, "number", {})[:unit]
  end

  test "a short answer is served with its passage and without its model answer" do
    rows = build_ui_subject(key: "italian", name: "Italiano", position: 7, components: %w[short_answer])
    conductor = Diagnosis::Conductor.new(Diagnosis::Conductor.run_for(rows[:student], rows[:subject]))
    step = conductor.step!
    item = conductor.presentation(step.event, student: rows[:student])[:item]
    assert_equal "Un breve testo da riassumere.", item[:passage_it]
    refute_match(/Una risposta\./, item.to_json)
  end

  test "the accent buttons depend on the subject, and the expression input on the warm-up" do
    assert_nil served_payload("normalized-text")[:item][:accents]
    assert_equal "mathlive", served_payload("expression")[:item][:input]
  end

  test "after a failed editor warm-up the expression item asks for a text box" do
    AppEvent.create!(kind: "warmup_editor_fallback", student: @rows[:student], payload_json: "{}")
    assert_equal "text", served_payload("expression")[:item][:input]
  end

  test "Spanish and Italian items offer their accented letters" do
    { "spanish" => "es", "italian" => "it" }.each_with_index do |(key, accents), i|
      rows = build_ui_subject(key: key, name: key.capitalize, position: 10 + i, components: %w[normalized_text])
      run = Diagnosis::Conductor.run_for(rows[:student], rows[:subject])
      conductor = Diagnosis::Conductor.new(run)
      step = conductor.step!
      assert_equal accents, conductor.presentation(step.event, student: rows[:student])[:item][:accents]
    end
  end

  test "skills still being studied get the other button" do
    graph = SkillGraphRevision.find(@rows[:blueprint].skill_graph_revision_id)
    body = JSON.parse(graph.body_json)
    body["skills"].each { |s| s["scope"] = "in_progress" if s["key"] == "math.number" }
    graph2 = SkillGraphRevision.create!(subject: @rows[:subject], seq: 2, body_json: body.to_json, author_session: graph.author_session)
    blueprint = BlueprintRevision.create!(subject: @rows[:subject], skill_graph_revision: graph2, seq: 2, body_json: @rows[:blueprint].body_json,
                                          author_session: graph.author_session)
    run = Diagnosis::Conductor.fresh_run(@rows[:preview], @rows[:subject])
    assert_equal blueprint, run.blueprint_revision
    conductor = Diagnosis::Conductor.new(run)
    payload = conductor.presentation(conductor.step!.event, student: @rows[:preview])
    assert payload[:not_studied_button]
    refute served_payload("number")[:not_studied_button]
  end

  test "a figure is only an image from its digest, and only when the digest is valid" do
    sha = Digest::SHA256.hexdigest("<svg/>")
    presenter = Diagnosis::ItemPresenter.allocate
    assert_equal({ alt_it: "Un disegno", src: "/assets/items/#{sha}.svg" }, presenter.send(:figure, { "sha256" => sha, "alt_it" => "Un disegno", "asset" => "assets/a.svg" }))
    assert_equal({ alt_it: "Un disegno" }, presenter.send(:figure, { "sha256" => "../../etc/passwd", "alt_it" => "Un disegno" }))
    assert_equal({ alt_it: "x" }, presenter.send(:figure, { "alt_it" => "x", "asset" => "assets/a.svg" }))
    assert_nil presenter.send(:figure, nil)
  end
end
