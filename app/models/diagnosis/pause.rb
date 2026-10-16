module Diagnosis
  # The suggestion to rest between subjects (D-298): a student who has worked on two or more subjects
  # today (a sitting started today, Rome date as elsewhere) is told a break would do well. A line of
  # text only: no limit and no button is taken away (D-294).
  module Pause
    SUBJECTS = 2

    module_function

    def subjects_today(student, clock: Clock.new)
      today = clock.date(clock.now)
      DiagnosisRun.where(student: student).includes(:subject).select do |run|
        next false if EventLoader.voided?(run)

        Conductor.new(run).state.sittings.any? { |s| clock.date(s.started_at) == today }
      end.map(&:subject_id).uniq.size
    end

    def suggested?(student, clock: Clock.new) = subjects_today(student, clock: clock) >= SUBJECTS
  end
end
