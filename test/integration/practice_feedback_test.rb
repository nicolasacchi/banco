require "test_helper"
require_relative "../support/multi_user"
require_relative "../support/practice_text_world"

# D-339 over the real endpoints, for the student and for the teacher's preview: a whole sentence around a `___` blank, the same answer twice,
# the plainer messages, «ci sei quasi», «Fai controllare» (the contest, its comment and its solution) and the list's «Da finire».
class PracticeFeedbackTest < ActionDispatch::IntegrationTest
  include MultiUser
  include PracticeTextWorld

  JSON_HEADERS = { "Content-Type" => "application/json", "Accept" => "application/json" }.freeze
  PREVIEW = "/teacher/preview".freeze
  WHOLE_WRONG = "My parents do not eat meat".freeze # the part «do not eat» is not «don't eat»

  setup { build_text_world }

  # ---- the page's calls ---------------------------------------------------------------------------------

  def post_json(headers, path, body = {}, root: "")
    on(:web, "#{root}/today", headers: headers, remote_addr: EDGE)
    token = css_select("meta[name=csrf-token]").first&.[]("content")
    on(:web, path, method: :post, headers: headers.merge(JSON_HEADERS, "X-CSRF-Token" => token.to_s), params: body.to_json, remote_addr: EDGE)
    response.parsed_body
  end

  def get_json(headers, path)
    on(:web, path, headers: headers.merge("Accept" => "application/json"), remote_addr: EDGE)
    response.parsed_body
  end

  def serve_for(headers, key, root: "") = post_json(headers, "#{root}/practice/serves", { topic: TOPIC, skill: SKILL, item: key }, root: root)

  def answer_for(headers, serve, raw, root: "")
    post_json(headers, "#{root}/practice/answers", { serve_id: serve["serve_id"], client_attempt_id: SecureRandom.uuid, raw: raw, source: "text" }, root: root)
  end

  def contest_for(headers, serve, root: "") = post_json(headers, "#{root}/practice/serves/#{serve['serve_id']}/contest", {}, root: root)

  def statuses(headers, root: "")
    get_json(headers, "#{root}/practice/exercises?topic=#{TOPIC}")["skills"].first["exercises"].to_h { |e| [ e["item"], e["status"] ] }
  end

  def solution_events(serve) = PracticeEvent.where(practice_serve_id: serve["serve_id"], kind: "solution_shown").map { |e| JSON.parse(e.payload_json)["reason"] }
  def tries(serve) = PracticeAttempt.where(practice_serve_id: serve["serve_id"]).count

  # ---- the whole sentence --------------------------------------------------------------------------------

  test "a whole sentence around the blank is right, with the note; the words alone have none" do
    serve = serve_for(OFFICIAL, SENTENCE)
    right = answer_for(OFFICIAL, serve, "My parents don't eat meat.")
    assert_equal [ "graded", "correct", "Corretto." ], right.values_at("status", "outcome", "message_it")
    assert_equal "Bastava scrivere solo le parole che mancano: don't eat.", right["note_it"]
    assert right["solution"]
    assert_equal %w[next back], right["actions"]
    attempt = PracticeAttempt.find(right["attempt_id"])
    assert_equal [ "My parents don't eat meat.", 1 ], [ attempt.raw, attempt.try_number ]

    again = serve_for(OFFICIAL, SENTENCE)
    refute_equal serve["serve_id"], again["serve_id"]
    plain = answer_for(OFFICIAL, again, "don't eat")
    assert_equal "correct", plain["outcome"]
    assert_nil plain["note_it"]
  end

  test "the blank copied and a sentence that does not fit are refused, and no try is stored" do
    serve = serve_for(OFFICIAL, SENTENCE)
    blank = answer_for(OFFICIAL, serve, "My parents ___ meat.")
    assert_equal [ "invalid", "Al posto di ___ scrivi le parole che mancano." ], blank.values_at("status", "message_it")
    long = answer_for(OFFICIAL, serve, "My parents really do not like to eat any food at all")
    assert_equal [ "invalid", "Scrivi solo le parole che vanno al posto di ___." ], long.values_at("status", "message_it")
    assert_equal 0, tries(serve)
  end

  # ---- the messages --------------------------------------------------------------------------------------

  test "the unrecognised answer says it is not right yet, with and without a hint; the old text is gone" do
    serve = serve_for(OFFICIAL, SENTENCE)
    wrong = answer_for(OFFICIAL, serve, "play")
    assert_equal [ "unrecognised", "Non è ancora giusta. Leggi l'aiuto e riprova." ], wrong.values_at("outcome", "message_it")
    assert_equal "Pensa al plurale.", wrong.dig("hint", "hint_it")
    assert_equal %w[retry show_solution contest], wrong["actions"]
    assert_no_match(/non corrisponde a un errore/, wrong.to_json)

    bare = answer_for(OFFICIAL, serve_for(OFFICIAL, WORD), "casa")
    assert_equal [ "unrecognised", "Non è ancora giusta. Riprova." ], bare.values_at("outcome", "message_it")
    assert_nil bare["hint"]
  end

  test "a typo and a missing word are «ci sei quasi»; two near answers close the serve with the solution" do
    typo = answer_for(OFFICIAL, serve_for(OFFICIAL, WORD), "neighbourhod")
    assert_equal [ "near_miss", "Ci sei quasi: controlla come l'hai scritta, forse c'è un errore di battitura.", %w[retry] ],
                 typo.values_at("outcome", "message_it", "actions")
    assert_nil typo["solution"]

    serve = serve_for(OFFICIAL, SENTENCE)
    missing = answer_for(OFFICIAL, serve, "don't")
    assert_equal [ "near_miss", "Ci sei quasi: manca una parola, oppure ce n'è una in più." ], missing.values_at("outcome", "message_it")
    second = answer_for(OFFICIAL, serve, "eat")
    assert_equal [ "near_miss", I18n.t("practice.second_wrong"), %w[after_solution next back] ], second.values_at("outcome", "message_it", "actions")
    assert second["solution"]
  end

  test "a substitution is a grammar error, not «ci sei quasi»" do
    wrong = answer_for(OFFICIAL, serve_for(OFFICIAL, SENTENCE), "does eat")
    assert_equal "unrecognised", wrong["outcome"]
  end

  # ---- the same answer -----------------------------------------------------------------------------------

  test "the same answer is refused with «Fai controllare» while a contest is allowed, and no try is stored" do
    serve = serve_for(OFFICIAL, SENTENCE)
    first = answer_for(OFFICIAL, serve, "play")
    assert_equal 1, first["try_number"]
    same = answer_for(OFFICIAL, serve, "  play ")
    assert_equal [ "invalid", "È la stessa risposta di prima. Cambia qualcosa, oppure premi «Fai controllare»." ], same.values_at("status", "message_it")
    assert_equal 1, tries(serve)
    assert_equal %w[retry show_solution contest], first["actions"]
    other = answer_for(OFFICIAL, serve, "sleep")
    assert_equal 2, other["try_number"]
  end

  test "the same answer is refused with the plain text when there is nothing to contest, a text answer compared as the grader reads it" do
    serve = serve_for(OFFICIAL, WORD)
    assert_equal "near_miss", answer_for(OFFICIAL, serve, "neighbourhod")["outcome"]
    same = answer_for(OFFICIAL, serve, "Neighbourhod ")
    assert_equal [ "invalid", "È la stessa risposta di prima. Cambia qualcosa e riprova." ], same.values_at("status", "message_it")
    assert_equal 1, tries(serve)
  end

  # ---- «Fai controllare» ---------------------------------------------------------------------------------

  test "a contest on an open serve: the comment for the teacher, the solution once, the same answer on a second click" do
    serve = serve_for(OFFICIAL, SENTENCE)
    answer_for(OFFICIAL, serve, WHOLE_WRONG)
    body = contest_for(OFFICIAL, serve)
    assert_response :success
    assert_equal "contested", body["status"]
    assert_equal "Ho mandato la tua risposta al docente: ti risponde in «I miei commenti». Intanto ecco la soluzione: confrontala con la tua.", body["message_it"]
    assert_equal "don't eat", body.dig("solution", "final")
    assert_equal %w[next back], body["actions"]

    contest = PracticeContest.last
    attempt = PracticeAttempt.find_by!(practice_serve_id: serve["serve_id"])
    assert_equal [ @official.id, serve["serve_id"], attempt.id ], [ contest.student_id, contest.practice_serve_id, contest.practice_attempt_id ]
    comment = contest.comment
    assert_equal [ @official.id, "error", "practice", "exercise/item/answer", serve["serve_id"], "/topics/#{TOPIC}/practice/#{SKILL}" ],
                 [ comment.student_id, comment.reason, comment.page_kind, comment.anchor, comment.practice_serve_id, comment.page_path ]
    assert_equal "La mia risposta, secondo me giusta: «#{WHOLE_WRONG}».", comment.text_it
    assert_equal "sent", comment.state
    assert_equal %w[after_contest], solution_events(serve)

    assert_equal body, contest_for(OFFICIAL, serve)
    assert_response :success
    assert_equal [ 1, 1 ], [ PracticeContest.count, Comment.count ]
    assert_equal %w[after_contest], solution_events(serve)
    closed = answer_for(OFFICIAL, serve, "something else")
    assert_response :conflict
    assert_equal "closed", closed["status"]
  end

  test "a contest on a serve closed wrong after two tries contests the second try and sends no second solution" do
    serve = serve_for(OFFICIAL, WORD)
    answer_for(OFFICIAL, serve, "casa")
    second = answer_for(OFFICIAL, serve, "albero")
    assert_equal %w[after_solution back contest], second["actions"]
    assert_equal %w[after_last_try], solution_events(serve)

    body = contest_for(OFFICIAL, serve)
    assert_response :success
    assert_equal [ "contested", %w[next back] ], body.values_at("status", "actions")
    assert body["solution"]
    assert_equal second["attempt_id"], PracticeContest.last.practice_attempt_id
    assert_equal %w[after_last_try], solution_events(serve)
    assert_equal "La mia risposta, secondo me giusta: «albero».", Comment.last.text_it
  end

  test "the answer in the comment is cut at 200 characters" do
    serve = serve_for(OFFICIAL, WORD)
    answer_for(OFFICIAL, serve, "x" * 300)
    contest_for(OFFICIAL, serve)
    assert_equal "La mia risposta, secondo me giusta: «#{'x' * 200}».", Comment.last.text_it
  end

  test "a contest is refused with 409 when it is not allowed: no try, a typical error, a right answer, a near miss" do
    serve = serve_for(OFFICIAL, SENTENCE)
    assert_equal({ "status" => "not_contestable" }, contest_for(OFFICIAL, serve))
    assert_response :conflict

    typical = answer_for(OFFICIAL, serve, "doesn't eat")
    assert_equal [ "typical_error", SLIP_MESSAGE ], typical.values_at("outcome", "message_it")
    assert_equal({ "status" => "not_contestable" }, contest_for(OFFICIAL, serve))
    assert_response :conflict

    right = serve_for(OFFICIAL, SENTENCE)
    answer_for(OFFICIAL, right, "don't eat")
    assert_equal({ "status" => "not_contestable" }, contest_for(OFFICIAL, right))
    assert_response :conflict

    near = serve_for(OFFICIAL, WORD)
    answer_for(OFFICIAL, near, "neighbourhod")
    assert_equal({ "status" => "not_contestable" }, contest_for(OFFICIAL, near))
    assert_response :conflict
    assert_equal [ 0, 0 ], [ PracticeContest.count, Comment.count ]
  end

  test "another student's serve is a 404" do
    serve = serve_for(OFFICIAL, SENTENCE)
    answer_for(OFFICIAL, serve, "play")
    assert_equal({ "status" => "not_found" }, contest_for(TRIAL, serve))
    assert_response :not_found
    assert_equal 0, PracticeContest.count
  end

  test "a trial student's contest is the trial student's own, with a comment" do
    serve = serve_for(TRIAL, SENTENCE)
    answer_for(TRIAL, serve, "play")
    assert_equal "contested", contest_for(TRIAL, serve)["status"]
    assert_equal [ @trial.id ], [ PracticeContest.last.student_id ]
    assert_equal [ @trial.id, true ], [ Comment.last.student_id, Comment.last.trial ]
  end

  test "the preview contests as the preview student, writes no comment, sends the solution once, and answers the same on a second click" do
    serve = serve_for(TEACHER, SENTENCE, root: PREVIEW)
    answer_for(TEACHER, serve, "play", root: PREVIEW)
    body = contest_for(TEACHER, serve, root: PREVIEW)
    assert_response :success
    assert_equal [ "contested", %w[next back] ], body.values_at("status", "actions")
    assert body["solution"]

    preview = Student.where(kind: "preview").order(:id).last
    contest = PracticeContest.last
    assert_equal [ preview.id, nil ], [ contest.student_id, contest.comment_id ]
    assert_equal 0, Comment.count
    assert_equal %w[after_contest], solution_events(serve)
    assert_equal body, contest_for(TEACHER, serve, root: PREVIEW)
    assert_equal [ 1, 0 ], [ PracticeContest.count, Comment.count ]
    assert_equal({ "status" => "not_found" }, contest_for(OFFICIAL, serve))
  end

  test "a contest changes no answer and no grading: the try stays as it was graded" do
    serve = serve_for(OFFICIAL, SENTENCE)
    answer_for(OFFICIAL, serve, "play")
    attempt = PracticeAttempt.find_by!(practice_serve_id: serve["serve_id"])
    grading = attempt.gradings.map { |g| [ g.id, g.verdict ] }
    contest_for(OFFICIAL, serve)
    assert_equal grading, attempt.reload.gradings.map { |g| [ g.id, g.verdict ] }
    assert_equal [ 1, "play" ], [ PracticeAttempt.where(practice_serve_id: serve["serve_id"]).count, attempt.raw ]
  end

  # ---- the list ------------------------------------------------------------------------------------------

  test "the list says «unfinished» for an open serve with a try or a draft, «skipped» for neither" do
    serve = serve_for(OFFICIAL, SENTENCE)
    assert_equal "skipped", statuses(OFFICIAL)[SENTENCE]
    post_json(OFFICIAL, "/practice/serves/#{serve['serve_id']}/draft", { raw: "pla", source: "text" })
    assert_equal "unfinished", statuses(OFFICIAL)[SENTENCE]
    answer_for(OFFICIAL, serve, "play")
    assert_equal "unfinished", statuses(OFFICIAL)[SENTENCE]
    assert_equal "todo", statuses(OFFICIAL)[WORD]
  end

  test "an open serve with nothing typed on a done exercise keeps «done»; with a try it is «unfinished»" do
    serve = serve_for(OFFICIAL, SENTENCE)
    answer_for(OFFICIAL, serve, "don't eat")
    assert_equal "done", statuses(OFFICIAL)[SENTENCE]
    again = serve_for(OFFICIAL, SENTENCE)
    refute_equal serve["serve_id"], again["serve_id"]
    assert_equal "done", statuses(OFFICIAL)[SENTENCE]
    answer_for(OFFICIAL, again, "play")
    assert_equal "unfinished", statuses(OFFICIAL)[SENTENCE]
  end

  test "the preview's list says «unfinished» too, for the preview student" do
    serve = serve_for(TEACHER, SENTENCE, root: PREVIEW)
    answer_for(TEACHER, serve, "play", root: PREVIEW)
    assert_equal "unfinished", statuses(TEACHER, root: PREVIEW)[SENTENCE]
    assert_equal "todo", statuses(OFFICIAL)[SENTENCE], "the official student's list is not the preview's"
  end

  test "the labels are in the locale" do
    assert_equal [ "Da finire", "Finito", "Finito: con la soluzione", "Fatto", "Saltato", "Da fare" ],
                 %w[unfinished finished finished_solution done skipped todo].map { |status| I18n.t("practice.status_#{status}") }
    assert_equal "Fai controllare", I18n.t("practice.contest_button")
    assert_equal "Pensi che la tua risposta sia giusta? Premi «Fai controllare»: la vede il docente.", I18n.t("practice.contest_note")
  end
end
