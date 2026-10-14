require "test_helper"
require_relative "../support/validation_servers"
require_relative "../support/chrome_helper"
require_relative "../support/lesson_render_world"

# The render check keeps its time (R4, D-249, D-255): a lesson with a large timeline, a zoom in five states and a number check on the
# dates draws every card at every viewport well inside the budget of lesson2.render, and the runner says where each card's seconds went.
# The history lesson of wave 2 once timed out on its second card in the production sidecar: the cause was the sidecar's GPU rasterization
# through SwiftShader (see docs/validation.md), not the timeline; this test keeps the timeline honest in any Chrome.
class LessonRenderTimingTest < ActiveSupport::TestCase
  include ChromeHelper
  include LessonRenderWorld

  FRONT = <<~MD
    ---
    schema: banco.lesson/2
    key: ripasso.history.render-timing
    kind: ripasso
    subject: history
    title_it: "Prova di tempo della linea"
    goals_it:
      - "**Leggere** una linea del tempo lunga"
      - "**Contare** gli anni tra due fatti"
    skills: [history.render-timing]
    refs:
      - {source: seconda-2025-26, line: 31, fragment: "la linea del tempo", role: needed_by}
      - {source: prima-2025-26, line: 21, fragment: "gli anni e i secoli", role: taught_in}
    scope: studied
    minutes: 25
    calculator: false
    why_it: "Una linea del tempo mette i fatti nell'ordine giusto. Il contenuto è inventato."
    ---
  MD

  def event(id, at, text) = "{id: #{id}, at: '#{at}', label_it: \"#{text}\", note_it: \"Una nota di prova per il fatto #{id}.\"}"

  # A line from 753 BC to 476 AD with 13 century bands and 12 facts, and a zoom of 120 years that shows 8 of them, in five states.
  def timeline_md
    whole = (1..12).map { |i| event("w#{i}", -700 + (i * 95), "Fatto lungo #{i}") }
    zoom = ->(from, to, label) {
      inside = (1..8).map { |i| event("z#{i}", from + (i * (to - from) / 10), "#{label} #{i}") }
      "  - from: '#{from}'\n    to: '#{to}'\n    op_it: \"Zoom: #{label}\"\n    periods:\n      - {from: '#{from + 5}', to: '#{to - 5}', label_it: \"#{label}\", role: senate}\n    events:\n      #{inside.map { |e| "- #{e}" }.join("\n      ")}\n"
    }
    <<~MD
      ## La linea lunga e il suo zoom {idea short="Linea" icon=hourglass}

      Prima tutta la storia, poi cinque ingrandimenti.

      ::: diagram timeline
      alt_it: "Una linea del tempo dal 753 avanti Cristo al 476 dopo Cristo con dodici fatti inventati e cinque ingrandimenti di centoventi anni."
      caption_it: "Tocca un fatto per leggere che cosa succede."
      scale: years
      from: '-753'
      to: '476'
      centuries: true
      periods:
        - {from: '-753', to: '-509', label_it: "Primo periodo"}
        - {from: '-509', to: '-27', label_it: "Secondo periodo", role: senate}
        - {from: '-27', to: '476', label_it: "Terzo periodo"}
      events:
        #{whole.map { |e| "- #{e}" }.join("\n  ")}
      states:
        - {op_it: "Tutta la storia"}
      #{zoom.call(-300, -180, 'Primo zoom')}#{zoom.call(-180, -60, 'Secondo zoom')}#{zoom.call(-70, 50, 'Terzo zoom')}#{zoom.call(60, 180, 'Quarto zoom')}#{zoom.call(180, 300, 'Quinto zoom')}:::

      ::: check number
      prompt_it: "Dal 133 a.C. al 27 a.C. quanti anni passano?"
      input_after: "anni"
      answer: '106'
      errors:
        - {answer: '160', message_it: "Hai sommato. Sono due anni a.C.: togli il numero più piccolo dal più grande."}
      explain_it: 'Sono due anni a.C.: si sottrae. $133 - 27 = 106$ anni.'
      :::
    MD
  end

  test "a large timeline with a five-state zoom renders at every viewport inside the budget, card by card" do
    require_chrome!
    shots = Dir.mktmpdir("lesson-shots")
    ENV["BANCO_LESSON_SHOTS_DIR"] = shots
    findings = Validation::Findings.new
    body = Lessons::Parser2.call(FRONT + "\n" + timeline_md, findings, allow_reserved: true).body
    assert_empty findings.errors.map(&:to_h)
    revision = store_lesson2!(body)
    started = Process.clock_gettime(Process::CLOCK_MONOTONIC)
    Validation::LessonRenderCheck.new(revision).call
    elapsed = Process.clock_gettime(Process::CLOCK_MONOTONIC) - started
    row = LessonRender.where(lesson_revision_id: revision.id).order(:id).last
    # The time is what this test is about: a label of the invented data near the edge may differ with the fonts of the machine, a timeout may not.
    render_errors = row.result["errors"].select { |e| e["code"] == "E-LESSON-RENDER" }
    assert_empty render_errors, render_errors.map { |e| "card #{e['card']} #{e['viewport']}: #{e['message']}" }.join("\n")
    assert_not_equal "error", row.status
    per_card = Validation::Rules.get(:lesson2, :render, :card_viewport_seconds)
    timings = row.result["timings"]
    assert_operator timings.size, :>=, 3 * 2, "a timing for the cover and the card at every viewport"
    slow = timings.select { |t| t["inspect"] + t["shot"] > per_card }
    assert_empty slow, "cards over #{per_card} s: #{slow.inspect}"
    assert_operator elapsed, :<, Validation::Rules.get(:lesson2, :render, :budget_seconds) / 3.0
  ensure
    ENV.delete("BANCO_LESSON_SHOTS_DIR")
    FileUtils.rm_rf(shots) if shots
  end
end
