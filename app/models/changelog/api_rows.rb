module Changelog
  # The rows of GET /api/v1/changelog (D-375): the entries as the file holds them, the updates as the ledger gives them.
  module ApiRows
    module_function

    # teacher: true adds the decisions behind the entry (the student's text never names them).
    def entry(entry, teacher:)
      row = { id: entry.id, date: entry.date.iso8601, audience: entry.audience, kind: entry.kind, title_it: entry.title_it, body_it: entry.body_it,
              title_en: entry.title_en, body_en: entry.body_en, topics: entry.topics.presence, link: entry.link }
      row[:decisions] = entry.decisions.presence if teacher
      row.compact
    end

    # One approval that replaced another: the ids of the two revisions and the decision; the teacher's reason only when asked (`reason`).
    def update(update, reason:)
      row = { at: update.at.utc.iso8601, date: update.date.iso8601, subject: update.subject_key, topic: update.topic, title_it: update.title_it,
              old_revision_id: update.old_revision_id, new_revision_id: update.new_revision_id, decision_id: update.decision_id }
      row[:reason_it] = update.reason_it if reason && update.reason_it
      row.compact
    end
  end
end
