require "test_helper"
require_relative "../support/multi_user"
require_relative "../support/lesson2_page_world"

# D-372, «I miei schemi»: the schema of a topic (the summary card of the lesson revision he is shown, drawn by the lesson/2 renderer; a lesson/1's
# summary) opens when the topic is done, by the course's own meaning (practised, or known from the entry test); before that the page and the list
# say it is closed and carry none of its content. The list groups the open ones by subject and counts the closed ones. The links (Materia, the topic,
# Oggi), the menu, the comment box, the teacher's link and the preview.
class SchemasTest < ActionDispatch::IntegrationTest
  include MultiUser
  include Lesson2PageWorld

  JSON_HEADERS = { "Content-Type" => "application/json", "Accept" => "application/json" }.freeze
  ROOT = "/teacher/preview".freeze
  LOCKED = "Si apre quando finisci l'argomento.".freeze
  SUMMARY_V1 = "Si controlla il risultato.".freeze

  def page(headers, path) = on(:web, path, headers: headers, remote_addr: EDGE)

  def schema_path(topic = TOPIC) = "/topics/#{topic}/schema"

  # The official student has done the topic: three right answers on three days.
  def finish!(topic_revision = @topic_revision, skill = SKILL)
    @clock = Diagnosis::FakeClock.new(Time.current - 20.days)
    play_topic!(topic_revision, skill, 3)
  end

  def served_body_json = JSON.parse(css_select("script#lesson-body").first.text)

  # The entry test says the skills are known: the seeds of the entry diagnosis, as the loader reads them.
  def known(*skills, &block)
    seeds = skills.to_h { |skill| [ skill, Practice::Seed.new(skill: skill, state: "demonstrated", at: Time.current - 5.days, run_id: 1, implied: false) ] }
    Practice::Seeder.stub(:call, seeds, &block)
  end

  def summary_card_number = @lesson_revision.body["cards"].find { |c| c["role"] == "summary" }["n"]

  # ---- the page, closed and open --------------------------------------------------------------------------

  test "a topic that is not done: the page says it is closed and carries nothing of the lesson" do
    build_lesson2_world
    page(OFFICIAL, schema_path)
    assert_response :success
    assert_select "h1", "Schema: Equazioni di primo grado"
    assert_select "#schema-locked[data-state=locked]", /#{Regexp.escape(LOCKED)}/
    assert_select "#schema-practice[href='/topics/#{TOPIC}']", "Esercizi"
    assert_select "#schema-lesson[href='/topics/#{TOPIC}/lesson']", "Rileggi la lezione"
    assert_select "#lesson-root", 0
    assert_select "script#lesson-body", 0
    assert_select "#schema-print", 0
    assert_not_includes response.body, "impossibile", "no word of the summary is in the closed page"
    assert_no_match(/sei indietro/i, response.body)
  end

  test "a topic that is done: the summary card alone, drawn by the lesson renderer, with the links and «Stampa»" do
    build_lesson2_world
    finish!
    page(OFFICIAL, schema_path)
    assert_response :success
    assert_select "h1", "Schema: Equazioni di primo grado"
    assert_select "#schema-locked", 0
    assert_select "#lesson-root[data-controller=lesson2][data-lesson2-schema-value=true][data-lesson2-view-value=cards]"
    assert_select "#lesson-root[data-comment-lesson-revision-id='#{@lesson_revision.id}']"
    assert_select "#schema-lesson[href='/topics/#{TOPIC}/lesson']", "Rileggi la lezione"
    assert_select "#schema-practice[href='/topics/#{TOPIC}']", "Esercizi"
    assert_select "#schema-print[data-action='schema-print#print']", /Stampa/
    body = served_body_json
    assert_equal [ "summary" ], body["cards"].map { |c| c["role"] }, "one card, the summary"
    assert_equal %w[summary schema], body["cards"].first["blocks"].map { |b| b["type"] }
    assert_equal "Equazioni di primo grado intere", body["title_it"]
    assert_equal [], %w[hero parts goals_it why_it book_it] & body.keys, "nothing of the lesson's cover"
    assert_nil JSON.parse(css_select("#lesson-root").first["data-lesson2-urls-value"])["questions"], "no «Non ho capito» on the schema"
    # the renderer's own texts are in the page (the same ones as the lesson's)
    assert_equal "Comincia", JSON.parse(css_select("#lesson-root").first["data-lesson2-labels-value"])["start"]
  end

  test "the schema page is the same summary card the lesson serves, and the lesson's own page is unchanged" do
    build_lesson2_world
    finish!
    page(OFFICIAL, "/topics/#{TOPIC}/lesson")
    in_lesson = served_body_json["cards"].find { |c| c["role"] == "summary" }
    page(OFFICIAL, schema_path)
    assert_equal in_lesson, served_body_json["cards"].first
    page(OFFICIAL, "/topics/#{TOPIC}/lesson")
    assert_equal 13, served_body_json["cards"].size
    assert_select "#lesson-root[data-lesson2-schema-value=true]", 0
  end

  test "a page that records nothing: no event, no card seen, no row" do
    build_lesson2_world
    finish!
    before = [ PracticeEvent.count, LessonEvent.count, AppEvent.count, PracticeServe.count ]
    page(OFFICIAL, schema_path)
    page(OFFICIAL, "/schemas")
    assert_equal before, [ PracticeEvent.count, LessonEvent.count, AppEvent.count, PracticeServe.count ]
  end

  test "a topic known from the entry test is open, and one that is not done or only begun is closed" do
    build_progress_world
    known("math.prog-da-fare") do
      page(OFFICIAL, schema_path(PROGRESS_TODO))
      assert_select "#schema-summary", /#{Regexp.escape(SUMMARY_V1)}/
      assert_select "#schema-locked", 0
      page(OFFICIAL, schema_path(PROGRESS_STARTED))
      assert_select "#schema-locked", /#{Regexp.escape(LOCKED)}/
      page(OFFICIAL, schema_path(PROGRESS_EXTRA_TODO))
      assert_select "#schema-locked"
    end
    page(OFFICIAL, schema_path(PROGRESS_TODO))
    assert_select "#schema-locked", 1, "without the entry test's seed it is closed"
  end

  test "a lesson of the first format shows its summary alone" do
    build_progress_world
    page(OFFICIAL, schema_path(TOPIC))
    assert_response :success
    assert_select "#schema-summary h2", "In sintesi"
    assert_select "#schema-summary [data-lesson-markup]", /Un termine che cambia lato cambia segno\./
    assert_select "#schema-summary [data-lesson-markup]", /#{Regexp.escape(SUMMARY_V1)}/
    assert_select "#lesson-root", 0
    assert_no_match(/Perché ti serve|Le equazioni servono in quasi ogni/, response.body)
    assert_not_includes response.body, SECRET_FINAL
    assert_not_includes response.body, SECRET_SOLUTION
    assert_select "#schema-lesson[href='/topics/#{TOPIC}/lesson']"
    assert_select "#schema-print"
  end

  test "an address the student cannot see is the student's own 404, whatever exists" do
    build_lesson2_world(approve: false)
    page(OFFICIAL, schema_path)
    assert_response :not_found
    page(OFFICIAL, schema_path("ripasso.math.nonesiste"))
    assert_response :not_found
    assert_select "#error-page[data-status=not_found]"
  end

  # ---- another student ------------------------------------------------------------------------------------

  test "the topic is open for the one who finished it and closed for another student" do
    build_lesson2_world
    finish!
    page(OFFICIAL, schema_path)
    assert_select "#lesson-root"
    page(TRIAL, schema_path)
    assert_response :success
    assert_select "#schema-locked", /#{Regexp.escape(LOCKED)}/
    assert_select "#lesson-root", 0
    page(TRIAL, "/schemas")
    assert_select "li.row[data-topic]", 0
    assert_select ".schemas-locked[data-locked='1']"
  end

  test "the teacher and a guest get 403 on both pages" do
    build_lesson2_world
    [ TEACHER, GUEST ].each do |who|
      [ "/schemas", schema_path ].each do |path|
        page(who, path)
        assert_response :forbidden, "#{path} for #{who['Remote-User']}"
      end
    end
  end

  # ---- the list -------------------------------------------------------------------------------------------

  test "the list: the open schemas by subject, the closed ones as a count, and no title of a closed topic" do
    build_progress_world
    page(OFFICIAL, "/schemas")
    assert_response :success
    assert_select "h1", "I miei schemi"
    assert_select "section.schemas-subject[data-subject=math] h2", /#{Regexp.escape(@subject.name_it)}/
    assert_select "section[data-subject=math] li.row", 2
    assert_select "li.row[data-topic='#{TOPIC}'] a.schema-link[href='/topics/#{TOPIC}/schema']", TOPIC_TITLE
    assert_select "li.row[data-topic='#{PROGRESS_EXTRA_DONE}'] a.schema-link[href='/topics/#{PROGRESS_EXTRA_DONE}/schema']", "Percentuali"
    assert_select "section[data-subject=math] .schemas-locked[data-locked='3']", /Ancora chiusi: 3 schemi\. Si aprono quando finisci l'argomento\./
    [ "Frazioni", "Potenze", "Radici" ].each { |title| assert_not_includes response.body, title, "#{title} is not done: only counted" }
    assert_select "#schemas-empty", 0
  end

  test "the list with nothing open says so, and counts one closed schema in the singular" do
    build_lesson2_world
    page(OFFICIAL, "/schemas")
    assert_select "#schemas-empty", "Non c'è ancora nessuno schema. Si apre quando finisci un argomento."
    assert_select ".schemas-locked[data-locked='1']", /Ancora chiuso: 1 schema\./
  end

  test "the list before the release is the closed course, and a student with no course has no menu entry" do
    build_lesson2_world(release: false)
    page(OFFICIAL, "/schemas")
    assert_response :success
    assert_select "#course-closed"
    assert_select "section.schemas-subject", 0
    assert_select "nav.student-menu a#menu-schemas", 0
  end

  # ---- menu and links -------------------------------------------------------------------------------------

  test "the menu has «I miei schemi» after Materie, marked on both pages" do
    build_lesson2_world
    finish!
    page(OFFICIAL, "/today")
    assert_select "nav.student-menu a#menu-schemas[href='/schemas']", "I miei schemi"
    labels = css_select("nav.student-menu a").map(&:text)
    assert_equal labels.index("Materie") + 1, labels.index("I miei schemi")
    [ "/schemas", schema_path ].each do |path|
      page(OFFICIAL, path)
      assert_select "nav.student-menu a[aria-current=page]", "I miei schemi"
    end
  end

  test "Materia and the topic page show «Schema» on a done topic only" do
    build_progress_world
    page(OFFICIAL, "/subjects/math")
    assert_select "li.topic[data-topic='#{TOPIC}'] a.schema-row-link[href='/topics/#{TOPIC}/schema']", /Schema/
    assert_select "li.topic[data-topic='#{PROGRESS_EXTRA_DONE}'] a.schema-row-link"
    [ PROGRESS_STARTED, PROGRESS_TODO, PROGRESS_EXTRA_TODO ].each { |key| assert_select "li.topic[data-topic='#{key}'] a.schema-row-link", 0, key }
    page(OFFICIAL, "/topics/#{TOPIC}")
    assert_select "#schema-link[href='/topics/#{TOPIC}/schema']", /Schema/
    page(OFFICIAL, "/topics/#{PROGRESS_TODO}")
    assert_select "#schema-link", 0
  end

  test "Oggi offers «Ripassa uno schema» only when one is open, and always the same one on the same day" do
    build_progress_world
    page(OFFICIAL, "/today")
    assert_select "#schema-review-title", "Ripassa uno schema"
    href = css_select("#schema-review-link").first["href"]
    assert_includes [ "/topics/#{TOPIC}/schema", "/topics/#{PROGRESS_EXTRA_DONE}/schema" ], href
    3.times do
      page(OFFICIAL, "/today")
      assert_equal href, css_select("#schema-review-link").first["href"]
    end
    page(TRIAL, "/today")
    assert_select "#schema-review", 0
  end

  test "the day's schema: the same all day, another over the days, none when nothing is open; no model, no randomness" do
    build_progress_world
    schemas = Course::Schemas.new(Course::StudentView.new(@official))
    day = Date.new(2026, 11, 19)
    pick = schemas.daily_pick("student", on: day)
    assert_equal pick.topic.key, schemas.daily_pick("student", on: day).topic.key
    drawn = (0..30).map { |i| schemas.daily_pick("student", on: day + i).topic.key }.uniq
    assert_equal [ TOPIC, PROGRESS_EXTRA_DONE ].sort, drawn.sort, "over a month both open schemas come up"
    assert_nil Course::Schemas.new(Course::StudentView.new(@trial)).daily_pick("prova-1", on: day)
  end

  # ---- the preview ----------------------------------------------------------------------------------------

  test "the preview opens the schema as the student sees it, on the preview addresses, and the list too" do
    build_lesson2_world
    page(TEACHER, "#{ROOT}#{schema_path}")
    assert_response :success
    assert_select "#schema-preview-note", /Anteprima/
    assert_select "#lesson-root[data-lesson2-schema-value=true]"
    assert_select "#schema-lesson[href='#{ROOT}/topics/#{TOPIC}/lesson']"
    assert_select "#schema-practice[href='#{ROOT}/topics/#{TOPIC}']"
    assert_select "a.back[href='#{ROOT}/schemas']"
    assert_select "nav.student-menu a#menu-schemas[href='#{ROOT}/schemas']"
    assert_equal [ "summary" ], served_body_json["cards"].map { |c| c["role"] }
    assert_equal "#{ROOT}/preferences", JSON.parse(css_select("#lesson-root").first["data-lesson2-urls-value"])["preferences"]
    page(TEACHER, "#{ROOT}/schemas")
    assert_response :success
    assert_select "li.row[data-topic='#{TOPIC}'] a.schema-link[href='#{ROOT}#{schema_path}']"
    assert_select "#comment-root", 0, "the preview writes no comment"
  end

  test "the preview writes nothing and the student's own schema page is not the preview's" do
    build_lesson2_world
    before = [ Decision.count, LessonEvent.count, PracticeServe.count, AppEvent.count, Comment.count ]
    page(TEACHER, "#{ROOT}#{schema_path}")
    page(TEACHER, "#{ROOT}/schemas")
    assert_equal before, [ Decision.count, LessonEvent.count, PracticeServe.count, AppEvent.count, Comment.count ]
    page(TEACHER, schema_path)
    assert_response :forbidden
  end

  # ---- comments -------------------------------------------------------------------------------------------

  def token_for(headers, path = "/today")
    page(headers, path)
    css_select("meta[name=csrf-token]").first&.[]("content").to_s
  end

  def post_comment(headers, **over)
    token = token_for(headers)
    body = { client_comment_id: "c-#{SecureRandom.hex(8)}", reason: "like", text_it: "Utile.", viewport_width: 390, viewport_height: 800, theme: "cream", text_size: "normal" }.merge(over)
    on(:web, "/comments", method: :post, headers: headers.merge(JSON_HEADERS, "X-CSRF-Token" => token), params: body.to_json, remote_addr: EDGE)
    response.parsed_body
  end

  test "the comment box is on both pages and a comment is filed under the kinds schema and schemas" do
    build_lesson2_world
    finish!
    saved = ActionController::Base.allow_forgery_protection
    ActionController::Base.allow_forgery_protection = true
    [ schema_path, "/schemas" ].each do |path|
      page(OFFICIAL, path)
      assert_select "#comment-root[data-comment-page-path-value='#{path}']"
    end
    assert_equal({ "status" => "recorded" }, post_comment(OFFICIAL, page_path: "/schemas", anchor: nil, refs: {}))
    assert_equal [ "schemas", "/schemas", nil ], Comment.last.then { |c| [ c.page_kind, c.page_path, c.lesson_revision_id ] }
    reply = post_comment(OFFICIAL, page_path: schema_path, anchor: "card:#{summary_card_number}/block:2", refs: { lesson_revision_id: @lesson_revision.id })
    assert_equal({ "status" => "recorded" }, reply)
    comment = Comment.last
    assert_equal [ "schema", schema_path, summary_card_number, @lesson_revision.id, @topic_revision.id, @subject.id ],
                 [ comment.page_kind, comment.page_path, comment.card, comment.lesson_revision_id, comment.topic_revision_id, comment.subject_id ]
    post_comment(OFFICIAL, page_path: schema_path, anchor: nil, refs: { lesson_revision_id: @lesson_revision.id + 99 })
    assert_equal comment.id, Comment.last.id, "a revision he was not shown is refused"
    post_comment(OFFICIAL, page_path: "/topics/ripasso.math.nonesiste/schema", anchor: nil, refs: {})
    assert_equal comment.id, Comment.last.id, "a topic he cannot see is refused"
    post_comment(OFFICIAL, page_path: "/schemas/x", anchor: nil, refs: {})
    assert_equal comment.id, Comment.last.id
  ensure
    ActionController::Base.allow_forgery_protection = saved
  end

  test "the kinds are in the model, the pages and the words of the places" do
    assert_includes Comment::PAGE_KINDS, "schema"
    assert_includes Comment::PAGE_KINDS, "schemas"
    assert_equal [ "schema", TOPIC ], Comments::Pages.parse(schema_path).then { |p| [ p.kind, p.topic ] }
    assert_equal "schemas", Comments::Pages.parse("/schemas").kind
    [ "/schemas/", "/topics/#{TOPIC}/schema/", "/topics/#{TOPIC}/schemas", "/topics/x/schema" ].each { |path| assert_nil Comments::Pages.parse(path), path }
    %w[schema schemas].each do |kind|
      assert I18n.exists?("comments.place.#{kind}", :it)
      assert I18n.exists?("teacher.comments.page.#{kind}", :it)
      assert_includes CommentsHelper::PLACE_ICONS, kind
    end
  end
end
