module Teacher
  # «Testi da correggere» (D-407): the texts the student wrote himself on the writing tasks of the topics, pending first, then corrected. Read-only for the
  # guest (no form); the teacher's form posts the decision `correct_writing` to Teacher::DecisionsController (the person's own words: firm rule 1), which comes
  # back here with a flash. Default student: the official one; `?student=KEY` picks a trial student, as «Correzioni» does (ViewedStudent).
  class WritingsController < Teacher::BaseController
    def show
      @unit = "evening"
      @board = Writings::Board.new(student: viewed_student)
    end
  end
end
