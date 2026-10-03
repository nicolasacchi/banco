require "test_helper"
require_relative "../../support/student_ui_rows"

# The web side of a run: what is appended for each engine action, with a clock that
# moves only when told to.
class DiagnosisConductorTest < ActiveSupport::TestCase
  include StudentUiRows

  setup do
    @rows = build_ui_subject(components: %w[number choice ordering])
    @clock = Diagnosis::FakeClock.new
    @run = Diagnosis::Conductor.run_for(@rows[:student], @rows[:subject])
    @conductor = Diagnosis::Conductor.new(@run, clock: @clock)
    @recorder = Diagnosis::AnswerRecorder.new(student: @rows[:student], context: "diagnosis", clock: @clock)
  end

  def kinds = @run.events.order(:seq).pluck(:kind)

  def answer(step, raw: Grading::DONT_KNOW_RAW, source: "button")
    @recorder.call(served_event_id: step.event.id, client_attempt_id: SecureRandom.uuid, raw: raw, source: source)
  end

  test "the first step starts an unsupervised sitting and serves an item with its shuffle logged" do
    step = @conductor.step!
    assert_equal :item, step.type
    assert_equal %w[sitting_started item_served], kinds
    assert_equal "unsupervised", JSON.parse(@run.events.find_by(kind: "sitting_started").payload_json)["condition"]
    served = ItemServed.find_by!(diagnosis_event_id: step.event.id)
    assert_equal "math.number", served.skill_key
    assert_equal "{}", served.id_map_json # a number is not shuffled
  end

  test "asking again while an item is open shows the same one and writes nothing" do
    first = @conductor.step!
    again = @conductor.step!
    assert_equal first.event.id, again.event.id
    assert_equal 2, @run.events.count
  end

  test "an item left open for 30 minutes is logged as given up and a fresh instance of the skill is served" do
    first = @conductor.step!
    @clock.advance(Diagnosis::Rules::V1::ABANDON_GAP_SECONDS + 1)
    next_step = @conductor.step!
    assert_equal :item, next_step.type
    refute_equal first.event.id, next_step.event.id
    assert_includes kinds, "item_abandoned"
    assert_equal ItemServed.find_by!(diagnosis_event_id: first.event.id).skill_key, ItemServed.find_by!(diagnosis_event_id: next_step.event.id).skill_key
    refute_equal ItemServed.find_by!(diagnosis_event_id: first.event.id).item_instance_id, ItemServed.find_by!(diagnosis_event_id: next_step.event.id).item_instance_id
  end

  test "the run goes through every skill and closes when the frontier is empty" do
    steps = 0
    loop do
      step = @conductor.step!
      break if step.type == :final

      assert_equal :item, step.type
      assert_equal "recorded", answer(step).status
      steps += 1
      flunk "no end" if steps > 10
    end
    assert_equal 3, steps
    assert_equal "frontier_empty", JSON.parse(@run.events.find_by(kind: "run_closed").payload_json)["reason"]
    assert @conductor.closed?
  end

  test "pause and visibility are recorded only when they change" do
    @conductor.step!
    assert @conductor.record(:paused)
    refute @conductor.record(:paused)
    assert @conductor.record(:resumed)
    refute @conductor.record(:resumed)
    assert @conductor.record(:hidden)
    assert @conductor.record(:visible)
    refute @conductor.record(:visible)
    assert_equal %w[paused resumed hidden visible], kinds.last(4)
    assert_raises(ArgumentError) { @conductor.record(:keepalive) }
  end

  test "an event that only the engine may write is refused" do
    assert_raises(ArgumentError) { @conductor.record("run_closed") }
  end

  test "a voided run is replaced by a fresh one, a closed one is not" do
    assert_equal @run, Diagnosis::Conductor.run_for(@rows[:student], @rows[:subject])
    Decision.create!(kind: "void_diagnosis_run", subject: @rows[:subject], student: @rows[:student],
                     payload_json: { run_id: @run.id }.to_json, request_id: SecureRandom.uuid, teacher_login: "t", remote_addr: "127.0.0.1")
    fresh = Diagnosis::Conductor.run_for(@rows[:student], @rows[:subject])
    refute_equal @run, fresh
    assert_equal 2, fresh.sequence
  end

  test "a subject without a blueprint has no run" do
    other = Subject.create!(key: "history", name_it: "Storia", position: 2)
    assert_nil Diagnosis::Conductor.run_for(@rows[:student], other)
  end

  test "the sitting ends at the budget, waits for the next day and starts again" do
    rows = build_ui_subject(key: "english", name: "Inglese", position: 3, components: %w[number choice ordering matching], sitting_minutes: 10)
    run = Diagnosis::Conductor.run_for(rows[:student], rows[:subject])
    clock = Diagnosis::FakeClock.new
    conductor = Diagnosis::Conductor.new(run, clock: clock)
    recorder = Diagnosis::AnswerRecorder.new(student: rows[:student], context: "diagnosis", clock: clock)

    step = conductor.step!
    assert_equal :item, step.type
    clock.advance(650) # the item counts its 600 seconds at most: the whole budget
    recorder.call(served_event_id: step.event.id, client_attempt_id: SecureRandom.uuid, raw: Grading::DONT_KNOW_RAW, source: "button")

    over = conductor.step!
    assert_equal :sitting_over, over.type
    assert_includes run.events.pluck(:kind), "sitting_closed"
    assert_equal :wait, conductor.step!.type, "the next sitting starts on a later day"
    assert_equal :wait, conductor.step!.type

    clock.advance(24 * 3600)
    assert_equal :item, conductor.step!.type
    assert_equal 2, run.events.where(kind: "sitting_started").count
  end
end
