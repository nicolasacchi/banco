# What the rest of the app reads of the render check (D-249, A12): the API's status, the topic gate's reason, the
# teacher's one line. The rows themselves are LessonRender (append-only).
module LessonRenders
  # The further states of a card the render check draws (D-311): "exN" (exercise N of «Prova tu» shown), "open" and "exN-open"
  # (every closed part opened), and (D-402) "tr" and "exN-tr" (every translation of the card opened). A shot or an error without a state is the card as drawn.
  STATE = /\A(?:ex(\d+))?(?:(-?open)|(-?tr))?\z/

  module_function

  # Where a state's pictures go on the teacher's page: the card as drawn, the card opened, with the translation open, then each exercise and its further states.
  def state_rank(state)
    return [ 0, 0 ] if state.nil?

    n, open, translation = state.to_s.match(STATE)&.captures
    [ 1, (n.to_i * 3) + (open ? 1 : (translation ? 2 : 0)) ]
  end

  # The state in the teacher's words, or nil for the card as drawn.
  def state_words(state)
    return nil if state.nil?

    n, open, translation = state.to_s.match(STATE)&.captures
    return state.to_s unless n || open || translation

    key = if translation then n ? "state_ex_tr" : "state_tr"
    else n ? (open ? "state_ex_open" : "state_ex") : "state_open"
    end
    I18n.t("teacher.render.shots.#{key}", n: n)
  end

  # The gate's reason for a lesson/2 revision, or nil when its latest render has no error (and nil for lesson/1).
  # The words matter: Teacher::TopicReview groups them by "render check", Teacher::Wording turns them into Italian.
  def gate_reason(revision)
    return nil unless revision.lesson2?

    row = LessonRender.latest_for(revision)
    return "the lesson revision has no render without errors yet: the render check has not run" if row.nil?
    return "the lesson revision has no render without errors: the render check could not run, it runs again" if row.status == "error" || row.timeout_only?
    return nil if row.passed?

    errors = row.errors_list
    first = errors.first(3).map { |e| "#{e['code']}#{" on card #{e['card']}" if e['card']}" }.uniq.join(", ")
    "the lesson revision has no render without errors: the render check found #{errors.size} error(s) (#{first})"
  end

  # { status: pending|passed|failed|error, ... } for `banco lesson status`.
  def summary(revision)
    row = LessonRender.latest_for(revision)
    return { status: "pending", next: "the job renders the revision soon; ask again with banco lesson status #{revision.id}" } unless row

    shots = row.shots
    out = { status: row.status, render_id: row.id, at: row.created_at.utc.iso8601, shots: shots.size, shots_available: shots.count { |s| LessonShots.exist?(s["sha256"]) },
            errors: row.errors_list, elapsed_seconds: row.result["elapsed_seconds"], chrome_version: row.chrome_version, harness_version: row.harness_version }
    out[:message] = row.result["message"] if row.status == "error"
    out[:next] = case row.status
    when "passed" then "look at every card: banco lesson shots #{revision.id} --dir DIR"
    when "failed" then row.timeout_only? ? timeout_next(revision) : "fix the data of the cards named in errors, banco lesson submit DIR --dry-run, then submit (a new revision is drawn again)"
    else "Chrome could not be reached; the job tries again, ask again with banco lesson status #{revision.id}"
    end
    out[:timeout_only] = true if row.timeout_only?
    out
  end

  # What an author reads when the render ran out of time only (never his data): the server's limit, who draws it again and how to ask.
  def timeout_next(revision)
    again = LessonRender.timeout_streak(revision) < RenderLessonRevisionJob::TIMEOUT_DRAWS
    "the render ran out of the server's time limit: it is not a problem of the cards' data, do not change the lesson for it. " \
      "#{again ? 'The server draws it again by itself in a few minutes (ask again with banco lesson status ' + revision.id.to_s + '); if it keeps failing, or to ask at once: ' : 'It stopped asking again; draw it once more: '}" \
      "banco lesson render #{revision.id} --retry"
  end

  # What the teacher's topic page says (one line, errors by card): { state:, count:, cards: [{ n:, title_it:, errors: [..] }] }.
  def teacher_line(revision)
    row = LessonRender.latest_for(revision)
    return { state: "pending" } unless row
    return { state: row.status } unless %w[passed failed].include?(row.status)

    titles = revision.body["cards"].to_h { |c| [ c["n"], c["title_it"] ] }
    by_card = row.errors_list.group_by { |e| e["card"] }.map do |n, list|
      { n: n, title_it: n ? titles[n] : nil, errors: list.map { |e| e.slice("code", "viewport", "message") }.uniq }
    end
    { state: row.status, count: row.shots.size, cards: by_card.sort_by { |c| c[:n].to_i }, render_id: row.id }
  end
end
