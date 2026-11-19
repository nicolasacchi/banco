require "test_helper"
require_relative "../support/multi_user"
require_relative "../support/changelog_world"

# D-375, «Novità»: the student's page (the three sources, newest first, in Italian and English, never the teacher's reason), the visit recorded as the app
# event `changelog_viewed`, the dot on the menu entry, the teacher's preview that records nothing, the teacher's page and the guest's, and who is refused.
class ChangelogPagesTest < ActionDispatch::IntegrationTest
  include MultiUser
  include ChangelogWorld

  REASON = "SEGRETO-DEL-DOCENTE: la correzione cambia il segno.".freeze
  ROOT = "/teacher/preview".freeze

  setup do
    build_student_world
    @row = Student.find_by!(key: "student")
  end

  def page(headers, path) = on(:web, path, headers: headers, remote_addr: EDGE)

  def visits(student = @row) = AppEvent.where(kind: "changelog_viewed", student_id: student.id)

  def entry_ids = css_select("#changelog-entries li[data-entry]").map { |li| li["data-entry"] }

  def english! = Diagnosis::Preferences.record(@row, language: "en")

  # A file of entries with one dated after the student's account began, so that something is new to him.
  def with_new_entry(date)
    Dir.mktmpdir do |dir|
      path = File.join(dir, "changelog.yml")
      File.write(path, <<~YAML)
        entries:
          - {id: brand-new-entry, date: #{date.iso8601}, audience: [student], kind: software, title_it: "Una cosa nuova", body_it: "Prova.", title_en: "Something new", body_en: "A test."}
      YAML
      saved = Changelog::Entries.path
      Changelog::Entries.path = path
      Changelog::Entries.reset!
      yield
    ensure
      Changelog::Entries.path = saved
      Changelog::Entries.reset!
    end
  end

  # ---- the student's page ----------------------------------------------------------------------------------

  test "the page lists the entries for the student newest first, with the day, the kind and what is new" do
    page(OFFICIAL, "/novita")
    assert_response :success
    assert_select "h1", "Novità"
    assert_select "#topbar-title", "Novità"
    assert_equal Changelog::Entries.for(:student).map(&:id), entry_ids
    assert_select "#changelog-entries li[data-entry=my-schemas]" do
      assert_select "h3", "I miei schemi"
      assert_select "time[datetime='2026-11-19']", "19 novembre 2026"
      assert_select ".pill", "App"
      assert_select "a.button[href='/schemas']", "Vai alla pagina"
    end
    assert_select "#changelog-entries li[data-entry=whole-sentence-answers] .pill", text: "Abbiamo corretto"
    assert_select "#changelog-entries li[data-entry=teacher-grading-review]", 0
    assert_select "#changelog-empty", 0
  end

  test "no decision number, no teacher-only entry and nothing from the ledger's reasons reach the student" do
    revise!(lesson_findings_reason_it: REASON)
    page(OFFICIAL, "/novita")
    assert_response :success
    assert_no_match(/D-\d{3}/, response.body)
    assert_not_includes response.body, "SEGRETO-DEL-DOCENTE"
    assert_not_includes response.body, "approve_topic"
    Changelog::Entries.for(:teacher).reject(&:student?).each { |entry| assert_not_includes response.body, entry.title_it }
  end

  test "a topic that was approved again is one line «Aggiornato: <argomento>» with the day and a generic line, linked to the topic" do
    travel_to(Time.zone.local(2026, 11, 19, 9, 30)) { revise!(lesson_findings_reason_it: REASON) }
    page(OFFICIAL, "/novita")
    assert_select "#changelog-updates h3.changelog-day", "19 novembre 2026"
    assert_select "#changelog-updates li[data-topic='#{TOPIC}']" do
      assert_select "h4", /Aggiornato: Equazioni di primo grado/
      assert_select "p", "Esercizi o lezione rivisti."
      assert_select "a[href='/topics/#{TOPIC}']", "Apri l'argomento"
    end
  end

  test "a topic his course does not show is not in the page, and the page has no updates before any topic was approved again" do
    page(OFFICIAL, "/novita")
    assert_select "#changelog-updates", 0
    build_hidden_topic!
    page(OFFICIAL, "/novita")
    assert_select "#changelog-updates", 0
    assert_no_match(/nascosto/, response.body)
  end

  test "«Le tue segnalazioni»: a comment on the topic, then the topic revised, says so, links the thread and never says it was fixed" do
    comment = comment_on(@row, "/topics/#{TOPIC}/lesson", "lesson", at: Time.zone.local(2026, 11, 18, 10, 0), card: 2)
    page(OFFICIAL, "/novita")
    assert_select "#changelog-followups", 0, "nothing was revised after the comment yet"
    travel_to(Time.zone.local(2026, 11, 19, 9, 30)) { revise! }
    page(OFFICIAL, "/novita")
    assert_select "#changelog-followups h2", "Le tue segnalazioni"
    assert_select "#changelog-followups li[data-comment='#{comment.id}']" do
      assert_select "p", /Dopo la tua segnalazione su Lezione: Equazioni di primo grado, scheda 2, l'argomento è stato rivisto il 19 novembre 2026\./
      assert_select "a[href='/comments/#{comment.id}']", "Apri la conversazione"
    end
    assert_no_match(/risolt|corretto il tuo|sistemato/i, css_select("#changelog-followups").text)
  end

  test "the sections come in the order: his own comments, the entries, the updates" do
    comment_on(@row, "/topics/#{TOPIC}", "topic", at: Time.zone.local(2026, 11, 18, 10, 0))
    revise!
    page(OFFICIAL, "/novita")
    assert_equal %w[changelog-followups changelog-entries changelog-updates], css_select("section.changelog-section").map { |s| s["id"] }
  end

  test "in English the interface, the entries' twins and the updates are English; the topic's name stays Italian" do
    english!
    revise!
    page(OFFICIAL, "/novita")
    assert_select "h1", "What's new"
    assert_select "#changelog-entries li[data-entry=my-schemas] h3", "My summaries"
    assert_select "#changelog-entries li[data-entry=my-schemas] time", "19 November 2026"
    assert_select "#changelog-updates h4", /Updated: Equazioni di primo grado/
    assert_select "#changelog-updates p", "Exercises or lesson revised."
    assert_select "html[lang=en]"
    assert_select "#menu-changelog", /What's new/
  end

  test "a trial student reads it too" do
    page(TRIAL, "/novita")
    assert_response :success
    assert_select "h1", "Novità"
  end

  # ---- the visit and the dot ---------------------------------------------------------------------------------

  test "each visit is one append-only app event with how many things were new; the first visit marks what came after the account, the second nothing" do
    revise!
    assert_difference -> { visits.count }, 1 do
      page(OFFICIAL, "/novita")
    end
    event = visits.last
    assert_equal({ "new" => 1 }, JSON.parse(event.payload_json))
    assert_select "#changelog-updates li[data-new=true] .pill", "Nuovo"
    page(OFFICIAL, "/novita")
    assert_equal [ 1, 0 ], visits.order(:id).map { |e| JSON.parse(e.payload_json)["new"] }
    assert_select "[data-new=true]", 0
    assert_equal 2, visits.count
  end

  test "the dot is on the menu entry and on the menu button while something is newer than the last visit, and goes after the visit" do
    page(OFFICIAL, "/today")
    assert_select "#changelog-dot", 0, "nothing came after his account"
    assert_select ".topbar .menu-dot", 0
    revise!
    page(OFFICIAL, "/today")
    assert_select "#menu-changelog #changelog-dot[role=img][aria-label='C\\'è qualcosa di nuovo']", 1
    assert_select ".topbar-menu .menu-dot", 1
    page(OFFICIAL, "/novita")
    assert_select "#changelog-dot", 0, "the page itself shows no dot: he is reading it"
    page(OFFICIAL, "/today")
    assert_select "#changelog-dot", 0
    assert_select ".topbar-menu .menu-dot", 0
    revise!
    page(OFFICIAL, "/today")
    assert_select "#changelog-dot", 1, "a later revision is new again"
  end

  test "an entry dated after his last visit is new too" do
    # the student's account began today; the entry is dated tomorrow and he comes at noon, after it, then comes again
    tomorrow = Date.current + 1
    travel_to(tomorrow.in_time_zone + 12.hours) do
      with_new_entry(tomorrow) do
        page(OFFICIAL, "/today")
        assert_select "#changelog-dot", 1
        page(OFFICIAL, "/novita")
        assert_select "#changelog-entries li[data-entry=brand-new-entry][data-new=true]"
        page(OFFICIAL, "/today")
        assert_select "#changelog-dot", 0
      end
    end
  end

  test "the menu entry is in the menu, marked on its page, and comments can be written on the page" do
    page(OFFICIAL, "/novita")
    assert_select "nav.student-menu a#menu-changelog[href='/novita'][aria-current=page]", /Novità/
    assert_equal "changelog", Comments::Pages.parse("/novita").kind
    comment = comment_on(@row, "/novita", "changelog")
    assert_equal "changelog", comment.reload.page_kind
  end

  # ---- the preview -------------------------------------------------------------------------------------------

  test "the teacher's preview shows the page, with its notice, and records no visit and no dot" do
    revise!
    assert_no_difference [ "AppEvent.count", "Comment.count" ] do
      page(TEACHER, "#{ROOT}/novita")
    end
    assert_response :success
    assert_select "h1", "Novità"
    assert_select "#changelog-preview-note", /nessuna visita/
    assert_select "#changelog-updates li[data-topic='#{TOPIC}']"
    assert_select "[data-new=true]", 0
    assert_select "#changelog-entries a.button[href='#{ROOT}/schemas']"
    assert_select "#changelog-dot", 0
    assert_select "#changelog-followups", 0
    page(TEACHER, "#{ROOT}/today")
    assert_select "#changelog-dot", 0
    assert_select "#menu-changelog[href='#{ROOT}/novita']"
  end

  # ---- who is refused ----------------------------------------------------------------------------------------

  test "a guest and the teacher get 403 on the student's page, and no event" do
    assert_no_difference "AppEvent.count" do
      assert_equal 403, get_as(GUEST, "/novita")
      assert_equal 403, get_as(TEACHER, "/novita")
    end
  end

  # ---- the teacher's page ------------------------------------------------------------------------------------

  test "the teacher's page lists every entry and the topics approved again with the reason, the two revisions and the link to the topic page" do
    second = travel_to(Time.zone.local(2026, 11, 19, 9, 30)) { revise!(lesson_findings_reason_it: REASON) }
    third = travel_to(Time.zone.local(2026, 11, 19, 11, 0)) { revise!(via: "api") }
    page(TEACHER, "/teacher/changelog")
    assert_response :success
    assert_select "h1", "Novità"
    assert_equal Changelog::Entries.all.map(&:id), css_select("#changelog-entries li[data-entry]").map { |li| li["data-entry"] }
    assert_select "#changelog-entries li[data-entry=teacher-grading-review]" do
      assert_select "h3", /Contestazioni/
      assert_select ".changelog-decisions", "Decisioni: D-368"
      assert_select "a.button[href='/teacher/grading']"
    end
    assert_select "#changelog-entries li[data-entry=my-schemas][data-audience=student]"
    assert_select "#changelog-entries li[data-entry=my-schemas] a[href='/teacher/preview/schemas']"
    assert_select "#changelog-entries li[data-entry=privacy-and-account-pages][data-audience='student teacher'] a[href='/privacy']"
    updates = css_select("#changelog-updates li[data-decision]")
    assert_equal 2, updates.size
    assert_includes updates.last.text, "SEGRETO-DEL-DOCENTE", "the older update holds the findings reason"
    assert_select "#changelog-updates li[data-topic='#{TOPIC}']" do |items|
      assert_equal [ "Revisione #{third.id} al posto della #{second.id}", "Revisione #{second.id} al posto della #{@topic_revision.id}" ], items.map { |i| i.css(".update-revisions").text.squish }
      assert_equal [ "Nessun motivo scritto.", "Motivo: #{REASON}" ], items.map { |i| i.css(".update-reason").text.squish }
      assert_equal [ "dal browser", "da un bot" ].sort, items.map { |i| i.css(".changelog-meta span").last.text.squish }.sort
    end
    assert_select "#changelog-updates a[href='/teacher/subjects/math/topics/#{TOPIC}']", "Apri l'argomento"
  end

  test "the teacher's filters: for whom and from which day; a stale value is left out" do
    revise!
    page(TEACHER, "/teacher/changelog?audience=teacher")
    ids = css_select("#changelog-entries li[data-entry]").map { |li| li["data-entry"] }
    assert_equal Changelog::Entries.all.select(&:teacher?).map(&:id), ids
    assert_select "#changelog-audience option[selected][value=teacher]"
    page(TEACHER, "/teacher/changelog?audience=student&since=2026-11-19")
    ids = css_select("#changelog-entries li[data-entry]").map { |li| li["data-entry"] }
    assert_equal Changelog::Entries.all.select { |e| e.student? && e.date >= Date.new(2026, 11, 19) }.map(&:id), ids
    page(TEACHER, "/teacher/changelog?since=2099-01-01")
    assert_select "#changelog-entries-empty"
    assert_select "#changelog-updates-empty"
    page(TEACHER, "/teacher/changelog?audience=parent&since=nonsense")
    assert_response :success
    assert_equal Changelog::Entries.all.size, css_select("#changelog-entries li[data-entry]").size
  end

  test "the teacher has «Novità» in the menu, marked on its page" do
    page(TEACHER, "/teacher/changelog")
    assert_select "#menu-changelog[href='/teacher/changelog'][aria-current=page]", "Novità"
    page(TEACHER, "/teacher")
    assert_select "#menu-changelog[href='/teacher/changelog']"
  end

  test "a guest reads the teacher's page, with no link into the preview; the student does not" do
    revise!(lesson_findings_reason_it: REASON)
    page(GUEST, "/teacher/changelog")
    assert_response :success
    assert_select "#changelog-entries li[data-entry]", minimum: 20
    assert_select "#changelog-entries li[data-entry=my-schemas] a", 0
    assert_select "#changelog-entries li[data-entry=teacher-grading-review] a[href='/teacher/grading']"
    assert_includes response.body, "SEGRETO-DEL-DOCENTE"
    assert_equal 403, get_as(OFFICIAL, "/teacher/changelog")
  end

  test "reading either page writes nothing but the student's own visit" do
    revise!
    assert_no_difference [ "Decision.count", "Comment.count" ] do
      page(TEACHER, "/teacher/changelog")
      page(GUEST, "/teacher/changelog")
    end
    assert_no_difference "AppEvent.count" do
      page(TEACHER, "/teacher/changelog")
    end
  end
end
