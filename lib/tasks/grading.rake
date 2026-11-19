namespace :banco do
  namespace :grading do
    # Candidate grading vectors from the teacher's corrections (D-368): every `resolve_attempt` that made an answer right is a case the grader got wrong
    # when it was sent. Prints, as JSON, the cases of test/fixtures/grading/vectors.json's own shape (id, component, raw, item = the spec and the key,
    # expect = the verdict the teacher gave) for the operator to review and paste into that file; one already there (by id) is left out. Never writes.
    #
    #   bin/rails banco:grading:vectors [STUDENT=student]
    desc "Print candidate grading vectors from the teacher's resolve_attempt corrections as JSON (print only): [STUDENT=key]"
    task vectors: :environment do
      key = ENV["STUDENT"].presence || Student::OFFICIAL_KEY
      student = Student::KEY_FORMAT.match?(key) ? Student.find_by(key: key, kind: "student") : nil
      student or abort "no student #{key.first(40).inspect}"
      cases = Teacher::GradingVectors.new(student).cases
      warn "#{cases.size} candidate vector(s) for #{key}: review them, then paste into test/fixtures/grading/vectors.json"
      puts JSON.pretty_generate(cases)
    end
  end
end
