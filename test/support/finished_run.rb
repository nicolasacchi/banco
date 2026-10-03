require_relative "student_ui_rows"

# A whole diagnosis run on the synthetic subject of StudentUiRows, played through the
# conductor: every number is answered with the typical error, every short answer with
# a text, the rest with "Non lo so". For the report and the teacher's pages.
module FinishedRun
  include StudentUiRows

  # Returns the run. answers: {component => raw}, anything else is "Non lo so".
  def play_run(student, subject, answers: { "number" => "99", "short_answer" => "Una risposta breve." }, clock: Diagnosis::FakeClock.new)
    run = Diagnosis::Conductor.run_for(student, subject)
    conductor = Diagnosis::Conductor.new(run, clock: clock)
    recorder = Diagnosis::AnswerRecorder.new(student: student, context: "diagnosis", clock: clock)
    40.times do
      step = conductor.step!
      break unless step.type == :item

      component = JSON.parse(ItemServed.find_by!(diagnosis_event_id: step.event.id).item_instance.item_revision.body_json).then { |b| b["kind"] == "short_answer" ? "short_answer" : b["component"] }
      raw = answers[component]
      recorder.call(served_event_id: step.event.id, client_attempt_id: SecureRandom.uuid, raw: raw || Grading::DONT_KNOW_RAW, source: raw ? "text" : "button")
      clock.advance(40)
    end
    run
  end
end
