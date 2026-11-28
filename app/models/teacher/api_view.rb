module Teacher
  # The teacher's pages as JSON (D-328): the same read models the browser pages use (Home and Dashboard, CourseReview,
  # TopicReview, TestReview, ItemCard), turned into plain hashes for GET /api/v1/teacher/... and /api/v1/students/:key/progress.
  # No query of its own and nothing written: opening a page records "the teacher read it" (an app event) and an API read
  # never does. Texts the page words in Italian (badges, waiting lines, gate reasons) come with an `_it` member next to the
  # key or the English reason, so the reader can both match and read them.
  module ApiView
    module_function

    # ---- home -------------------------------------------------------------------------------------

    def home(dashboard)
      home = dashboard.home
      release = dashboard.release
      {
        student: dashboard.student&.key,
        counts: dashboard.counts.to_h,
        todos: dashboard.todos.map { |t| todo(t) },
        subjects: home.rows.map { |row| subject_row(row, dashboard) },
        state: { subjects_waiting: home.waiting_total, corrections: home.corrections, minutes_total: home.minutes[:total], released: home.released?,
                 consent_recorded: home.consent_recorded?, warmup_complete: release.warmup, approvals: { done: release.approved, total: release.total } }
      }
    end

    def todo(todo)
      text = case todo.kind
      when :findings then I18n.t("teacher.dashboard.todo.findings", count: todo.count)
      when :release
        todo.reason.empty? ? I18n.t("teacher.dashboard.todo.release_ready") : I18n.t("teacher.dashboard.todo.release", missing: todo.reason.map { |m| I18n.t("teacher.dashboard.missing.#{m}") }.to_sentence(two_words_connector: " e ", last_word_connector: " e "))
      when :test_blocked then I18n.t("teacher.dashboard.todo.test_blocked", reason: todo.reason)
      when :topics, :corrections then I18n.t("teacher.dashboard.todo.#{todo.kind}", count: todo.count)
      when :jobs, :backup then todo.reason
      else I18n.t("teacher.dashboard.todo.#{todo.kind}")
      end
      { kind: todo.kind, subject: todo.subject&.key, count: todo.count, clear_findings: todo.extra, text_it: text, page: todo.href }
    end

    def subject_row(row, dashboard)
      waiting = row.waiting.map { |code, count| { code: code, count: count, text_it: I18n.t("teacher.home.wait.#{code}", count: count.to_i) } }
      {
        key: row.subject.key, name_it: row.subject.name_it, stage: row.stage, has_graph: row.has_graph, has_blueprint: row.has_blueprint,
        items: row.items, waiting: waiting, blocked_it: row.blocked, clear_findings: row.clear, minutes: row.minutes,
        course: row.course&.to_h,
        students: dashboard.students.map { |student| student_cell(dashboard.cell(student, row.subject)) }
      }
    end

    def student_cell(cell)
      { student: cell.student.key, official: cell.student.official?, diagnosis_it: cell.diagnosis, last_activity_at: time(cell.last_at), practised_skills: cell.practised }
    end

    # ---- the course path --------------------------------------------------------------------------

    def course(review, only_ready: false)
      out = { subject: subject(review.subject), present: review.present? }
      return out unless review.present?

      keep = ->(steps) { steps.select { |s| !only_ready || s.ready? } }
      out.merge(
        revision: { id: review.latest.id, seq: review.latest.seq }, open: review.open?, released_revision_id: review.released_id, released_latest: review.released_latest?,
        focus_subject: Course::Focus.subject_key, recommended: Course::Focus.subject_key == review.subject.key,
        counts: review.counts.merge(ready: review.ready_count), notes_it: review.notes,
        warnings: review.warnings.map { |w| { code: w["code"], message: I18n.t("teacher.course.warning.#{w['code']}", default: w["message"]) } },
        topics: keep.call(review.programme_steps).map { |s| step(s, review.subject) },
        extra_topics: keep.call(review.extra_steps).map { |s| step(s, review.subject) },
        release: { releasable: review.releasable?, checks: review.release_checks.map { |name, done| { name: name, done: done } },
                   reasons: review.release_reasons, reasons_it: review.release_reasons.map { |r| Teacher::Wording.italian(r) } },
        skills: review.skills.map { |s| skill_row(s) }
      )
    end

    def step(step, subject)
      entry = step.entry
      row = step.row
      attested = row.stage == "approved" ? Course::Decisions.attestation(entry["key"]) : nil
      {
        number: step.number, key: entry["key"], kind: entry["kind"], extra: step.extra?, title_it: entry["title_it"], term: entry["term"], minutes: entry["minutes"],
        skills: entry["skills"], after: Array(entry["after"]), stage: row.stage, badge: step.badge, badge_it: I18n.t("teacher.path.badge.#{step.badge}"),
        missing_it: step.missing_it, lesson_written: step.lesson?, exercises: step.exercises, open_findings: step.open_findings, ready: step.ready?,
        latest_revision: row.latest && { id: row.latest.id, seq: row.latest.seq }, approved_revision_id: row.approved_revision_id, attested_it: attested,
        gate_reasons: row.reasons, gate_reasons_it: row.reasons.map { |r| Teacher::Wording.italian(r) },
        progress: step.progress.map { |p| { student: p.student.key, tries: p.tries, skills_done: p.done, skills_total: p.total } },
        page: "/teacher/subjects/#{subject.key}/topics/#{entry['key']}"
      }
    end

    def skill_row(skill)
      { key: skill.key, label_it: skill.label_it, layer: skill.layer,
        refs: skill.refs.map { |r| { source: r.source, line: r.line, fragment: r.fragment, role: r.role, programme_text: r.text } }, errors: skill.errors }
    end

    # ---- one topic --------------------------------------------------------------------------------

    def topic(review, lesson_text: false)
      out = { subject: subject(review.subject), key: review.key, present: review.present?, extra: review.extra? }
      return out unless review.present?

      out[:title_it] = review.entry && review.entry["title_it"]
      return out.merge(latest: nil, missing_it: I18n.t("teacher.topic.missing")) if review.latest.nil?

      latest = review.latest
      done = review.steps_done
      out.merge(
        latest: { id: latest.id, seq: latest.seq, intro_it: review.intro_it }, approved: { latest: review.approved_latest?, revision_id: review.approved_id, seq: review.approved&.seq },
        attested_it: review.approved_latest? ? Course::Decisions.attestation(review.key) : nil,
        map_entry: review.entry, lesson: lesson(review, text: lesson_text),
        lesson_reviews: review.reviews.map { |row| lesson_review(row, review) },
        exercises: review.exercises.each_with_index.map { |ex, i| exercise(ex, i + 1) },
        writing: review.writing_tasks.map { |t| card_json(t.card).merge(task_it: t.stem, words_min: t.words_min, words_max: t.words_max, teacher_notes_it: t.notes_it) },
        findings: { lesson: review.lesson_findings.map { |e| lesson_finding(e, review) }, items: review.cards_with_findings.map { |c| { item: c.item.key, revision_id: c.revision.id, findings: c.findings.map { |f| finding(f) } } },
                    count: review.findings_count, clear: review.findings_clear? },
        send_backs: review.send_backs.map { |sb| sb.transform_keys(&:to_s) },
        lesson_sent_back: review.lesson_sent_back?,
        steps: { lesson_read: done[:lesson], exercises_seen: done[:exercises], findings_clear: done[:findings], approved: done[:approve] },
        approval: approval(review),
        pages: review.pages.map { |p| { key: p.page.key, revision_id: p.id, title_it: p.manifest["title_it"] } },
        next_ready: review.next_ready&.entry&.dig("key")
      )
    end

    # The facts of the lesson (the page's "Lezione" box). The text itself is large: only with lesson_text.
    def lesson(review, text:)
      body = review.lesson_body
      out = { revision_id: review.lesson_revision.id, seq: review.lesson_revision.seq, schema: body["schema"], kind: body["kind"], title_it: body["title_it"], minutes: body["minutes"],
              scope: body["scope"], calculator: body["calculator"], uses: Array(body["uses"]), refs: Array(body["refs"]), render: review.render_line }
      out[:cards] = Array(body["cards"]).size if body["schema"] == "banco.lesson/2"
      out[:body] = body if text
      out
    end

    def lesson_review(row, review)
      session = row.session
      { id: row.review.id, session_id: session.id, model: session.model, declared_model: session.declared_model, independent: row.independent, results: row.results,
        checklist: row.checklist, recomputed: row.recomputed, findings: review.lesson_findings_of(row).map(&:id) }
    end

    def lesson_finding(entry, review)
      { id: entry.id, severity: entry.severity, place_it: review.finding_place(entry), quote: entry.finding["quote"], problem_it: entry.finding["problem_it"],
        fix_it: entry.finding["fix_it"], response: entry.response&.to_h }
    end

    def exercise(ex, number)
      card = ex.card
      { number: number, item: card.item.key, revision_id: card.revision.id, seq: card.revision.seq, skill: ex.skill, skill_label_it: ex.skill_label, level: ex.level,
        purpose_it: ex.purpose_it, seen: ex.seen, card: card_json(card), samples: ex.samples.map { |s| sample(s.view) } }
    end

    def sample(view)
      { number: view.number, stem: view.stem, choices: view.choices, key: view.key, errors: view.errors, hints: view.hints, steps: view.steps, final: view.final }
    end

    # ---- the approval of a topic ------------------------------------------------------------------

    def approval(review)
      gate = review.gate
      { approvable: review.approvable?, gate_approvable: gate.approvable, reasons: gate.reasons, reasons_it: gate.reasons.map { |r| Teacher::Wording.italian(r) },
        checks: review.checks.map { |c| { name: c.name, done: c.done, reasons_it: c.reasons.map { |r| Teacher::Wording.italian(r) } } },
        other_reasons_it: review.other_reasons.map { |r| Teacher::Wording.italian(r) }, needs_reason: review.needs_reason? }
    end

    # ---- the entry test ---------------------------------------------------------------------------

    def test(review)
      out = { subject: subject(review.subject), present: review.present? }
      return out unless review.present?

      gate = review.gate
      out.merge(
        blueprint: { id: review.blueprint.id, seq: review.blueprint.seq, pinned_items: review.pinned_count }, approved: review.approved_latest?,
        approval: { approvable: gate.approvable && !review.approved_latest?, reasons: gate.reasons, reasons_it: gate.reasons.map { |r| Teacher::Wording.italian(r) } },
        attested_it: review.approved_latest? ? SubjectStage.blueprint_attestation(review.subject) : nil,
        skills: review.skill_rows.map { |row| test_skill(row, review) },
        open_findings: review.open_finding_list.map { |o| open_finding(o) },
        clear_open_findings: review.clear_open_list.map { |o| o.finding.id },
        settings: review.settings, formula_sheet: review.formula_sheet, traces: review.traces
      )
    end

    def test_skill(row, review)
      { skill: row.skill, label_it: row.label_it, role: row.role, items: review.cards(row.skill).map { |card| card_json(card) }, item_revision_ids: row.item_ids,
        not_assessed_reason_it: row.not_assessed_reason_it, redo_reserve: row.redo_reserve, choice_only_reason_it: row.choice_only_reason_it, reviewed: row.worked, open_findings: row.open_findings }
    end

    def open_finding(open)
      f = open.finding
      { id: f.id, severity: f.severity, skill: open.skill, label_it: open.label_it, item: open.item_key, instance: f.instance, problem_it: f.problem_it,
        opinion: opinion(open.opinion) }
    end

    # ---- an item card (the entry test's skill screen and the topic's exercises) -------------------

    def card_json(card)
      {
        item: card.item.key, revision_id: card.revision.id, seq: card.revision.seq, kind: card.body["kind"], component: card.body["component"], level: card.body["level"],
        superseded: card.superseded, gate: { approvable: card.gate.approvable, reasons: card.gate.reasons, reasons_it: card.gate.reasons.map { |r| Teacher::Wording.italian(r) } },
        catalogue: card.catalogue, sources: card.sources, review: review_json(card), blind_solve: blind_json(card),
        send_backs: card.send_backs.map { |sb| sb.transform_keys(&:to_s) }, findings: card.findings.map { |f| finding(f) }
      }
    end

    def review_json(card)
      return nil unless card.review

      failed = card.review.select { |c| c["result"] == "fail" }
      { pass: card.review.size - failed.size, fail: failed.size, failed: failed.map { |c| { point: c["id"], text: Review::Checklist::ALL_POINTS[c["id"] - 1], evidence: c["evidence"] } }, by: provenance(card.review_by) }
    end

    def blind_json(card)
      return nil unless card.blind

      mismatches = card.blind.reject { |r| %w[correct short_answer].include?(r["verdict"]) }
      { ok: card.blind.size - mismatches.size, total: card.blind.size, mismatches: mismatches, by: provenance(card.blind_by) }
    end

    def provenance(prov)
      prov && { session_id: prov.session.id, model: prov.session.model, independent: prov.independent }
    end

    def finding(entry)
      f = entry.finding
      ev = entry.evidence
      { id: f.id, severity: f.severity, source: f.source, instance: f.instance, field: Teacher::FindingField.key_for(f.field), field_it: Teacher::FindingField.phrase(f.field),
        quote: f.quote, problem_it: f.problem_it, fix_it: f.fix_it, disposition: entry.disposition, new_revision_expected: entry.new_revision_expected,
        closure: entry.closure, evidence: ev && { key: ev.key, accepted: ev.accepted, solver_answer: ev.solver_answer, dont_know: ev.dont_know },
        response: entry.response&.to_h, opinion: opinion(entry.opinion) }
    end

    def opinion(opinion)
      { state: opinion.state, verdict: opinion.verdict, first: opinion.first&.to_h, history: opinion.history.map(&:to_h) }
    end

    # ---- helpers ----------------------------------------------------------------------------------

    def subject(subject) = { key: subject.key, name_it: subject.name_it }

    def time(value) = value&.utc&.iso8601
  end
end
