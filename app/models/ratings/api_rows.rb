module Ratings
  # A rating and a target's summary as hashes, for GET /api/v1/ratings (D-365). The rows of Ratings::List must be loaded with
  # `includes` as List#rows does; the student's words are `text_it`.
  module ApiRows
    module_function

    def row(rating)
      { id: rating.id, at: rating.created_at.utc.iso8601, kind: rating.target_kind, target: rating.target_key, revision_id: rating.revision_id,
        revision: (rating.item? ? rating.item_revision : rating.lesson_revision).seq, subject: rating.subject.key, topic: rating.topic_revision.lesson.key,
        student: rating.student.key, trial: rating.trial, stars: rating.stars, text_it: rating.text_it, language: rating.language, serve_id: rating.practice_serve_id }.compact
    end

    # average: to one decimal, as the teacher's page says it; count: how many official students' current stars it is made of.
    def target(entry)
      summary = entry.summary
      { kind: entry.kind, target: entry.key, ratings: entry.rows, count: summary&.count.to_i, average: summary && summary.average.round(1) }.compact
    end

    def summary(summary) = summary && { count: summary.count, average: summary.average.round(1) }
  end
end
