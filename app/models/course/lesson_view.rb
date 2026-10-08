module Course
  # Lesson rows as the agent API shows them (A4): reviews with their results and findings, the teacher's
  # send-back comments, the state of the latest revision.
  module LessonView
    module_function

    def reviews(revision)
      revision.reviews.includes(:agent_session).order(:id).map do |review|
        tally = review.checklist.map { |c| c["result"] }.tally
        { review_id: review.id, session_id: review.agent_session_id, model: review.agent_session.model,
          results: { pass: tally["pass"].to_i, fail: tally["fail"].to_i, na: tally["na"].to_i }, findings: review.findings }
      end
    end

    def severity_count(revision, severity)
      revision.reviews.sum { |r| r.findings.count { |f| f["severity"] == severity } }
    end

    def older_rules?(revision) = revision.rules_version.to_s != Validation::Rules.version.to_s

    def comments(lesson)
      ids = lesson.revisions.map(&:id)
      Course::Decisions.lesson_send_backs(ids).flat_map do |rev_id, rows|
        rows.map { |p| { decision_id: p["decision_id"], at: p["at"], reason_code: p["reason_code"], comment_it: p["comment_it"], lesson_revision_id: rev_id } }
      end.sort_by { |c| [ c[:at], c[:decision_id] ] }
    end

    def latest_row(revision)
      { revision_id: revision.id, seq: revision.seq, rules_version: revision.rules_version, older_rules: older_rules?(revision), warnings: revision.warnings }
    end
  end
end
