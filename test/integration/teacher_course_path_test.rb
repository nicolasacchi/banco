require "test_helper"
require_relative "../support/decision_world"
require_relative "../support/multi_user"
require_relative "../support/course_path_world"

# D-240: the course page is the path of the subject, the topic page a guided review in four steps. Presentation and
# the "seen" records only: the decisions and the gate are the ones of D-237.
class TeacherCoursePathTest < ActionDispatch::IntegrationTest
  include DecisionWorld
  include MultiUser
  include CoursePathWorld

  setup do
    ENV["BANCO_TEACHER_USERS"] = "nik,teacher-a@example.test"
    ENV["BANCO_GUEST_USERS"] = "guest-a@example.test"
    build_course_path_world
    @major = path_finding!(@ready_items.first)
  end

  def course_page(query = "", headers: TEACHER) = on(:web, "/teacher/subjects/math/course#{query}", headers: headers, remote_addr: EDGE)

  def topic_page(key = CoursePathWorld::READY, headers: TEACHER) = on(:web, "/teacher/subjects/math/topics/#{key}", headers: headers, remote_addr: EDGE)

  def mark_seen(part, item: nil, revision: @ready, headers: TEACHER)
    token = csrf_token(headers: headers)
    on(:web, "/teacher/topic-revisions/#{revision.id}/seen", method: :post, remote_addr: EDGE, params: { part: part, item_revision_id: item&.id }.compact.to_json,
                                                              headers: headers.merge("X-CSRF-Token" => token, "Content-Type" => "application/json", "Accept" => "application/json"))
  end

  def read_everything!
    mark_seen("lesson")
    @ready_items.each { |item| mark_seen("exercise", item: item) }
  end

  test "the path lists the topics in course order as numbered steps, each with one plain badge" do
    course_page
    assert_response :success
    keys = css_select("ol.path > li").map { |li| li["data-topic"] }
    assert_equal [ CoursePathWorld::READY, CoursePathWorld::WORKING, CoursePathWorld::MISSING, CoursePathWorld::DONE ], keys
    assert_equal %w[1 2 3 4], css_select("ol.path .step-number").map { |n| n.text.strip }
    badges = css_select("ol.path > li").to_h { |li| [ li["data-topic"], li.at_css("[data-stage-label]").text.strip ] }
    assert_equal "Pronto per te", badges[CoursePathWorld::READY]
    assert_equal "Gli agenti ci lavorano", badges[CoursePathWorld::WORKING]
    assert_equal "Da scrivere", badges[CoursePathWorld::MISSING]
    assert_equal "Approvato", badges[CoursePathWorld::DONE]
    assert_equal 4, css_select("ol.path [data-stage-label]").size, "one badge per topic"
    assert_select "li[data-topic='#{CoursePathWorld::READY}'] ul[data-counts]", /Lezione scritta/
    assert_select "li[data-topic='#{CoursePathWorld::READY}'] [data-count=exercises]", "3 esercizi"
    assert_select "li[data-topic='#{CoursePathWorld::READY}'] [data-count=findings]", "1 rilievo da decidere"
    assert_select "li[data-topic='#{CoursePathWorld::MISSING}'] [data-count=lesson]", /non ancora scritta/
    assert_select "li[data-topic='#{CoursePathWorld::MISSING}'] [data-missing]", /non ha ancora scritto la lezione/
    assert_select "li[data-topic='#{CoursePathWorld::WORKING}'] [data-missing]", /Manca la revisione della lezione/
    assert_select "li[data-topic='#{CoursePathWorld::READY}'] [data-missing]", /Manca solo la tua revisione/
  end

  test "only the ready topics have the primary button, and the skills carry the reference of D-218" do
    course_page
    assert_select "a[data-review-button]", 1
    assert_select "li[data-topic='#{CoursePathWorld::READY}'] a[data-review-button]", "Rivedi e approva"
    assert_select "li[data-topic='#{CoursePathWorld::READY}'] .ref", /math\.number/
  end

  test "the summary line counts ready, approved and missing topics and says whether the course is closed" do
    course_page
    assert_select "#course-summary[data-open=false][data-ready='1']", "1 argomento pronto per te · 1 approvato · 1 da scrivere · corso chiuso a kid-a"
    assert_no_match(/andrea/i, response.body)
  end

  test "without a student map the course says it is closed to the student, never to a name" do
    ENV.delete("BANCO_STUDENT_USERS")
    course_page
    assert_select "#course-summary", /corso chiuso allo studente/
  end

  test "an official login starting with a takes ad" do
    ENV["BANCO_STUDENT_USERS"] = "anna-x=student,trial-x=prova-1"
    course_page
    assert_select "#course-summary", /corso chiuso ad anna-x/
  end

  test "the course summary pluralises topics and approved" do
    course_page
    assert_select "p.hint", /Mappa \d+: 4 argomenti, 1 approvato\./
  end

  test "the practice link is explained and a topic that is not ready has Vedi with a state hint" do
    course_page
    assert_select "#course-practice-note", /risposte, aiuti e abilità/
    assert_select "a[data-look-button]", "Vedi"
    assert_no_match(/Guarda/, response.body)
    assert_select "li[data-topic='#{CoursePathWorld::WORKING}'] [data-look-hint]", "Gli agenti ci stanno lavorando."
    assert_select "li[data-topic='#{CoursePathWorld::DONE}'] [data-look-hint]", "Già approvato."
  end

  test "the topic page and the student's lesson page render the same lesson body" do
    approve_path_topic!(@ready, CoursePathWorld::READY)
    open_course!
    topic_page
    assert_response :success
    teacher_body = body_outline(css_select("#lesson-text"))
    on(:web, "/topics/#{CoursePathWorld::READY}/lesson", headers: OFFICIAL, remote_addr: EDGE)
    assert_response :success
    student_body = body_outline(css_select("main.lesson"))
    assert_operator teacher_body[:headings].size, :>=, 7
    assert_equal student_body, teacher_body
  end

  def body_outline(roots)
    root = roots.first
    {
      headings: root.css("h2").map { |h| [ h["id"], h.text.strip ] },
      sections: root.css("section[id^=section-]").map { |n| [ n["id"], n["data-section"], n["aria-labelledby"] ] },
      markup: root.css(".markup[data-lesson-markup]:not(.exercise-solution)").size,
      exercises: root.css("ol.exercises li.exercise").map { |li| [ li["id"], li["data-exercise"] ] }
    }
  end

  test "the topic page shows one sample open per exercise, the other three folded, and a link to the approval step" do
    topic_page
    assert_select "#review-progress a#go-approve[href='#step-approve']", "Vai ad Approva"
    card = ".exercise-card[data-exercise-card='#{@ready_items.first.id}']"
    assert_select "#{card} > .samples-render .sample-render", 1
    assert_select "#{card} details.other-samples[data-more=samples] > summary", "Altri 3 esempi"
    assert_select "#{card} details.other-samples:not([open]) .sample-render", 3
    assert_select "#{card} details[data-more=hints]:not([open])"
    assert_select "#{card} details[data-more=solution]:not([open])"
  end

  test "the filter keeps the topics that wait for the teacher" do
    course_page
    assert_select "#path-filter[data-active=false]", "Solo quelli pronti per te"
    course_page("?only=ready")
    assert_equal [ CoursePathWorld::READY ], css_select("ol.path > li").map { |li| li["data-topic"] }
    assert_select "#path-filter[data-active=true]", "Mostra tutti gli argomenti"
    dispose_finding!(@major)
    read_ready_topic_approved!
    course_page("?only=ready")
    assert_select "#path-empty", "Nessun argomento è pronto per te."
  end

  def read_ready_topic_approved! = approve_path_topic!(@ready, CoursePathWorld::READY)

  test "progress: the trial students while the course is closed, the official student once it is released" do
    practice_on_ready!
    course_page
    assert_select "li[data-topic='#{CoursePathWorld::READY}'] [data-progress=prova-1]", "Prova: trial-x: 1 risposta, nessuna abilità su 1 dimostrata."
    assert_select "[data-progress=student]", 0
    open_course!
    course_page
    assert_select "#course-summary[data-open=true]", /corso aperto a kid-a/
    assert_select "li[data-topic='#{CoursePathWorld::READY}'] [data-progress=student]", /Ufficiale: 2 risposte, nessuna abilità su 1 dimostrata\./
    assert_select "[data-progress=prova-1]", 0
    assert_select "li[data-topic='#{CoursePathWorld::DONE}'] [data-badge-name=open]", "Aperto allo studente"
  end

  test "the release block says what opening needs, what is done, and that trial students see drafts" do
    course_page
    assert_select "#course-release [data-check=graph][data-done=false]", /La mappa poggia sul grafo che hai approvato\. da fare/
    assert_select "#course-release [data-check=topic][data-done=true]", /Almeno un argomento è approvato\. fatto/
    assert_select "#trial-note", /Gli studenti di prova vedono già le bozze/
    assert_select "#course-open-form button[disabled]"
    approve_graph_row!(@subject, @graph)
    course_page
    assert_select "#course-release [data-check=graph][data-done=true]"
    assert_select "#course-open-form button:not([disabled])"
  end

  test "the topic page is four steps with a progress bar, none done at first" do
    topic_page
    assert_response :success
    assert_select "#review-progress progress[max='4'][value='0']"
    %w[lesson exercises findings approve].each_with_index do |name, i|
      assert_select "#review-progress a[href='#step-#{name}']", /#{i + 1}/
      assert_select "section#step-#{name}[data-step=#{name}]"
    end
    assert_select "#step-lesson[data-done=false] [data-step-state]", "Da fare"
    assert_select "#step-exercises[data-done=false]"
    assert_select "#step-findings[data-done=false] [data-step-state]", "Da fare"
  end

  test "step one draws the lesson with the student's markup and the review beside it" do
    topic_page
    assert_select "#step-lesson .step-grid #lesson-text .markup[data-lesson-markup]", minimum: 6
    assert_select "#lesson-text #section-idea h2", "L'idea in breve"
    assert_select "#lesson-text ol.exercises li.exercise .exercise-solution[data-solution]", 2
    assert_select "#step-lesson aside.lesson-review ul[data-checklist] li", 8
    assert_select "#step-lesson aside.lesson-review", /Calcoli rifatti dal revisore: 1/
    assert_select "main[data-controller~=lesson-preview]"
    assert_select "#read-lesson", "Ho letto la lezione"
  end

  test "step two has one card per exercise in level order with four instances, hints, messages, solution and the review outcome" do
    topic_page
    cards = css_select(".exercise-card")
    assert_equal [ "1", "2", "3" ], cards.map { |c| c["data-level"] }
    assert_equal @ready_items.map { |r| r.id.to_s }, cards.map { |c| c["data-exercise-card"] }
    assert_select ".exercise-card", 3 do
      assert_select "[data-presentation]", minimum: 4
    end
    card = ".exercise-card[data-exercise-card='#{@ready_items.first.id}']"
    assert_select "#{card} [data-presentation]", 4
    assert_select "#{card} .sample-render", 4
    assert_select "#{card} [data-purpose]", /Allena .*Errori tipici previsti: 1/
    assert_select "#{card} .badge[data-seen-label]", "Da vedere"
    assert_select "#{card} details[data-more=hints] ol[data-hints] li", 12
    assert_select "#{card} details[data-more=errors]", /Hai sbagliato un segno/
    assert_select "#{card} details[data-more=solution] ol.steps li"
    assert_select "#{card} details[data-more=review] [data-blind=ok]"
    assert_select "#{card} a[data-play='#{@ready_items.first.id}'][href*='topic=#{CoursePathWorld::READY}']", "Prova questo esercizio come S"
    presentation = JSON.parse(css_select("#{card} [data-presentation]").first["data-presentation"])
    assert_equal JSON.parse(Teacher::StoredPresentation.call(@ready_items.first.instances.order(:id).first, @ready_items.first).to_json), presentation
  end

  test "the item play page goes back to the topic" do
    on(:web, "/teacher/items/#{@ready_items.first.id}/play?topic=#{CoursePathWorld::READY}", headers: TEACHER, remote_addr: EDGE)
    assert_response :success
    assert_select "a[href='/teacher/subjects/math/topics/#{CoursePathWorld::READY}']"
  end

  test "step three reuses the finding card with the opinions and folds the minor ones" do
    path_finding!(@ready_items[1], severity: "minor", opinions: [ "author_right" ])
    topic_page
    assert_select "#step-findings .finding[data-severity=major][data-finding='#{@major.id}']" do
      assert_select ".opinions[data-opinion-state]"
      assert_select "[data-opinion=first]", /ha ragione il rilievo/
      assert_select "button[data-follow=finding_right]", "Segui il parere"
    end
    assert_select "#step-findings details.minor-findings[data-minor-findings='1']"
    assert_select "#step-findings [data-lesson-finding][data-severity=minor]", /Frase lunga/
  end

  test "step three is done when nothing blocks" do
    dispose_finding!(@major)
    topic_page
    assert_select "#step-findings[data-done=true] [data-step-state]", "Fatto"
  end

  test "the approve button is closed with the reason until the lesson is read and every exercise seen" do
    dispose_finding!(@major)
    topic_page
    assert_select "#topic-approve-button[disabled]"
    assert_select "#step-approve [data-need=lesson]", /Ho letto la lezione/
    assert_select "#step-approve [data-need=exercises]"
    assert_select "#approve-checks [data-check=read_lesson][data-done=false]"
    mark_seen("lesson")
    assert_response :success
    @ready_items.first(2).each { |item| mark_seen("exercise", item: item) }
    topic_page
    assert_select "#review-progress progress[value='2']"
    assert_select "#step-lesson[data-done=true] [data-step-state]", "Fatto"
    assert_select "#topic-approve-button[disabled]"
    mark_seen("exercise", item: @ready_items.last)
    topic_page
    assert_select "#step-exercises[data-done=true]"
    assert_select "#topic-approve-button:not([disabled])"
    assert_select "#approve-checks [data-done=false]", 0
    assert_select ".exercise-card[data-seen=true]", 3
  end

  test "the approve button stays closed while the gate says no, with its reasons ticked off in the checklist" do
    read_everything!
    topic_page
    assert_select "#topic-approve-button[disabled]"
    assert_select "#approve-checks [data-check=exercises][data-done=false]", /1 rilievi gravi senza una tua decisione/
    assert_select "#approve-checks [data-check=map][data-done=true]"
    assert_select "#approve-checks [data-check=viewed][data-done=true]"
  end

  test "the seen records are app events, not decisions, idempotent, for pinned exercises of the latest revision only" do
    assert_difference "AppEvent.where(kind: 'teacher_read_lesson').count", 1 do
      mark_seen("lesson")
      mark_seen("lesson")
    end
    assert_response :success
    assert_difference "AppEvent.where(kind: 'teacher_saw_exercise').count", 1 do
      2.times { mark_seen("exercise", item: @ready_items.first) }
    end
    assert_no_difference "AppEvent.count" do
      mark_seen("exercise", item: @working_items.first)
      assert_response :not_found
      mark_seen("nonsense")
      assert_response :unprocessable_entity
    end
    assert_no_difference "Decision.count" do
      mark_seen("lesson")
    end
    newer = make_topic(@ready_lesson, { "math.number" => @ready_items }, course: @course)
    assert_no_difference "AppEvent.count" do
      mark_seen("lesson", revision: @ready)
      assert_response :conflict
    end
    assert_equal newer.seq, @ready.seq + 1
  end

  test "approving needs no seen record from the gate: the gate is the one of D-237" do
    dispose_finding!(@major)
    topic_page
    assert Approval::TopicGate.check(@ready, confirm_seen: true).approvable
    decide("/teacher/topic-revisions/#{@ready.id}/approve", { confirm_seen: "1" })
    assert_response :success
    assert_equal 1, Decision.where(kind: "approve_topic", subject: @subject).where("payload_json LIKE ?", "%#{CoursePathWorld::READY}%").count
  end

  test "after approving, the page links to the next topic ready for the teacher, or says there is none" do
    dispose_finding!(@major)
    approve_path_topic!(@ready, CoursePathWorld::READY)
    topic_page
    assert_select "#next-topic [data-next=none]", /Nessun altro argomento da approvare/
    # a second topic becomes ready
    lesson = path_lesson!("ripasso.math.more-numbers", "math.number", reviewed: true)
    course = build_course_map(subject: @subject, topics: CoursePathWorld::PATH_TOPICS + [ { key: "ripasso.math.more-numbers", kind: "ripasso", title_it: "Ancora numeri", skills: [ "math.number" ], minutes: 20, term: 1, after: [] } ])
    items = [ path_item!("more-numbers-1", "math.number", 1) ]
    other = make_topic(lesson, { "math.number" => items }, course: course)
    assert_equal course.id, other.course_revision_id
    topic_page
    assert_select "#next-topic [data-next='ripasso.math.more-numbers'] a[href$='/topics/ripasso.math.more-numbers']", "Ancora numeri"
  end

  test "a guest reads the same pages without buttons and writes nothing" do
    assert_no_difference [ "AppEvent.count", "Decision.count" ] do
      topic_page(headers: GUEST)
      assert_response :success
      assert_select "#read-lesson", 0
      assert_select "[data-seen-button]", 0
      assert_select "form.decide", 0
      assert_select "#guided-review[data-topic-review-writable-value=false]"
      assert_select "#topic-approve-button[disabled]", 0, "no approve form is drawn for a guest"
      assert_select ".exercise-card [data-presentation]", minimum: 4
      course_page(headers: GUEST)
      assert_response :success
      assert_select "a[data-review-button]", 1
      assert_select "form.decide", 0
      mark_seen("lesson", headers: GUEST)
      assert_response :forbidden
    end
  end

  test "the student's computer reads but does not record what it saw" do
    topic_page(headers: TEACHER)
    token = csrf_token
    cookies[DecisionRecorder::DEVICE_COOKIE] = "1"
    assert_no_difference "AppEvent.where(kind: 'teacher_read_lesson').count" do
      on(:web, "/teacher/topic-revisions/#{@ready.id}/seen", method: :post, remote_addr: EDGE, params: { part: "lesson" }.to_json,
                                                              headers: TEACHER.merge("X-CSRF-Token" => token, "Content-Type" => "application/json", "Accept" => "application/json"))
    end
    assert_response :forbidden
  end

  test "a topic that is not written yet has no review page and the path says so" do
    topic_page(CoursePathWorld::MISSING)
    assert_response :not_found
  end
end
