require "test_helper"
require_relative "../../support/student_ui_rows"

# What a request has read from the ledger is reused, and is dropped the moment a row it depends on is added.
class DiagnosisReadsTest < ActiveSupport::TestCase
  include StudentUiRows

  setup do
    rows = build_ui_subject(components: %w[number choice])
    @run = Diagnosis::Conductor.run_for(rows[:student], rows[:subject])
    @conductor = Diagnosis::Conductor.new(@run, clock: Diagnosis::FakeClock.new)
  end

  test "the same question is answered once while nothing is written" do
    reads = 0
    2.times { Diagnosis::Reads.fetch(:probe) { reads += 1 } }
    assert_equal 1, reads
  end

  test "a new event of the run is seen by the next read of its events" do
    assert_empty Diagnosis::EventLoader.for_run(@run)
    @conductor.step!
    assert_equal %w[sitting_started item_served], Diagnosis::EventLoader.for_run(@run).map { |e| e[:kind] }
    assert_equal 1, Diagnosis::Conductor.new(@run).state.sittings.size
  end

  test "a voided run is seen as voided at once" do
    assert_not Diagnosis::EventLoader.voided?(@run)
    Decision.create!(kind: "void_diagnosis_run", subject: @run.subject, student: @run.student, payload_json: JSON.generate(run_id: @run.id, reason_it: "x"),
                     request_id: "vr-reads", teacher_login: "teacher", remote_addr: "127.0.0.1")
    assert Diagnosis::EventLoader.voided?(@run)
  end
end
