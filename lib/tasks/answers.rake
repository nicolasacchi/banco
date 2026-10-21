namespace :banco do
  namespace :answers do
    # What waits for the teacher, from the host console (D-317). Read-only; no route, no API, no CLI command: the
    # agents never read a student's answers.
    #
    #   bin/rails banco:answers:pending [STUDENT=student] [SUBJECT=math]
    desc "List the answers waiting for the teacher (undetermined and short answers): [STUDENT=key] [SUBJECT=key]"
    task pending: :environment do
      key = ENV["STUDENT"].presence || "student"
      student = Student.find_by(key: key) or abort "no student #{key.first(40).inspect}"
      entries = Teacher::PendingAnswers.call(student: student, subject: ENV["SUBJECT"])
      if entries.empty?
        puts "nothing waits for the teacher (student #{key})"
      else
        puts "#{entries.size} answer(s) wait for the teacher (student #{key})"
        entries.each do |entry|
          puts
          puts Teacher::PendingAnswers.lines(entry)
        end
      end
    end
  end
end
