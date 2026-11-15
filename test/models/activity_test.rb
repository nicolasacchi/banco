require "test_helper"

# D-334: Activity.recent, the feed of who did what, built from the ledgers that already record it. Rows are written
# straight into the ledgers here, with fixed times; the whole path (browser, console, API) is in activity_api_test.
class ActivityTest < ActiveSupport::TestCase
  T0 = Time.utc(2026, 11, 15, 9, 0, 0)

  setup do
    @subject = Subject.create!(key: "math", name_it: "Matematica", position: 1, created_at: T0)
    @student = Student.create!(key: "student", kind: "student", created_at: T0)
    @nik = ApiToken.create!(public_id: "nikToken", secret_sha256: "a" * 64, role: "teacher", label: "teacher-nik", teacher_login: "nik", expires_at: T0 + 30.days, created_at: T0)
    @silvia = ApiToken.create!(public_id: "xkSIgdEx", secret_sha256: "b" * 64, role: "teacher", label: "teacher-silvia-bot-2026-11-15", teacher_login: "silvia@scc.im", expires_at: T0 + 30.days, created_at: T0)
    @reader = ApiToken.create!(public_id: "readTokn", secret_sha256: "c" * 64, role: "bot_read", label: "reader-bot", expires_at: T0 + 30.days, created_at: T0)
    @comment = Comment.create!(student: @student, client_comment_id: "c-1", reason: "error", page_path: "/today", page_kind: "today", subject: @subject,
                               text_it: "PAROLA-SEGRETA-DELLO-STUDENTE", created_at: T0)
    build_ledger
  end

  def decision(kind, login, minutes, via: nil, token: nil, payload: {}, user_agent: "")
    payload = payload.merge(via: via, token: token).compact
    Decision.create!(kind: kind, subject: @subject, payload_json: payload.to_json, request_id: SecureRandom.uuid, teacher_login: login,
                     groups: via == "api" ? "api" : "banco-teacher", remote_addr: "127.0.0.1", user_agent: user_agent, created_at: T0 + minutes.minutes)
  end

  def event(kind, actor, origin, minutes, token: nil, text: nil, os_user: nil)
    CommentEvent.create!(comment: @comment, kind: kind, origin: origin, actor: actor, text_it: text, request_id: SecureRandom.uuid,
                         payload_json: { token: token, os_user: os_user }.compact.to_json, created_at: T0 + minutes.minutes)
  end

  # Newest last: 1 nik web decision, 2 silvia api decision, 3 console decision, 4 nik web reply, 5 silvia api reply, the student's own
  # reply_seen (not activity), 7 a link by the bot_read token, 8 its revocation.
  def build_ledger
    @web = decision("set_formula_sheet", "nik", 1, payload: { subject: "math", enabled: false })
    @api = decision("approve_topic", "silvia@scc.im", 2, via: "api", token: "xkSIgdEx", payload: { topic: "lezione.math.potenze" })
    @console = decision("release_course", "nik", 3, via: "console", payload: { subject: "math", open: true })
    @web_reply = event("reply", "nik", "web", 4, text: "RISPOSTA-SEGRETA-DEL-DOCENTE")
    @api_reply = event("reply", "silvia@scc.im", "api", 5, token: "xkSIgdEx", text: "Un'altra risposta riservata.")
    event("reply_seen", "student", "student", 6)
    @link = ViewLink.create!(api_token: @reader, token_digest: Digest::SHA256.hexdigest("raw"), path: "/teacher/subjects/math/course", expires_at: T0 + 7.minutes + 2.hours, created_at: T0 + 7.minutes)
    @revocation = ViewLinkRevocation.create!(view_link: @link, api_token: @reader, created_at: T0 + 8.minutes)
  end

  def kinds(rows) = rows.map { |r| r["kind"] }

  test "every action is listed newest first, the student's own events are not" do
    rows = Activity.recent
    assert_equal %w[view_link_revoked view_link_created comment_reply comment_reply decision decision decision], kinds(rows)
    assert_equal rows.map { |r| r["at"] }.sort.reverse, rows.map { |r| r["at"] }
    assert_equal "2026-11-15T09:08:00Z", rows.first["at"]
  end

  test "a browser decision names the login, via web and no token" do
    row = Activity.recent.find { |r| r.dig("ref", "decision_id") == @web.id }
    assert_equal({ "login" => "nik", "via" => "web", "token" => nil, "os_user" => nil }, row["actor"])
    assert_equal({ "decision_id" => @web.id, "decision_kind" => "set_formula_sheet", "subject" => "math" }, row["ref"])
    assert_equal "Spento il formulario (Matematica)", row["summary_it"]
  end

  test "an API decision names the teacher of the token, via api, and the token's public id and label" do
    row = Activity.recent.find { |r| r.dig("ref", "decision_id") == @api.id }
    assert_equal({ "login" => "silvia@scc.im", "via" => "api", "token" => { "public_id" => "xkSIgdEx", "label" => "teacher-silvia-bot-2026-11-15" }, "os_user" => nil }, row["actor"])
    assert_equal({ "decision_id" => @api.id, "decision_kind" => "approve_topic", "subject" => "math", "topic" => "lezione.math.potenze" }, row["ref"])
    assert_equal "Approvato un argomento: lezione.math.potenze (Matematica)", row["summary_it"]
  end

  test "a console decision is via console with no token" do
    row = Activity.recent.find { |r| r.dig("ref", "decision_id") == @console.id }
    assert_equal({ "login" => "nik", "via" => "console", "token" => nil, "os_user" => nil }, row["actor"])
    assert_equal "Aperto il corso allo studente (Matematica)", row["summary_it"]
  end

  test "a console comment reply and a console decision show via console and the host's os_user, nothing else does" do
    decision("approve_topic", "nik", 11, via: "console", payload: { topic: "lezione.math.potenze" }, user_agent: "banco:decide nik-host")
    event("reply", "nik", "console", 12, text: "Risposta dalla console.", os_user: "nik-host")
    rows = Activity.recent(limit: 2)
    assert_equal %w[comment_reply decision], kinds(rows)
    rows.each { |r| assert_equal [ "nik", "console", nil, "nik-host" ], r["actor"].values_at("login", "via", "token", "os_user") }
    assert Activity.recent.drop(2).all? { |r| r.dig("actor", "os_user").nil? }
  end

  test "a reply by a browser teacher and one by a bot: who, how, which comment, and never the reply's text" do
    web = Activity.recent.find { |r| r["kind"] == "comment_reply" && r.dig("actor", "via") == "web" }
    api = Activity.recent.find { |r| r["kind"] == "comment_reply" && r.dig("actor", "via") == "api" }
    assert_equal({ "login" => "nik", "via" => "web", "token" => nil, "os_user" => nil }, web["actor"])
    assert_equal({ "login" => "silvia@scc.im", "via" => "api", "token" => { "public_id" => "xkSIgdEx", "label" => "teacher-silvia-bot-2026-11-15" }, "os_user" => nil }, api["actor"])
    assert_equal({ "comment_id" => @comment.id, "subject" => "math" }, web["ref"])
    assert_equal "Risposta al commento #{@comment.id} (Matematica)", api["summary_it"]
    text = Activity.recent.to_json
    assert_not_includes text, "PAROLA-SEGRETA-DELLO-STUDENTE"
    assert_not_includes text, "RISPOSTA-SEGRETA-DEL-DOCENTE"
    assert_not_includes text, "Un'altra risposta riservata."
  end

  test "a view link by a bot_read token is attributed to bot_read:label, via api, and so is its revocation" do
    created = Activity.recent.find { |r| r["kind"] == "view_link_created" }
    revoked = Activity.recent.find { |r| r["kind"] == "view_link_revoked" }
    expected = { "login" => "bot_read:reader-bot", "via" => "api", "token" => { "public_id" => "readTokn", "label" => "reader-bot" }, "os_user" => nil }
    assert_equal expected, created["actor"]
    assert_equal expected, revoked["actor"]
    assert_equal({ "view_link_id" => @link.id }, created["ref"])
    assert_equal({ "view_link_id" => @link.id }, revoked["ref"])
    assert_equal "Creato il link di sola lettura #{@link.id} (/teacher/subjects/math/course, 120 minuti)", created["summary_it"]
    assert_equal "Revocato il link di sola lettura #{@link.id}", revoked["summary_it"]
  end

  test "a revocation that no token made came from the console" do
    other = ViewLink.create!(api_token: @nik, token_digest: Digest::SHA256.hexdigest("raw2"), path: "/teacher", expires_at: T0 + 9.minutes + 3.hours, created_at: T0 + 9.minutes)
    ViewLinkRevocation.create!(view_link: other, api_token: nil, created_at: T0 + 10.minutes)
    row = Activity.recent(limit: 1).first
    assert_equal [ "view_link_revoked", nil, "console", nil ], [ row["kind"], row.dig("actor", "login"), row.dig("actor", "via"), row.dig("actor", "token") ]
  end

  test "actor filters on the login of the rows, bot_read links included" do
    assert_equal %w[comment_reply decision], kinds(Activity.recent(actor: "silvia@scc.im"))
    assert_equal [ "silvia@scc.im" ], Activity.recent(actor: "silvia@scc.im").map { |r| r.dig("actor", "login") }.uniq
    assert_equal %w[comment_reply decision decision], kinds(Activity.recent(actor: "nik"))
    assert_equal %w[view_link_revoked view_link_created], kinds(Activity.recent(actor: "bot_read:reader-bot"))
    assert_empty Activity.recent(actor: "nessuno")
  end

  test "since keeps the rows at or after it" do
    assert_equal %w[view_link_revoked view_link_created comment_reply], kinds(Activity.recent(since: T0 + 5.minutes))
    assert_equal %w[view_link_revoked], kinds(Activity.recent(since: T0 + 8.minutes))
    assert_empty Activity.recent(since: T0 + 9.minutes)
    assert_equal 7, Activity.recent(since: T0).size
  end

  test "limit bounds the rows, newest first, and is kept within 1..200" do
    assert_equal %w[view_link_revoked view_link_created comment_reply], kinds(Activity.recent(limit: 3))
    assert_equal 1, Activity.recent(limit: 0).size
    assert_equal 1, Activity.recent(limit: -5).size
    assert_equal 7, Activity.recent(limit: 100_000).size
    assert_equal 7, Activity.recent.size
    assert_equal 2, Activity.recent(actor: "nik", since: T0 + 3.minutes, limit: 5).size
  end

  test "a window of the limit's size is drawn across the ledgers, not from one of them" do
    assert_equal [ @link.id, @link.id, @api_reply.comment_id ], Activity.recent(limit: 3).map { |r| r["ref"].values_at("view_link_id", "comment_id").compact.first }
  end

  test "reading the feed writes nothing" do
    tables = %w[decisions comment_events view_links view_link_revocations view_link_redemptions api_tokens api_token_renewals app_events]
    count = -> { tables.map { |t| ActiveRecord::Base.connection.select_value("SELECT COUNT(*) FROM #{t}") } }
    before = count.call
    Activity.recent(actor: "nik")
    Activity.recent(since: T0)
    assert_equal before, count.call
  end
end
