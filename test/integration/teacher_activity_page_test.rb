require "test_helper"
require_relative "../support/multi_user"
require_relative "../support/decision_world"

# D-334: «Chi ha fatto che cosa», the teachers' read-only page of the actions of the teachers and the bots. Only a teacher
# reads it (it names the teachers' logins and the bots' labels): a guest and a view link get 403 and no menu entry. The page
# records nothing and shows no word of the student or of a reply.
class TeacherActivityPageTest < ActionDispatch::IntegrationTest
  include MultiUser
  include DecisionWorld

  SILVIA = "silvia@scc.im".freeze
  SILVIA_HEADERS = { "Remote-User" => SILVIA, "Remote-Groups" => "banco-teacher" }.freeze

  setup do
    ENV["BANCO_TEACHER_USERS"] = "nik,#{SILVIA}"
    build_decision_world
    ApiToken.issue!(role: "teacher", label: "teacher-silvia-bot-2026-11-15", expires_at: 30.days.from_now, teacher_login: SILVIA)
    ApiToken.issue!(role: "bot_read", label: "reader-bot", expires_at: 30.days.from_now)
    @silvia = ApiToken.find_by!(label: "teacher-silvia-bot-2026-11-15")
    @reader = ApiToken.find_by!(label: "reader-bot")
    @comment = Comment.create!(student: @student, client_comment_id: "c-#{SecureRandom.hex(6)}", reason: "error", text_it: "PAROLA-SEGRETA-DELLO-STUDENTE", page_path: "/today",
                               page_kind: "today", subject: @subject, created_at: 10.minutes.ago)
    ledger_rows
  end

  def ledger_rows
    Decision.create!(kind: "set_formula_sheet", subject: @subject, payload_json: { subject: "math", enabled: false }.to_json, request_id: SecureRandom.uuid,
                     teacher_login: "nik", groups: "banco-teacher", remote_addr: EDGE, created_at: 5.minutes.ago)
    Decision.create!(kind: "set_formula_sheet", subject: @subject, payload_json: { subject: "math", enabled: false, via: "api", token: @silvia.public_id }.to_json,
                     request_id: SecureRandom.uuid, teacher_login: SILVIA, groups: "api", remote_addr: "127.0.0.1", created_at: 4.minutes.ago)
    Decision.create!(kind: "kind_override", subject: @subject, payload_json: { skill: "math.number", kind: "learn", via: "console" }.to_json,
                     request_id: SecureRandom.uuid, teacher_login: "nik", groups: "console", remote_addr: "console", created_at: 3.minutes.ago)
    CommentEvent.create!(comment: @comment, kind: "reply", origin: "api", actor: SILVIA, text_it: "RISPOSTA-SEGRETA-DEL-BOT", request_id: SecureRandom.uuid,
                         payload_json: { token: @silvia.public_id }.to_json, created_at: 2.minutes.ago)
    ViewLink.create!(api_token: @reader, token_digest: Digest::SHA256.hexdigest("raw"), path: "/teacher", expires_at: 59.minutes.from_now, created_at: 1.minute.ago)
  end

  def page(headers = TEACHER) = on(:web, "/teacher/activity", headers: headers, remote_addr: EDGE)

  def table_rows = css_select("#activity-table tbody tr").map { |tr| tr.css("td").map { |td| td.text.squish } }

  def check_rows
    assert_response :success
    assert_select "h1", "Chi ha fatto che cosa"
    assert_select "#activity-table thead th", count: 4
    %w[Quando Chi Come].each { |label| assert_select "#activity-table thead th", text: label }
    assert_select "#activity-table thead th", text: "Che cosa"
    rows = table_rows
    assert_equal 5, rows.size
    assert_equal [ "bot_read:reader-bot", "bot «reader-bot»" ], rows[0].values_at(1, 2)
    assert_match(/\ACreato il link di sola lettura \d+ \(\/teacher, 60 minuti\)\z/, rows[0][3])
    assert_equal [ SILVIA, "bot «teacher-silvia-bot-2026-11-15»", "Risposta al commento #{@comment.id} (Matematica)" ], rows[1].values_at(1, 2, 3)
    assert_equal [ "nik", "console", "Cambiato il tipo di un'abilità (Matematica)" ], rows[2].values_at(1, 2, 3)
    assert_equal [ SILVIA, "bot «teacher-silvia-bot-2026-11-15»", "Spento il formulario (Matematica)" ], rows[3].values_at(1, 2, 3)
    assert_equal [ "nik", "browser", "Spento il formulario (Matematica)" ], rows[4].values_at(1, 2, 3)
    %w[PAROLA-SEGRETA-DELLO-STUDENTE RISPOSTA-SEGRETA-DEL-BOT].each { |secret| assert_not_includes response.body, secret }
  end

  test "the teacher sees who did what, newest first, and the menu links to the page" do
    page
    check_rows
    assert_select "nav#teacher-menu a#menu-activity[href=?][aria-current=page]", "/teacher/activity", text: "Chi ha fatto che cosa"
    assert_select "#teacher-menu [aria-current]", 1
  end

  test "another teacher reads the same rows" do
    page(SILVIA_HEADERS)
    check_rows
    assert_select "nav#teacher-menu a#menu-activity", text: "Chi ha fatto che cosa"
  end

  def assert_forbidden_page
    assert_response :forbidden
    assert_select "#error-page[data-status=forbidden]"
    assert_select "#activity-table", 0
    %w[teacher-silvia-bot-2026-11-15 reader-bot].each { |secret| assert_not_includes response.body, secret }
    assert_not_includes response.body, SILVIA
  end

  test "a guest gets the 403 page, and the guest's teacher pages have no menu link to it" do
    page(GUEST)
    assert_forbidden_page
    on(:web, "/teacher", headers: GUEST, remote_addr: EDGE)
    assert_response :success
    assert_select "nav#teacher-menu a#menu-activity", 0
    assert_select "nav#teacher-menu a[href=?]", "/teacher/activity", 0
  end

  test "a view link's session gets the 403 page and no menu link" do
    saved = ENV.to_h.slice("BANCO_VIEW_LINKS_ENABLED", "BANCO_VIEW_URL")
    ENV["BANCO_VIEW_LINKS_ENABLED"] = "1"
    ENV["BANCO_VIEW_URL"] = "https://api.banco.scc.im"
    _, raw = ViewLinks.create!(token: @reader, path: "/teacher", minutes: 60)
    on(:view, "/v?view_token=#{raw}", remote_addr: EDGE)
    assert_response :see_other
    on(:view, "/teacher/activity", remote_addr: EDGE)
    assert_forbidden_page
    on(:view, "/teacher", remote_addr: EDGE)
    assert_response :success
    assert_select "nav#teacher-menu a[href=?]", "/teacher/activity", 0
  ensure
    %w[BANCO_VIEW_LINKS_ENABLED BANCO_VIEW_URL].each { |k| saved.key?(k) ? ENV[k] = saved[k] : ENV.delete(k) }
  end

  test "the menu of the other teacher pages links to it" do
    on(:web, "/teacher", headers: TEACHER, remote_addr: EDGE)
    assert_response :success
    assert_select "nav#teacher-menu a#menu-activity[href=?]", "/teacher/activity"
    assert_select "#teacher-menu a#menu-activity[aria-current]", 0
  end

  test "with nothing recorded the page says so" do
    Activity.stub(:recent, []) { page }
    assert_response :success
    assert_select "#activity-empty", /Nessuna azione registrata/
    assert_select "#activity-table", 0
  end

  test "reading the page records nothing, and no heartbeat unit is set" do
    tables = ActiveRecord::Base.connection.tables - %w[sqlite_sequence ar_internal_metadata]
    count = -> { tables.to_h { |t| [ t, ActiveRecord::Base.connection.select_value("SELECT COUNT(*) FROM #{t}") ] } }
    before = count.call
    page
    page(GUEST)
    assert_response :forbidden
    assert_equal before, count.call
    assert_select "body[data-activity-unit-value]", 0
  end
end
