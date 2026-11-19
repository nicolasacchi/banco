require "test_helper"
require_relative "../support/decision_world"
require_relative "../support/multi_user"
require_relative "../support/topic_world"
require_relative "../support/practice_rows"

# D-365: «Valutazioni», the teacher's read-only page of what the student thinks of the exercises and lessons: newest first, filters (subject,
# topic, kind), each row with its date, stars, comment, target, revision and who (official or trial), an average and a count per target, and the
# line «Valutazione: 4,2 ★ (5)» on the topic page, the exercises' cards and the lesson, linking to the filtered list. The teacher, a guest and
# a view link read it; the student does not; nothing is written.
class TeacherRatingsTest < ActionDispatch::IntegrationTest
  include DecisionWorld
  include MultiUser
  include TopicWorld
  include PracticeRows

  VIEW_ENV = { "BANCO_VIEW_LINKS_ENABLED" => "1", "BANCO_VIEW_URL" => "https://api.banco.scc.im" }.freeze

  setup do
    @saved_view_env = ENV.to_h.slice(*VIEW_ENV.keys)
    VIEW_ENV.each { |k, v| ENV[k] = v }
    ENV["BANCO_TEACHER_USERS"] = "nik,teacher-a@example.test"
    ENV["BANCO_GUEST_USERS"] = "guest-a@example.test"
    @world = build_ui_subject(approve: false)
    @subject = @world[:subject]
    @graph = SkillGraphRevision.where(subject: @subject).order(:seq).last
    build_topic_world
    @official = Student.official
    @trial = Student.create!(key: "prova-1", kind: "student")
    @item = @topic_items.first
    @key = @item.item.key
    @serve = make_serve(@official, @topic, @item.instances.order(:id).first, skill_key: "math.number")
    @trial_serve = make_serve(@trial, @topic, @item.instances.order(:id).first, skill_key: "math.number")
    @old = rate_item(@official, 2, "Troppo facile.", at: 3.days.ago)
    @new = rate_item(@official, 5, "Mi piace molto.", at: 2.days.ago)
    @lesson = rate_lesson(@official, 3, "Un po' lunga.", at: 1.day.ago)
    @test_row = rate_item(@trial, 1, "PROVA-DELL-ADULTO", at: 1.hour.ago, serve: @trial_serve)
  end

  teardown { VIEW_ENV.each_key { |k| @saved_view_env.key?(k) ? ENV[k] = @saved_view_env[k] : ENV.delete(k) } }

  def rate_item(student, stars, text, at:, serve: @serve)
    Rating.create!(student: student, client_rating_id: "r-#{SecureRandom.hex(6)}", target_kind: "item", target_key: @key, subject: @subject, topic_revision: @topic,
                   item_revision: @item, practice_serve: serve, stars: stars, text_it: text, language: "it", trial: student.trial?, created_at: at)
  end

  def rate_lesson(student, stars, text, at:)
    Rating.create!(student: student, client_rating_id: "r-#{SecureRandom.hex(6)}", target_kind: "lesson", target_key: TopicWorld::TOPIC_KEY, subject: @subject, topic_revision: @topic,
                   lesson_revision: @lesson_revision, stars: stars, text_it: text, language: "it", trial: student.trial?, created_at: at)
  end

  def page(path = "/teacher/ratings", headers: TEACHER) = on(:web, path, headers: headers, remote_addr: EDGE)

  def row_ids = css_select("#ratings-table tbody tr").map { |tr| tr["id"].delete_prefix("rating-").to_i }

  # ---- the page ---------------------------------------------------------------------------------------------

  test "the page lists every rating newest first, with the date, the stars, the words, the target, the revision and who" do
    page
    assert_response :success
    assert_select "h1", "Valutazioni"
    assert_equal [ @test_row.id, @lesson.id, @new.id, @old.id ], row_ids
    assert_select "#rating-#{@new.id}[data-kind=item][data-target=?][data-stars='5'][data-trial=false]", @key do
      assert_select "td", text: "Mi piace molto."
      assert_select ".sr-only", text: "5 stelle su 5"
      assert_select ".rating-stars-it", text: "★★★★★"
      assert_select "td", text: "revisione #{@item.seq}"
      assert_select ".pill", text: "Studente"
      assert_select "td[data-label=Chi] .key", 0 # D-380: the official student is «Studente», never the key «student»
      assert_select ".ref[data-ref-key=?]", @key
    end
    assert_select "#rating-#{@old.id} .rating-stars-it", text: "★★☆☆☆"
    assert_select "#rating-#{@lesson.id}[data-kind=lesson]" do
      assert_select "td", text: "revisione #{@lesson_revision.seq}"
      assert_select "a[href=?]", "/teacher/subjects/math/topics/#{TopicWorld::TOPIC_KEY}", text: "Lezione di prova"
    end
    assert_select "#rating-#{@test_row.id}[data-trial=true]" do
      assert_select ".pill", text: "Prova"
      assert_select "td", text: "PROVA-DELL-ADULTO"
    end
  end

  test "an average and a count per target: the student's latest stars only, a trial student never counts" do
    page
    assert_select "#ratings-targets tbody tr", 2
    assert_select "#ratings-targets tr[data-kind=item][data-target=?]", @key do
      assert_select "td[data-average='5.0']", text: "5,0 ★ (1)"
      assert_select "td[data-label=Valutazioni]", text: "3", count: 1
    end
    assert_select "#ratings-targets tr[data-kind=lesson] td[data-average='3.0']", text: "3,0 ★ (1)"
    assert_select "#ratings-summary", "Media: 4,0 ★ (2)."
    assert_select "#ratings-total[data-total='4']", /Valutazioni: 4\./
  end

  test "the filters: subject, topic, kind and one target; an unknown value leaves the filter out" do
    page("/teacher/ratings?kind=lesson")
    assert_equal [ @lesson.id ], row_ids
    assert_select "#ratings-kind option[selected][value=lesson]"
    page("/teacher/ratings?kind=item")
    assert_equal [ @test_row.id, @new.id, @old.id ], row_ids
    page("/teacher/ratings?topic=#{TopicWorld::TOPIC_KEY}&subject=math")
    assert_equal [ @test_row.id, @lesson.id, @new.id, @old.id ], row_ids
    assert_select "#ratings-topic option[selected][value=?]", TopicWorld::TOPIC_KEY
    page("/teacher/ratings?target=#{TopicWorld::TOPIC_KEY}")
    assert_equal [ @lesson.id ], row_ids
    assert_select "#ratings-target-note"
    page("/teacher/ratings?topic=ripasso.math.altro")
    assert_select "#ratings-empty", /Nessuna valutazione con questi filtri/
    page("/teacher/ratings?kind=page&subject=nonesiste")
    assert_equal [ @test_row.id, @lesson.id, @new.id, @old.id ], row_ids
    page("/teacher/ratings")
    assert_select "#ratings-filters-clear", 0
    page("/teacher/ratings?kind=item")
    assert_select "#ratings-filters-clear"
  end

  test "no ratings: an empty page, not an error" do
    page("/teacher/ratings?target=nessuno")
    assert_response :success
    assert_select "#ratings-empty"
    assert_select "#ratings-table", 0
  end

  test "the menu has the entry and marks it on the page" do
    page("/teacher")
    assert_select "#teacher-menu a#menu-ratings[href=?]", "/teacher/ratings", text: "Valutazioni"
    page
    assert_select "#teacher-menu a#menu-ratings[aria-current=page]"
    assert_select "#teacher-menu [aria-current]", 1
  end

  # ---- who reads it -----------------------------------------------------------------------------------------

  test "a guest reads the page and the rows; the student, an unmapped login and nobody do not" do
    page(headers: GUEST)
    assert_response :success
    assert_select "#read-only-notice"
    assert_equal 4, row_ids.size
    assert_includes response.body, "Mi piace molto."
    page(headers: OFFICIAL)
    assert_response :forbidden
    assert_not_includes response.body, "Mi piace molto."
    page(headers: UNMAPPED)
    assert_response :forbidden
    page(headers: {})
    assert_response :forbidden
  end

  test "a view link on /teacher/ratings opens the page on the view listener, read-only" do
    raw = ApiToken.issue!(role: "bot_read", label: "view ratings", expires_at: 30.days.from_now)
    token = ApiToken.find_by!(public_id: Banco::TokenAuth::FORMAT.match(raw)[1])
    _, secret = ViewLinks.create!(token: token, path: "/teacher/ratings?kind=item", minutes: 30)
    on(:view, "/v?view_token=#{secret}", remote_addr: EDGE)
    assert_response :see_other
    assert_equal "/teacher/ratings?kind=item", URI(response.location).request_uri
    on(:view, "/teacher/ratings?kind=item", remote_addr: EDGE)
    assert_response :success
    assert_equal [ @test_row.id, @new.id, @old.id ], row_ids
    assert_includes response.body, "Mi piace molto."
    assert_no_difference [ "Rating.count", "Decision.count" ] do
      on(:view, "/teacher/ratings", method: :post, remote_addr: EDGE)
      assert_response :forbidden
    end
  end

  test "reading the page writes nothing" do
    assert_no_difference [ "Rating.count", "AppEvent.count", "Decision.count", "Student.count" ] do
      page
      page(headers: GUEST)
    end
  end

  # ---- the line «Valutazione: 4,2 ★ (5)» --------------------------------------------------------------------

  test "the topic page says the stars of the lesson, of each exercise and of the topic, each linking to the filtered list" do
    open_topic_page!(headers: TEACHER)
    assert_response :success
    assert_select "#topic-rating a.rating-line[href=?]", "/teacher/ratings?topic=#{TopicWorld::TOPIC_KEY}", text: "Valutazione: 4,0 ★ (2)"
    assert_select "#lesson-rating a.rating-line[href=?]", "/teacher/ratings?kind=lesson&target=#{TopicWorld::TOPIC_KEY}", text: "Valutazione: 3,0 ★ (1)"
    assert_select "[data-exercise-card='#{@item.id}'] [data-item-rating] a[href=?]", "/teacher/ratings?kind=item&target=#{@key}", text: "Valutazione: 5,0 ★ (1)"
    assert_select "[data-exercise-card='#{@topic_items.last.id}'] [data-item-rating]", 0, "an exercise nobody rated has no line"
    open_topic_page!(headers: GUEST)
    assert_select "#topic-rating a.rating-line", text: "Valutazione: 4,0 ★ (2)"
  end

  test "the item card of the entry test's skill screen has the line too" do
    revision = @world[:revisions]["number"]
    serve = make_serve(@official, @topic, revision.instances.order(:id).first, skill_key: "math.number")
    Rating.create!(student: @official, client_rating_id: "r-#{SecureRandom.hex(6)}", target_kind: "item", target_key: revision.item.key, subject: @subject, topic_revision: @topic,
                   item_revision: revision, practice_serve: serve, stars: 4, language: "it", trial: false, created_at: Time.current)
    page("/teacher/subjects/math/test/skills/math.number")
    assert_response :success
    assert_select "article.item-card[data-item=?] [data-item-rating] a[href=?]", revision.item.key, "/teacher/ratings?kind=item&target=#{revision.item.key}", text: "Valutazione: 4,0 ★ (1)"
  end
end
