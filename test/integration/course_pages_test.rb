require "test_helper"
require_relative "../support/multi_user"
require_relative "../support/student_course_world"

# The student's course pages (A9): who sees what, the pages, and what the browser is told. The official
# student sees nothing until release_course; a trial student sees drafts; readers get 403.
class CoursePagesTest < ActionDispatch::IntegrationTest
  include MultiUser
  include StudentCourseWorld

  JSON_HEADERS = { "Content-Type" => "application/json", "Accept" => "application/json" }.freeze
  PAGES = [ "/today", "/subjects", "/subjects/math", "/topics/#{TOPIC}", "/topics/#{TOPIC}/lesson", "/topics/#{TOPIC}/practice/#{SKILL}" ].freeze

  # A page as the browser asks for it.
  def page(headers, path) = on(:web, path, headers: headers, remote_addr: EDGE)

  # A post as the page's script does it, with the page's CSRF token.
  def post_json(headers, path, body = {})
    on(:web, "/today", headers: headers, remote_addr: EDGE)
    token = css_select("meta[name=csrf-token]").first&.[]("content")
    on(:web, path, method: :post, headers: headers.merge(JSON_HEADERS, "X-CSRF-Token" => token.to_s), params: body.to_json, remote_addr: EDGE)
    response.parsed_body
  end

  def serve_for(headers, follow: nil)
    post_json(headers, "/practice/serves", { topic: TOPIC, skill: SKILL, follow: follow })
  end

  # ---- visibility ------------------------------------------------------------------------------------

  test "the official student sees nothing until the course is released" do
    build_student_world(release: false)
    page(OFFICIAL, "/today")
    assert_response :success
    assert_select "#course-closed", /Il corso non è ancora aperto/
    assert_select "#suggestions", 0
    page(OFFICIAL, "/subjects")
    assert_select "#course-closed"
    assert_select "li.subject", 0
    (PAGES - %w[/today /subjects]).each do |path|
      page(OFFICIAL, path)
      assert_response :not_found, path
    end
    assert_equal({ "status" => "not_found" }, serve_for(OFFICIAL))
    assert_response :not_found
    assert_equal 0, PracticeServe.count
  end

  test "an unapproved topic stays hidden from the official student after the release" do
    build_student_world(approve: false)
    page(OFFICIAL, "/topics/#{TOPIC}")
    assert_response :not_found
    page(OFFICIAL, "/today")
    assert_select "#course-closed"
  end

  test "after the release and the approval the official student sees the course, and a withdrawal closes it again" do
    build_student_world
    page(OFFICIAL, "/today")
    assert_select "#suggestions li.topic[data-topic='#{TOPIC}']", 1
    assert_select "#course-closed", 0
    release_course!(@course, open: false)
    page(OFFICIAL, "/today")
    assert_select "#course-closed"
    page(OFFICIAL, "/topics/#{TOPIC}")
    assert_response :not_found
  end

  test "a trial student sees the draft before any approval and release, labelled" do
    build_student_world(approve: false, release: false)
    page(TRIAL, "/topics/#{TOPIC}")
    assert_response :success
    assert_select "#draft-notice", "Bozza: il docente non l'ha ancora approvata."
    page(TRIAL, "/today")
    assert_select "#suggestions li.topic .topic-why", /Bozza/
    assert_select "#trial-notice", /Account di prova/
    page(TRIAL, "/topics/#{TOPIC}/lesson")
    assert_select "#draft-notice"
  end

  test "an approved topic carries no draft notice for a trial student" do
    build_student_world
    page(TRIAL, "/topics/#{TOPIC}")
    assert_select "#draft-notice", 0
  end

  test "the teacher and a guest get 403 on every page and every post" do
    build_student_world
    [ TEACHER, GUEST ].each do |who|
      PAGES.each do |path|
        page(who, path)
        assert_response :forbidden, "#{path} for #{who['Remote-User']}"
      end
      [ "/practice/serves", "/practice/answers", "/practice/serves/1/hint", "/practice/serves/1/solution", "/questions", "/topics/#{TOPIC}/lesson/exercises/1/solution" ].each do |path|
        on(:web, path, method: :post, headers: who.merge(JSON_HEADERS), params: "{}", remote_addr: EDGE)
        assert_response :forbidden, path
      end
    end
    page({}, "/today")
    assert_response :forbidden
  end

  test "a student the operator has not configured is told so, not shown the course" do
    build_student_world
    page(UNMAPPED, "/today")
    assert_response :forbidden
  end

  test "the trial student's practice never touches the official student's rows" do
    build_student_world
    serve_for(TRIAL)
    assert_equal [ @trial.id ], PracticeServe.pluck(:student_id).uniq
  end

  # ---- the pages -------------------------------------------------------------------------------------

  test "Oggi: the resume button after a lesson and the reason of each suggestion" do
    build_student_world
    page(OFFICIAL, "/today")
    assert_select "#resume", 0
    assert_select "li.topic[data-reason=course_next] .topic-why", "È il prossimo argomento del corso."
    assert_select "li.topic .topic-meta", /Ripasso di prima · 30 minuti/
    assert_select ".course-nav a", 3
    page(OFFICIAL, "/topics/#{TOPIC}/lesson")
    page(OFFICIAL, "/today")
    assert_select "#resume", "Riprendi: #{TOPIC_TITLE}"
  end

  test "Materie and Materia: counts, status and tag" do
    build_student_world
    page(OFFICIAL, "/subjects")
    assert_select "li.subject[data-subject=math] .subject-state", "0 abilità dimostrate, 0 in studio, 0 da riprendere, 1 non ancora viste."
    page(OFFICIAL, "/subjects/math")
    assert_select "li.topic[data-topic='#{TOPIC}'][data-status=todo]"
    assert_select "li.topic .topic-meta", /Ripasso di prima · 30 minuti · Da fare/
    page(OFFICIAL, "/subjects/chemistry")
    assert_response :not_found
  end

  test "Argomento: the programme line, the intro, the lesson link and the skill" do
    build_student_world
    page(OFFICIAL, "/topics/#{TOPIC}")
    assert_select "h1", TOPIC_TITLE
    assert_select "#programme li", "Dal programma, riga 7: «equazioni di primo grado numeriche»"
    assert_select "#intro", "Qui impari a risolvere le equazioni."
    assert_select "#lesson-read", 0
    assert_select "li.skill[data-skill='#{SKILL}'] .skill-name", "Equazioni lineari intere"
    assert_select "li.skill .topic-why", /Non l'hai ancora provata/
    assert_select "li.skill a[href='/topics/#{TOPIC}/practice/#{SKILL}']", "Esercitati"
    assert_select "[data-controller=question] button", "Non ho capito"
    page(OFFICIAL, "/topics/#{TOPIC}/lesson")
    page(OFFICIAL, "/topics/#{TOPIC}")
    assert_select "#lesson-read", "Lezione letta"
  end

  test "Lezione: the sections in order, the exercises, no solution and no final in the page" do
    build_student_world
    page(OFFICIAL, "/topics/#{TOPIC}/lesson")
    assert_response :success
    assert_equal [ "Perché ti serve", "L'idea in breve", "Esempio svolto", "Errori da evitare", "Prova tu", "Sul libro", "In sintesi" ], css_select("main > section > h2").map(&:text)
    assert_select "li.exercise", 2
    assert_select "li.exercise button", "Mostra la soluzione"
    assert_select "[data-lesson-markup]", minimum: 6
    assert_not_includes response.body, SECRET_FINAL
    assert_not_includes response.body, SECRET_SOLUTION
    assert_not_includes response.body, "Secondo passo"
    assert_not_includes response.body, "final_it"
    assert_not_includes response.body, "finals_it"
    assert_equal 1, PracticeEvent.where(kind: "lesson_opened", student: @official).count
  end

  test "the lesson solution comes on request, is recorded, and an unknown exercise is a 404" do
    build_student_world
    body = post_json(OFFICIAL, "/topics/#{TOPIC}/lesson/exercises/1/solution")
    assert_response :success
    assert_equal [ "n", "solution_it" ], body.keys
    assert_equal 1, body["n"]
    assert_includes body["solution_it"], SECRET_SOLUTION
    assert_not_includes body.to_json, SECRET_FINAL
    event = PracticeEvent.find_by!(kind: "lesson_solution_shown")
    assert_equal({ "n" => 1 }, JSON.parse(event.payload_json))
    assert_equal [ @official.id, @lesson_revision.id, @topic_revision.id ], [ event.student_id, event.lesson_revision_id, event.topic_revision_id ]
    post_json(OFFICIAL, "/topics/#{TOPIC}/lesson/exercises/9/solution")
    assert_response :not_found
  end

  test "the diagnosis page links to Oggi only when there is a visible topic" do
    build_student_world(release: false)
    page(OFFICIAL, "/diagnosis")
    assert_select "#course-link", 0
    release_course!(@course)
    page(OFFICIAL, "/diagnosis")
    assert_select "#course-link[href='/today']"
  end

  test "the practice page shell: skill, state, the live region and the question control" do
    build_student_world
    page(OFFICIAL, "/topics/#{TOPIC}/practice/#{SKILL}")
    assert_response :success
    assert_select "#skill-name", "Equazioni lineari intere"
    assert_select "#skill-state", /Non ancora vista/
    assert_select "#feedback[role=status][aria-live=polite]"
    assert_select "button#check", "Controlla"
    assert_select "[data-controller=practice]"
    assert_select "[data-controller=question]"
    page(OFFICIAL, "/topics/#{TOPIC}/practice/math.not-in-this-topic")
    assert_response :not_found
    # nothing about the key or the practice items is in the shell
    assert_not_includes response.body, "Quale regola usi?"
  end

  # ---- the JSON ----------------------------------------------------------------------------------------

  # Names that belong to the key, the grading or the shuffle, wherever they are.
  FORBIDDEN_KEYS = %w[answer answers errors error_catalogue steps_solution id_map shown_order verdict score expected fingerprint rubric model_answer_it
                      grading evidence finals_it final_it review checklist findings errors_json answer_json hints_json solution_json].freeze

  def keys_of(value, found = [])
    case value
    when Hash then value.each { |k, v| found << k.to_s; keys_of(v, found) }
    when Array then value.each { |v| keys_of(v, found) }
    end
    found
  end

  def assert_clean(json, what)
    assert_empty keys_of(json) & FORBIDDEN_KEYS, "#{what} carries a forbidden key"
    text = json.to_json
    [ "Quale regola usi?", "Fai il primo passaggio.", "Passo.", "Hai sbagliato un segno." ].each { |s| assert_not_includes text, s, "#{what} leaks #{s}" } if what.start_with?("serve")
  end

  test "a serve: exactly the A9.3 keys, one open serve, no key, no hint, no solution, for the official and the trial path" do
    build_student_world
    [ OFFICIAL, TRIAL ].each do |who|
      body = serve_for(who)
      assert_response :success
      assert_equal %w[type serve_id reason reason_it status next_try_number skill hints item].sort, body.keys.sort
      assert_equal [ "item", "next", "open", 1 ], [ body["type"], body["reason"], body["status"], body["next_try_number"] ]
      assert_nil body["reason_it"]
      assert_equal({ "total" => 3, "shown" => [] }, body["hints"])
      assert_equal [ SKILL, "Equazioni lineari intere", "not_seen", "Non ancora vista" ], body["skill"].values_at("key", "label_it", "state", "state_it")
      assert_equal "number", body["item"]["component"]
      assert body["item"]["instance_stem_it"].present? || body["item"]["stem_it"].present?
      assert_clean(body, "serve")
      assert_equal body["serve_id"], serve_for(who)["serve_id"], "a reload gets the same serve"
    end
    assert_equal 2, PracticeServe.count
  end

  test "the item part is the one the diagnosis shows: Items::Part keys only" do
    build_student_world
    item = serve_for(OFFICIAL)["item"]
    allowed = %w[component passage_it stem_it instance_stem_it table quote figure options elements left right reuse_right unit scientific mixed
                 answer_format_it steps_it accents input]
    assert_empty item.keys - allowed
  end

  test "a correct answer: graded, the solution is sent then, and the next serve is another instance" do
    build_student_world
    serve = serve_for(OFFICIAL)
    instance = PracticeServe.find(serve["serve_id"]).item_instance
    answer = post_json(OFFICIAL, "/practice/answers", { serve_id: serve["serve_id"], client_attempt_id: SecureRandom.uuid, raw: JSON.parse(instance.answer_json).to_s, source: "text" })
    assert_response :success
    assert_equal %w[graded correct], answer.values_at("status", "outcome")
    assert_equal %w[next back], answer["actions"]
    assert_equal "Corretto.", answer["message_it"]
    assert_equal "Passo.", answer["solution"]["steps"].first["text_it"]
    assert_equal true, answer["skill"]["changed"]
    assert_nil answer["error_code"]
    second = serve_for(OFFICIAL)
    assert_not_equal serve["serve_id"], second["serve_id"]
    assert_not_equal PracticeServe.find(serve["serve_id"]).item_instance_id, PracticeServe.find(second["serve_id"]).item_instance_id
  end

  test "a typical error: the catalogue message, no solution, Prova questo serves the code" do
    build_student_world
    serve = serve_for(OFFICIAL)
    instance = PracticeServe.find(serve["serve_id"]).item_instance
    slip = JSON.parse(instance.errors_json).first["value"].to_s
    answer = post_json(OFFICIAL, "/practice/answers", { serve_id: serve["serve_id"], client_attempt_id: SecureRandom.uuid, raw: slip, source: "text" })
    assert_equal [ "typical_error", "slip", "Hai sbagliato un segno." ], answer.values_at("outcome", "error_code", "message_it")
    assert_nil answer["solution"]
    assert_equal %w[prova_questo show_solution back], answer["actions"]
    assert_clean(answer, "answer")
    follow = serve_for(OFFICIAL, follow: { serve_id: serve["serve_id"], kind: "prova_questo" })
    assert_response :success
    assert_equal "prova_questo", follow["reason"]
    assert_equal "Un esercizio simile, per lo stesso errore.", follow["reason_it"]
    assert_equal "slip", PracticeServe.find(follow["serve_id"]).error_code
  end

  test "an unrecognised answer: the first hint comes with it, the second only on request, then the solution on request" do
    build_student_world
    serve = serve_for(OFFICIAL)
    id = serve["serve_id"]
    answer = post_json(OFFICIAL, "/practice/answers", { serve_id: id, client_attempt_id: SecureRandom.uuid, raw: "99999", source: "text" })
    assert_equal "unrecognised", answer["outcome"]
    assert_equal({ "n" => 1, "total" => 3, "hint_it" => "Che cosa guardi prima?" }, answer["hint"])
    assert_nil answer["solution"]
    assert_equal %w[retry show_solution], answer["actions"]
    assert_not_includes answer.to_json, "Quale regola usi?"
    reload = serve_for(OFFICIAL)
    assert_equal id, reload["serve_id"]
    assert_equal 2, reload["next_try_number"]
    assert_equal [ { "n" => 1, "hint_it" => "Che cosa guardi prima?" } ], reload["hints"]["shown"]
    assert_not_includes reload.to_json, "Quale regola usi?"
    hint = post_json(OFFICIAL, "/practice/serves/#{id}/hint", { n: 2 })
    assert_response :success
    assert_equal "Quale regola usi?", hint["hint_it"]
    post_json(OFFICIAL, "/practice/serves/#{id}/hint", { n: 4 })
    assert_response :unprocessable_entity
    solution = post_json(OFFICIAL, "/practice/serves/#{id}/solution")
    assert_response :success
    assert_equal "Passo.", solution["solution"]["steps"].first["text_it"]
    assert_equal %w[after_solution back], solution["actions"]
    post_json(OFFICIAL, "/practice/answers", { serve_id: id, client_attempt_id: SecureRandom.uuid, raw: "1", source: "text" })
    assert_response :conflict
    assert_equal "closed", response.parsed_body["status"]
    assert_equal "Questo esercizio è chiuso: scegline un altro.", response.parsed_body["message_it"]
  end

  test "an answer is idempotent on its client id, and invalid input is not a try" do
    build_student_world
    id = serve_for(OFFICIAL)["serve_id"]
    cid = SecureRandom.uuid
    first = post_json(OFFICIAL, "/practice/answers", { serve_id: id, client_attempt_id: cid, raw: "99999", source: "text" })
    again = post_json(OFFICIAL, "/practice/answers", { serve_id: id, client_attempt_id: cid, raw: "99999", source: "text" })
    assert_equal first, again
    assert_equal 1, PracticeAttempt.count
    empty = post_json(OFFICIAL, "/practice/answers", { serve_id: id, client_attempt_id: SecureRandom.uuid, raw: "  ", source: "text" })
    assert_equal "invalid", empty["status"]
    assert_equal 1, PracticeAttempt.count
  end

  test "another student's serve is a 404 on every endpoint" do
    build_student_world
    id = serve_for(OFFICIAL)["serve_id"]
    post_json(TRIAL, "/practice/answers", { serve_id: id, client_attempt_id: SecureRandom.uuid, raw: "1", source: "text" })
    assert_response :not_found
    post_json(TRIAL, "/practice/serves/#{id}/hint", { n: 1 })
    assert_response :not_found
    post_json(TRIAL, "/practice/serves/#{id}/solution")
    assert_response :not_found
    serve_for(TRIAL, follow: { serve_id: id, kind: "prova_questo" })
    assert_response :unprocessable_entity
    assert_equal "bad_follow", response.parsed_body["status"]
  end

  test "a withdrawn release stops the official student's answers too" do
    build_student_world
    id = serve_for(OFFICIAL)["serve_id"]
    release_course!(@course, open: false)
    post_json(OFFICIAL, "/practice/answers", { serve_id: id, client_attempt_id: SecureRandom.uuid, raw: "1", source: "text" })
    assert_response :not_found
    serve_for(OFFICIAL)
    assert_response :not_found
  end

  test "a skill that is not the topic's, or a topic that does not exist, is a 404" do
    build_student_world
    post_json(OFFICIAL, "/practice/serves", { topic: TOPIC, skill: "math.percentages" })
    assert_response :not_found
    post_json(OFFICIAL, "/practice/serves", { topic: "ripasso.math.nope", skill: SKILL })
    assert_response :not_found
  end

  # ---- "Non ho capito" ---------------------------------------------------------------------------------

  test "a question is stored once, with its place, and the teacher's table is the only reader" do
    build_student_world
    id = serve_for(OFFICIAL)["serve_id"]
    body = { client_question_id: "q-" + SecureRandom.hex(8), topic: TOPIC, lesson_revision_id: @lesson_revision.id, serve_id: id, section: "practice", exercise: nil,
             text_it: "Non capisco il segno." }
    reply = post_json(OFFICIAL, "/questions", body)
    assert_response :success
    assert_equal({ "ok" => true, "message_it" => "Fatto: il docente lo vedrà." }, reply)
    post_json(OFFICIAL, "/questions", body)
    assert_response :success
    assert_equal 1, StudentQuestion.count
    q = StudentQuestion.first
    assert_equal [ @official.id, @topic_revision.id, @lesson_revision.id, id, "practice", nil, "Non capisco il segno." ],
                 [ q.student_id, q.topic_revision_id, q.lesson_revision_id, q.practice_serve_id, q.section, q.exercise, q.text_it ]
  end

  test "a question may be empty, and its refusals" do
    build_student_world
    ok = ->(extra) { post_json(OFFICIAL, "/questions", { client_question_id: "q-" + SecureRandom.hex(8), topic: TOPIC }.merge(extra)) }
    ok.({ section: "idea", text_it: nil })
    assert_response :success
    assert_nil StudentQuestion.last.text_it
    ok.({ text_it: "x" * 301 })
    assert_response :unprocessable_entity
    ok.({ section: "nonsense" })
    assert_response :unprocessable_entity
    ok.({ exercise: 40 })
    assert_response :unprocessable_entity
    ok.({ lesson_revision_id: @lesson_revision.id + 99 })
    assert_response :not_found
    ok.({ topic: "ripasso.math.nope" })
    assert_response :not_found
    post_json(OFFICIAL, "/questions", { client_question_id: "x", topic: TOPIC })
    assert_response :unprocessable_entity
    other = practice_student("someone-else")
    foreign = make_serve(other, @topic_revision, @revisions.first.instances.first, skill_key: SKILL)
    ok.({ serve_id: foreign.id })
    assert_response :not_found
  end

  test "the official student's question is not readable through another student's id" do
    build_student_world
    cid = "q-" + SecureRandom.hex(8)
    post_json(OFFICIAL, "/questions", { client_question_id: cid, topic: TOPIC, text_it: "uno" })
    post_json(TRIAL, "/questions", { client_question_id: cid, topic: TOPIC, text_it: "due" })
    assert_response :not_found
    assert_equal 1, StudentQuestion.count
  end

  # ---- the headers ---------------------------------------------------------------------------------------

  test "the pages carry the student's CSP with a nonce, no inline script, and the JSON is not cached" do
    build_student_world
    page(OFFICIAL, "/topics/#{TOPIC}/practice/#{SKILL}")
    csp = response.headers["Content-Security-Policy"]
    assert_match(/script-src 'self' 'nonce-/, csp)
    assert_not_includes csp.to_s[/script-src[^;]*/], "unsafe-inline"
    assert_no_match(/<script(?![^>]*(nonce=|src=|type="importmap"))/, response.body)
    assert_nil response.body[/ on[a-z]+="/]
    post_json(OFFICIAL, "/practice/serves", { topic: TOPIC, skill: SKILL })
    assert_equal "no-store", response.headers["Cache-Control"]
  end
end
