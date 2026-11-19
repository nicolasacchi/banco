module Teacher
  # What the student typed, in the words he read (D-376, D-380): `Diagnosis::AnswerText` on the serve that showed the exercise, so the shown ids are
  # turned back into the texts he saw and a reading test is one numbered line per question. The one reader of the corrections page
  # (Teacher::GradingReview#answer_words) and of the comment card's tries (CommentsHelper#comment_try_words); the stored text is what it says
  # when the serve is gone or the answer does not read as that exercise's.
  module AnswerWords
    module_function

    # {ref => words} of the practice and diagnosis tries among these rows (each with :kind, :id and :ref, as Attempts::Log gives them); other kinds have none.
    def call(rows)
      practice_ids = rows.select { |t| t[:kind] == "practice" }.map { |t| t[:id] }
      diagnosis_ids = rows.select { |t| t[:kind] == "diagnosis" }.map { |t| t[:id] }
      practice = PracticeAttempt.where(id: practice_ids).includes(practice_serve: :item_instance).index_by(&:id)
      diagnosis = Attempt.where(id: diagnosis_ids).includes(:item_instance).index_by(&:id)
      served = ItemServed.where(diagnosis_event_id: diagnosis.values.map(&:served_event_id)).index_by(&:diagnosis_event_id)
      rows.select { |t| %w[practice diagnosis].include?(t[:kind]) }.to_h do |t|
        words = if t[:kind] == "practice"
          attempt = practice.fetch(t[:id])
          of(attempt, attempt.practice_serve)
        else
          attempt = diagnosis.fetch(t[:id])
          of(attempt, served[attempt.served_event_id])
        end
        [ t[:ref], words ]
      end
    end

    # Diagnosis::AnswerText on the serve that showed the exercise; the stored text when the serve is gone or the answer does not read as that exercise's.
    def of(attempt, serve)
      serve ? Diagnosis::AnswerText.call(attempt, serve) : attempt.raw.to_s
    rescue JSON::ParserError, NoMethodError, TypeError
      attempt.raw.to_s
    end
  end
end
