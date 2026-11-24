# Who did what (D-334): the teachers' and bots' actions in one newest-first feed, read from the ledgers that already
# record them and written nowhere. Several teachers and bots work on the same students (a token per person or bot,
# each with its teacher_login and a label); this is how one sees what the other did.
#
# Sources (SELECTs only, nothing is derived by rewriting a row):
#   - every decision (decisions.teacher_login; Decision#via: web, console or api; an api row's payload names the token),
#   - every comment event done by a teacher or a bot (comment_events.actor and .origin; an api event's payload names
#     the token); the student's own events (reply_seen) are not activity of a teacher,
#   - every view link creation and revocation (the actor is the token that made it: D-332).
#
#   Activity.recent(limit: 15)
#   Activity.recent(since: 1.day.ago, actor: "silvia@scc.im")
#
# A row is a Hash with string keys, ready for JSON:
#   {"at", "actor" => {"login", "via", "token" => {"public_id", "label"} | nil, "os_user" => String | nil}, "kind", "summary_it", "ref" => {...}}
# os_user is the host account of a console row (a decision keeps it in its user_agent, a comment event in its payload).
# The summary never carries the student's words nor the text of a reply: ids, kinds, subjects and topic keys only.
module Activity
  DEFAULT_LIMIT = 50
  MAX_LIMIT = 200
  COMMENT_KINDS = { "reply" => "comment_reply", "resolved" => "comment_resolve", "reopened" => "comment_reopen", "read" => "comment_read" }.freeze

  CONSOLE_AGENT = "banco:decide ".freeze

  module_function

  # The newest rows first, at most limit (clamped to 1..MAX_LIMIT). since: nil or a Time (rows at or after it: a cursor
  # taken from a row's "at" never skips a row of the same second); actor: nil or a login ("actor.login" of the rows).
  def recent(since: nil, actor: nil, limit: DEFAULT_LIMIT)
    limit = Integer(limit).clamp(1, MAX_LIMIT)
    actor = actor.to_s.strip.presence
    tokens = ApiToken.all.to_a
    by_public = tokens.index_by(&:public_id)
    by_id = tokens.index_by(&:id)
    candidates = decision_rows(since, actor, limit, by_public) + comment_rows(since, actor, limit, by_public) +
                 link_rows(since, actor, limit, tokens, by_id)
    candidates.sort_by { |c| c.first(2) }.reverse.first(limit).map(&:last)
  end

  # public_id => label for the given public ids (the API's decision and comment event rows name the token with its label).
  def token_labels(public_ids)
    ids = public_ids.compact.uniq
    ids.empty? ? {} : ApiToken.where(public_id: ids).pluck(:public_id, :label).to_h
  end

  # [sort time, id, row] triples: the sort key keeps the time of the ledger row to the microsecond, since "at" is in seconds.
  def decision_rows(since, actor, limit, by_public)
    scope = Decision.includes(:subject).order(created_at: :desc, id: :desc).limit(limit)
    scope = scope.where("created_at >= ?", since) if since
    scope = scope.where(teacher_login: actor) if actor
    scope.map do |decision|
      payload = JSON.parse(decision.payload_json)
      via = decision.via
      token = by_public[payload["token"]] if via == "api"
      ref = { "decision_id" => decision.id, "decision_kind" => decision.kind, "subject" => decision.subject&.key, "topic" => payload["topic"] }.compact
      os_user = decision.user_agent.delete_prefix(CONSOLE_AGENT).strip.presence if via == "console" && decision.user_agent.start_with?(CONSOLE_AGENT)
      [ decision.created_at, decision.id, row(decision.created_at, decision.teacher_login, via, token, "decision", decision_summary(decision, payload), ref, os_user: os_user) ]
    end
  end

  def comment_rows(since, actor, limit, by_public)
    scope = CommentEvent.where(kind: COMMENT_KINDS.keys).where.not(origin: "student").includes(comment: :subject).order(created_at: :desc, id: :desc).limit(limit)
    scope = scope.where("comment_events.created_at >= ?", since) if since
    scope = scope.where(actor: actor) if actor
    scope.map do |event|
      payload = JSON.parse(event.payload_json)
      token = by_public[payload["token"]] if event.origin == "api"
      os_user = payload["os_user"].presence if event.origin == "console"
      subject = event.comment.subject
      ref = { "comment_id" => event.comment_id, "subject" => subject&.key }.compact
      kind = COMMENT_KINDS.fetch(event.kind)
      summary = I18n.t("activity.#{kind}", id: event.comment_id) + subject_suffix(subject)
      [ event.created_at, event.id, row(event.created_at, event.actor, event.origin, token, kind, summary, ref, os_user: os_user) ]
    end
  end

  # A link's actor is the token that made it (always over the API); a revocation without a token (none is written today)
  # was not made over the API, so it can only have come from the console.
  def link_rows(since, actor, limit, tokens, by_id)
    ids = actor ? tokens.select { |t| login_of(t) == actor }.map(&:id) : nil
    narrow = lambda do |scope|
      scope = scope.order(created_at: :desc, id: :desc).limit(limit)
      scope = scope.where("created_at >= ?", since) if since
      ids ? scope.where(api_token_id: ids) : scope
    end
    created = narrow.call(ViewLink.all)
    revoked = narrow.call(ViewLinkRevocation.all)
    made = created.map do |link|
      token = by_id[link.api_token_id]
      minutes = ((link.expires_at - link.created_at) / 60).round
      summary = I18n.t("activity.view_link_created", id: link.id, path: link.path, minutes: minutes)
      [ link.created_at, link.id, row(link.created_at, login_of(token), "api", token, "view_link_created", summary, { "view_link_id" => link.id }) ]
    end
    ended = revoked.map do |revocation|
      token = by_id[revocation.api_token_id]
      via = token ? "api" : "console"
      summary = I18n.t("activity.view_link_revoked", id: revocation.view_link_id)
      [ revocation.created_at, revocation.id, row(revocation.created_at, login_of(token), via, token, "view_link_revoked", summary, { "view_link_id" => revocation.view_link_id }) ]
    end
    made + ended
  end

  # The login a token acts as: a teacher token's teacher; any other role (bot_read) is named by its role and label.
  def login_of(token)
    return nil unless token

    token.role == "teacher" ? token.teacher_login : "#{token.role}:#{token.label}"
  end

  def row(at, login, via, token, kind, summary, ref, os_user: nil)
    { "at" => at.utc.iso8601,
      "actor" => { "login" => login, "via" => via, "token" => (token ? { "public_id" => token.public_id, "label" => token.label } : nil), "os_user" => os_user },
      "kind" => kind, "summary_it" => summary, "ref" => ref }
  end

  def decision_summary(decision, payload)
    key = decision.kind
    key += payload["enabled"] ? "_on" : "_off" if key == "set_formula_sheet"
    key += payload["open"] ? "_open" : "_closed" if key == "release_course"
    key += payload["subject"].present? ? "_set" : "_clear" if key == "set_focus_subject"
    text = I18n.t("activity.decision.#{key}", default: I18n.t("activity.decision.other", kind: decision.kind))
    text += ": #{payload['topic']}" if payload["topic"].present?
    text + subject_suffix(decision.subject)
  end

  def subject_suffix(subject) = subject ? " (#{subject.name_it})" : ""
end
