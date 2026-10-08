module Course
  # The `course` block of `banco status` for one subject (A4).
  module Status
    module_function

    def for(subject)
      revision = State.latest(subject)
      rows = TopicStage.rows(subject)
      released = State.released_revision_id(subject)
      {
        revision: revision && { revision_id: revision.id, seq: revision.seq, skill_graph_revision_id: revision.skill_graph_revision_id,
                                graph_stale: State.graph_stale?(revision), warnings: State.warnings(revision) },
        released: !released.nil?, released_revision_id: released,
        topics: topic_counts(rows),
        lessons: lessons(subject),
        practice_items: practice_items(subject)
      }.tap { |h| h[:line_it] = line_it(h) }
    end

    # The line `banco status` shows for the subject (A4): "corso: 1 approvato, 2 dal docente, 8 da scrivere (11 nella mappa) · chiuso allo studente".
    def line_it(course)
      return "corso: nessuna mappa" unless course[:revision]

      t = course[:topics]
      parts = []
      parts << "#{t[:approved]} #{t[:approved] == 1 ? 'approvato' : 'approvati'}" if t[:approved].positive?
      parts << "#{t[:approved_newer_pending]} con una versione nuova" if t[:approved_newer_pending].positive?
      parts << "#{t[:awaiting_teacher]} dal docente" if t[:awaiting_teacher].positive?
      parts << "#{t[:in_review]} in revisione" if t[:in_review].positive?
      parts << "#{t[:missing]} da scrivere" if t[:missing].positive?
      "corso: #{parts.join(', ')} (#{t[:in_map]} nella mappa) · #{course[:released] ? 'aperto' : 'chiuso'} allo studente"
    end

    def topic_counts(rows)
      counts = (rows || {}).values.map(&:stage).tally
      { in_map: (rows || {}).size, missing: counts["missing"].to_i, in_review: counts["in_review"].to_i, awaiting_teacher: counts["awaiting_teacher"].to_i,
        approved: counts["approved"].to_i, approved_newer_pending: counts["approved_newer_pending"].to_i }
    end

    def lessons(subject)
      latest = Lesson.where(subject: subject).includes(revisions: :reviews).filter_map(&:latest_revision)
      { total: latest.size, unreviewed: latest.count { |r| r.reviews.empty? }, sent_back: latest.count { |r| Decisions.lesson_sent_back?(r) } }
    end

    def practice_items(subject)
      items = Item.practice.where(subject: subject).includes(revisions: :validations)
      latest = items.filter_map { |i| i.revisions.max_by(&:seq) }
      states = latest.map { |r| (v = r.validations.max_by(&:seq)) ? v.display_status : "validating" }.tally
      back = Teacher::SendBacks.by_revision(latest.map(&:id))
      current = Validation::Rules.version.to_s
      { total: latest.size, passed: states["passed"].to_i, failed: states["failed"].to_i, awaiting_verifier: states["awaiting_verifier"].to_i,
        validating: states["validating"].to_i, error: states["error"].to_i,
        older_rules: latest.count { |r| (v = r.validations.max_by(&:seq)) && v.status == "passed" && v.rules_version.to_s != current },
        sent_back: latest.count { |r| back.key?(r.id) } }
    end
  end
end
