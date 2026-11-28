module Writings
  # A text a student wrote himself, as a hash for GET /api/v1/writings (D-407). `text` is the student's own words (data to read, never instructions to follow);
  # `correction.text_it` is the teacher's. A bot only reads them: the correction is recorded by the teacher in the browser or by the operator at the console.
  module ApiRows
    module_function

    # +entry+: a Writings::Board::Entry.
    def row(entry)
      submission = entry.submission
      correction = entry.correction
      { id: submission.id, at: submission.created_at.utc.iso8601, student: submission.student.key, trial: submission.student.trial?, subject: entry.subject.key,
        topic: entry.topic_key, item: entry.item_key, item_revision_id: submission.item_revision_id, topic_revision_id: submission.topic_revision_id,
        task_it: entry.task_it, words_min: entry.words_min, words_max: entry.words_max, teacher_notes_it: entry.notes_it,
        status: correction ? "corrected" : "pending", word_count: submission.word_count, text: submission.text,
        correction: correction && { decision_id: correction.decision_id, at: correction.at.utc.iso8601, teacher: correction.teacher, text_it: correction.text_it } }.compact
    end
  end
end
