module Practice
  # Seeds from the entry diagnosis (A8.6): the student's latest closed, non-voided run in the subject,
  # derived by the diagnosis engine unchanged. Trial students use their own runs (D-217).
  #
  #   Practice::Seeder.call(student, subject)   # => {skill => Practice::Seed}
  class Seeder
    def self.call(student, subject) = new(student, subject).seeds

    def initialize(student, subject)
      @student = student
      @subject = subject
    end

    def seeds
      run = closed_run or return {}
      conductor = Diagnosis::Conductor.new(run)
      result = Diagnosis::Derivation.result(conductor.plan, conductor.events)
      at = run.events.maximum(:at) || run.created_at
      result[:skills].filter_map { |row| seed(row, at, run) if row[:skill].start_with?("#{@subject.key}.") }.to_h { |s| [ s.skill, s ] }
    end

    private

    def closed_run
      runs = DiagnosisRun.where(student: @student, subject: @subject).order(sequence: :desc).to_a
      runs.reject { |r| Diagnosis::EventLoader.voided?(r) }.find { |r| Diagnosis::Conductor.new(r).closed? }
    end

    def seed(row, at, run)
      state, implied = case row[:state]
      when "demonstrated" then [ "demonstrated", false ]
      when "to_recover" then [ row[:kind] == "learn" ? "to_learn" : "to_recover", false ]
      when "not_assessed" then row[:reason] == "below_demonstrated" ? [ "demonstrated", true ] : nil
      end
      state && Practice::Seed.new(skill: row[:skill], state: state, at: at.in_time_zone(Rules::V1::ZONE), run_id: run.id, implied: implied)
    end
  end
end
