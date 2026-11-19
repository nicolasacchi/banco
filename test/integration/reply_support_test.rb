require "test_helper"
require "rake"
require_relative "../support/lesson_events_world"
require_relative "../support/multi_user"
require_relative "../support/public_api_tokens"

# D-371: what the teacher needs to answer a comment, for the operator's tools only (never the student's path): the `context` block of
# GET /api/v1/comments/:id (the revision he saw against the newest, his tries, his earlier comments, the hours left of the 24 h promise), the
# tone lint of a reply (advisory, never blocking) and «In scadenza» (the inbox and the digest). Invented content only.
class ReplySupportTest < ActionDispatch::IntegrationTest
  include MultiUser
  include LessonEventsWorld
  include PublicApiTokens

  PHRASES = [ "hai sbagliato", "il tuo browser", "il tuo dispositivo", "tuo dispositivo", "se ricordi", "ti ricordi", "non hai letto", "era finito il tempo",
              "è scaduto il tempo", "devi", "avresti dovuto", "non è vero" ].freeze
  PRACTICE_PATH = "/topics/#{TOPIC}/practice/#{SKILL}".freeze

  setup do
    build_student_world
    @teacher_token = issue_token("teacher")
    @bot = issue_token("bot_read")
    @item = @revisions[0]
    @serve = make_serve(@official, @topic_revision, @item.instances.order(:id).first, skill_key: SKILL, at: 3.days.ago)
    @try = make_try(@serve, raw: "99999 parola-sua", verdict: "wrong", at: 3.days.ago + 60)
  end

  def make_comment(over = {})
    Comment.create!({ student: @official, client_comment_id: "c-#{SecureRandom.hex(6)}", reason: "error", text_it: "Non torna.", page_path: "/today", page_kind: "today",
                      subject: @subject, viewport_width: 390, viewport_height: 800, theme: "cream", text_size: "normal" }.merge(over))
  end

  def practice_comment(over = {})
    make_comment({ practice_serve: @serve, item_instance: @serve.item_instance, item_revision: @item, page_kind: "practice", page_path: PRACTICE_PATH,
                   anchor: "exercise/item", text_it: "La risposta giusta mi sembra un'altra." }.merge(over))
  end

  def event(comment, kind, at: Time.current, text: nil, origin: kind == "student_reply" ? "student" : "web")
    CommentEvent.create!(comment: comment, kind: kind, origin: origin, actor: origin == "student" ? @official.key : "nik", text_it: text, request_id: SecureRandom.uuid,
                         remote_addr: "1.1.1.1", created_at: at)
  end

  def newer_item_revision = ItemRevision.create!(item: @item.item, seq: 2, body_json: @item.body_json, file_sessions_json: "{}")

  def read_context(token, comment)
    api_as(token, "/api/v1/comments/#{comment.id}")
    assert_response :success
    json["comment"]["context"]
  end

  def send_reply(token, comment, text, confirm: false)
    api_as(token, "/api/v1/comments/#{comment.id}/reply", method: :post, body: { text_it: text, confirm: confirm })
  end

  # ---- the context: revisions ------------------------------------------------------------------------------

  test "the context sets the item revision he saw against the newest one, and says since when it changed" do
    comment = practice_comment
    context = read_context(@teacher_token, comment)
    assert_equal({ "key" => @item.item.key, "seen_revision_id" => @item.id, "current_revision_id" => @item.id, "changed" => false, "note" => "unchanged: rev #{@item.id}" },
                 context["revision"]["item"])
    newest = newer_item_revision
    item = read_context(@teacher_token, comment)["revision"]["item"]
    assert_equal [ @item.id, newest.id, true, "changed since: rev #{newest.id}" ], item.values_at("seen_revision_id", "current_revision_id", "changed", "note")
  end

  test "the context names the lesson revision of a lesson comment, and none for a comment on no revision" do
    comment = make_comment(lesson_revision: @lesson_revision, topic_revision: @topic_revision, page_kind: "lesson", page_path: "/topics/#{TOPIC}/lesson", card: 1, anchor: "card:1/block:1")
    newest = LessonRevision.create!(lesson: @lesson, seq: 2, source_md: "---\n", source_sha256: "1" * 64, rules_version: @lesson_revision.rules_version, warnings_json: "[]",
                                    body_json: @lesson_revision.body_json)
    lesson = read_context(@bot, comment)["revision"]["lesson"]
    assert_equal [ TOPIC, @lesson_revision.id, newest.id, "changed since: rev #{newest.id}" ], lesson.values_at("key", "seen_revision_id", "current_revision_id", "note")
    assert_nil read_context(@teacher_token, make_comment)["revision"]
  end

  # ---- the context: tries (his words for the teacher token only, D-346) ------------------------------------

  test "the teacher token reads his raw words in the tries, a bot_read token reads the outcome without them" do
    other = make_serve(@official, @topic_revision, @item.instances.order(:id).offset(1).first, skill_key: SKILL, at: 2.days.ago)
    make_try(other, raw: "7 altra-parola", verdict: "wrong", at: 2.days.ago + 60)
    comment = practice_comment

    tries = read_context(@teacher_token, comment)["tries"]
    assert_equal true, tries["words"]
    assert_equal [ [ @try.id, "99999 parola-sua" ] ], tries["behind_the_comment"].map { |r| [ r["id"], r["answer"] ] }
    assert_equal [ @item.item.key, 2 ], tries["on_the_item"].values_at("item", "total")
    assert_equal [ "7 altra-parola" ], tries["on_the_item"]["rows"].map { |r| r["answer"] }, "the other tries on the item, not the one already listed"

    bot = read_context(@bot, comment)["tries"]
    assert_equal false, bot["words"]
    rows = bot["behind_the_comment"] + bot["on_the_item"]["rows"]
    assert_equal 2, rows.size
    assert(rows.none? { |r| r.key?("answer") || r.key?("anchor_row") })
    assert_equal [ @try.id ], bot["behind_the_comment"].map { |r| r["id"] }
    assert_not_includes response.body, "parola-sua"
    assert_not_includes response.body, "altra-parola"
  end

  test "a comment with no try behind it has no tries block" do
    assert_not read_context(@teacher_token, make_comment).key?("tries")
  end

  # ---- the context: earlier comments -----------------------------------------------------------------------

  test "the earlier comments on the same item come with what the teacher answered; a comment with no item gets the same page" do
    first = practice_comment(text_it: "Prima volta.", created_at: 2.days.ago)
    event(first, "reply", at: 2.days.ago + 1.hour, text: "Guarda l'esempio.")
    elsewhere = make_comment(text_it: "Su un'altra pagina.", page_path: "/subjects", page_kind: "subjects", created_at: 2.days.ago)
    current = practice_comment(text_it: "Di nuovo.")
    later = practice_comment(text_it: "Dopo.")

    earlier = read_context(@teacher_token, current)["earlier_comments"]
    assert_equal [ first.id ], earlier.map { |c| c["id"] }
    assert_equal [ "answered", "Prima volta.", [ "Guarda l'esempio." ] ], [ earlier[0]["state"], earlier[0]["text_it"], earlier[0]["replies"].map { |r| r["text_it"] } ]
    assert_not_includes earlier.map { |c| c["id"] }, later.id, "only what came before"
    assert_not_includes earlier.map { |c| c["id"] }, elsewhere.id

    page_one = make_comment(page_path: "/subjects", page_kind: "subjects", text_it: "Sezione.")
    assert_equal [ elsewhere.id ], read_context(@bot, page_one)["earlier_comments"].map { |c| c["id"] }
    assert_not read_context(@bot, first).key?("earlier_comments"), "nothing earlier, nothing said"
  end

  # ---- the due hours (D-349) ---------------------------------------------------------------------------------

  test "the hours left count from the first student message without a teacher reply after it" do
    comment = make_comment(created_at: 30.hours.ago)
    reply = read_context(@teacher_token, comment)["reply"]
    assert_equal [ 24, true, true, false ], reply.values_at("within_hours", "waiting", "late", "student_followup")
    assert_in_delta(-6.0, reply["due_in_hours"], 0.1)
    assert_in_delta(-6.0, json["comment"]["due_in_hours"], 0.1)

    event(comment, "reply", at: 20.hours.ago, text: "Guarda l'esempio.")
    assert_equal({ "within_hours" => 24, "waiting" => false }, read_context(@teacher_token, comment)["reply"])
    assert_not json["comment"].key?("due_in_hours")

    event(comment, "student_reply", at: 5.hours.ago, text: "Ancora non capisco.")
    event(comment, "student_reply", at: 1.hour.ago, text: "Aiuto.")
    reply = read_context(@bot, comment)["reply"]
    assert_equal [ true, false, true ], reply.values_at("waiting", "late", "student_followup")
    assert_in_delta(19.0, reply["due_in_hours"], 0.1)
    assert_equal comment.reload.waiting_since.utc.iso8601, reply["waiting_since"]
    assert_in_delta(5.hours.ago.to_f, comment.waiting_since.to_f, 5)

    event(comment, "reply", at: 10.minutes.ago, text: "Ecco.")
    assert_equal false, read_context(@bot, comment)["reply"]["waiting"]
    event(comment, "resolved", at: 5.minutes.ago)
    assert_equal false, read_context(@bot, comment)["reply"]["waiting"]
  end

  test "a fresh comment has 24 hours, one at the limit has none and a late one has negative hours" do
    assert_in_delta 24.0, make_comment.due_in_hours, 0.1
    assert_in_delta 0.0, make_comment(created_at: 24.hours.ago).due_in_hours, 0.1
    assert_in_delta(-12.0, make_comment(created_at: 36.hours.ago).due_in_hours, 0.1)
    assert_equal 24.0, Comments::ReplyWindow.due_in_hours(Time.utc(2026, 11, 18, 9), Time.utc(2026, 11, 18, 9))
    assert_equal(-12.0, Comments::ReplyWindow.due_in_hours(Time.utc(2026, 11, 17, 9), Time.utc(2026, 11, 18, 21)))
    assert_nil Comments::ReplyWindow.due_in_hours(nil)
  end

  test "the context is for the reading tokens only, and the console builds the same block" do
    comment = practice_comment
    %w[agent_claude ci].each do |role|
      api_as(issue_token(role), "/api/v1/comments/#{comment.id}")
      assert_response :forbidden, role
      assert_not_includes response.body, "context"
    end
    assert_equal Comments::Context.new(comment, words: true).to_h.deep_stringify_keys.keys.sort, read_context(@teacher_token, comment).keys.sort
  end

  # ---- the tone lint (advisory) ----------------------------------------------------------------------------

  test "the lint warns on every blaming phrase of the list, in any case, and on nothing else" do
    assert_equal PHRASES, Comments::ReplyLint.phrases
    PHRASES.each do |phrase|
      text = "Allora #{phrase.upcase} qui, ok."
      assert_equal [ [ "blaming_phrase", phrase ] ], Comments::ReplyLint.call(text).map { |w| [ w.code, w.phrase ] }, phrase
    end
    assert_equal [ "hai sbagliato", "devi" ], Comments::ReplyLint.call("Se devi, ricorda: hai sbagliato il segno.").map(&:phrase), "in the order of the list"
    assert_equal [ "hai sbagliato" ], Comments::ReplyLint.call("Hai   sbagliato\nil segno.").map(&:phrase), "spaces and line breaks inside a phrase"
    assert_empty Comments::ReplyLint.call("Nell'esercizio la risposta giusta è 12: l'ho corretto nella revisione nuova. Grazie di averlo scritto."), "a kind reply"
    assert_empty Comments::ReplyLint.call("Il verbo devia dal modello e il tuo browserino non conta."), "a phrase inside another word is not a match"
    assert_empty Comments::ReplyLint.call("   "), "nothing to say"
    assert_empty Comments::ReplyLint.call(nil)
  end

  test "the lint flags a reply over 600 characters and not one of 600" do
    assert_empty Comments::ReplyLint.call("a" * 600)
    warnings = Comments::ReplyLint.call("a" * 601)
    assert_equal [ [ "too_long", 601, 600 ] ], warnings.map { |w| [ w.code, w.length, w.max ] }
    assert_equal [ "blaming_phrase", "too_long" ], Comments::ReplyLint.call("Non è vero. #{'a' * 600}").map(&:code)
    assert_equal 600, Comments::ReplyLint.max_characters
  end

  test "a reply with warnings is still sent: the dry run and the confirmed reply both carry them" do
    comment = make_comment
    text = "Hai sbagliato tu: il tuo browser non c'entra."
    send_reply(@teacher_token, comment, text)
    assert_response :success
    assert_equal false, json["recorded"]
    assert_equal [ "hai sbagliato", "il tuo browser" ], json["warnings"].map { |w| w["phrase"] }
    assert_equal [ "blaming_phrase" ], json["warnings"].map { |w| w["code"] }.uniq
    assert json["warnings"].all? { |w| w["message"].include?("blaming") }
    assert_equal 0, CommentEvent.where(comment: comment).count, "the dry run writes nothing"

    send_reply(@teacher_token, comment, text, confirm: true)
    assert_response :created
    assert_equal true, json["recorded"]
    assert_equal [ "hai sbagliato", "il tuo browser" ], json["warnings"].map { |w| w["phrase"] }
    sent = CommentEvent.where(comment: comment, kind: "reply").last
    assert_equal text, sent.text_it, "the reply went out as written"
    assert_equal "answered", comment.reload.state
  end

  test "a reply over 600 characters warns and is sent; a clean one has an empty list; the other actions carry none" do
    comment = make_comment
    long = "Ecco la spiegazione. #{'parola ' * 100}"
    send_reply(@teacher_token, comment, long, confirm: true)
    assert_response :created
    assert_equal [ "too_long" ], json["warnings"].map { |w| w["code"] }
    assert_equal [ long.strip.length, 600 ], json["warnings"].first.values_at("length", "max")
    assert_equal long.strip, CommentEvent.where(comment: comment, kind: "reply").last.text_it

    other = make_comment
    send_reply(@teacher_token, other, "Guarda l'esempio.")
    assert_equal [], json["warnings"]
    api_as(@teacher_token, "/api/v1/comments/#{other.id}/read", method: :post, body: { confirm: false })
    assert_response :success
    assert_not json.key?("warnings")
  end

  test "the console returns the warnings of a reply, a dry run or confirmed, and never refuses for them" do
    comment = make_comment
    result = Comments::Console.call(action: "reply", id: comment.id, teacher: "nik", text_it: "Non hai letto la scheda.")
    assert result.ok
    assert_equal [ "non hai letto" ], result.warnings.map(&:phrase)
    result = Comments::Console.call(action: "reply", id: comment.id, teacher: "nik", text_it: "Non hai letto la scheda.", confirm: true)
    assert result.ok && result.recorded
    assert_equal [ "non hai letto" ], result.warnings.map(&:phrase)
    assert_equal [], Comments::Console.call(action: "resolve", id: comment.id, teacher: "nik", confirm: false).warnings
  end

  test "the rake task prints the warnings before it sends, and still sends with CONFIRM=1; show prints the context" do
    Rake::Task.clear
    Rails.application.load_tasks
    comment = practice_comment
    saved = ENV.to_h.slice("ID", "TEACHER", "TEXT_IT", "CONFIRM")
    ENV.update("ID" => comment.id.to_s, "TEACHER" => "nik", "TEXT_IT" => "Se ricordi cosa volevi dire, scrivilo.")
    ENV.delete("CONFIRM")
    out, err = capture_io { Rake::Task["banco:comments:reply"].reenable; Rake::Task["banco:comments:reply"].invoke }
    assert_match(/warning: reads as blaming the student: «se ricordi»/, err)
    assert_match(/dry run/, out)
    assert_equal 0, CommentEvent.where(comment: comment).count
    ENV["CONFIRM"] = "1"
    out, err = capture_io { Rake::Task["banco:comments:reply"].reenable; Rake::Task["banco:comments:reply"].invoke }
    assert_match(/warning: .*«se ricordi»/, err)
    assert_match(/recorded reply/, out)
    assert_equal [ "Se ricordi cosa volevi dire, scrivilo." ], CommentEvent.where(comment: comment, kind: "reply").map(&:text_it)

    ENV["TEXT_IT"] = "Guarda l'esempio."
    ENV["ID"] = comment.id.to_s
    _, err = capture_io { Rake::Task["banco:comments:reply"].reenable; Rake::Task["banco:comments:reply"].invoke }
    assert_equal "", err

    out, = capture_io { Rake::Task["banco:comments:show"].reenable; Rake::Task["banco:comments:show"].invoke }
    context = JSON.parse(out[/^\{.*\z/m])["context"]
    assert_equal [ "99999 parola-sua" ], context["tries"]["behind_the_comment"].map { |r| r["answer"] }, "the console is the teacher's: his words"
    assert_equal @item.id, context["revision"]["item"]["current_revision_id"]
  ensure
    %w[ID TEACHER TEXT_IT CONFIRM].each { |k| saved&.key?(k) ? ENV[k] = saved[k] : ENV.delete(k) }
  end

  # ---- «In scadenza» ---------------------------------------------------------------------------------------

  test "the digest lists the threads that wait with the hours left, soonest first, and the follow-ups" do
    fresh = make_comment(created_at: 2.hours.ago)
    late = make_comment(created_at: 36.hours.ago)
    thread = make_comment(created_at: 40.hours.ago)
    event(thread, "reply", at: 39.hours.ago, text: "Guarda.")
    event(thread, "student_reply", at: 8.hours.ago, text: "Ma non torna.")
    answered = make_comment(created_at: 3.hours.ago)
    event(answered, "reply", at: 2.hours.ago, text: "Fatto.")
    closed = make_comment(created_at: 50.hours.ago)
    event(closed, "resolved", at: 1.hour.ago)

    %w[bot_read teacher].each do |role|
      api_as(role == "teacher" ? @teacher_token : @bot, "/api/v1/digest")
      assert_response :success, role
      due = json["comments"]["due"]
      assert_equal [ 24, 3, 1, 1 ], due.values_at("within_hours", "waiting", "late", "followups"), role
      assert_equal [ late.id, thread.id, fresh.id ], due["rows"].map { |r| r["id"] }, "late first, then the soonest due"
      assert_in_delta(-12.0, due["rows"][0]["due_in_hours"], 0.1)
      assert_equal [ true, false ], due["rows"][0].values_at("late", "student_followup")
      assert_equal [ false, true ], due["rows"][1].values_at("late", "student_followup")
      assert_in_delta 16.0, due["rows"][1]["due_in_hours"], 0.1
      assert_equal "student", due["rows"][2]["student"]
      assert_not_includes due["rows"].map { |r| r["id"] }, answered.id
      assert_not_includes due["rows"].map { |r| r["id"] }, closed.id
    end
    api_as(@bot, "/api/v1/comments")
    by_id = json["comments"].index_by { |c| c["id"] }
    assert_equal [ true, true ], [ by_id[thread.id]["student_followup"], by_id[thread.id]["due_in_hours"].between?(15.9, 16.1) ]
    assert_not by_id[answered.id].key?("due_in_hours")
    assert_not by_id[late.id].key?("student_followup")
  end

  test "the teacher's inbox has «In scadenza»: the waiting threads with the hours left, a follow-up marked; a guest sees none of it" do
    fresh = make_comment(created_at: 2.hours.ago, text_it: "Da poco.")
    late = make_comment(created_at: 36.hours.ago)
    thread = make_comment(created_at: 40.hours.ago)
    event(thread, "reply", at: 39.hours.ago, text: "Guarda.")
    event(thread, "student_reply", at: 8.hours.ago, text: "Ma non torna.")
    answered = make_comment(created_at: 3.hours.ago)
    event(answered, "reply", at: 2.hours.ago, text: "Fatto.")

    on(:web, "/teacher/comments", headers: TEACHER, remote_addr: EDGE)
    assert_response :success
    assert_select "#comment-due-title", "In scadenza"
    assert_select "#comment-due[data-due-waiting='3'][data-due-followups='1']"
    assert_equal [ late.id, thread.id, fresh.id ], css_select("#comment-due-list li").map { |li| li["data-due-comment"].to_i }
    assert_select "#comment-due-list li[data-due-comment='#{late.id}'][data-due-late=true]", /in ritardo di 12 ore/
    assert_select "#comment-due-list li[data-due-comment='#{thread.id}'][data-due-followup=true]", /16 ore rimaste/
    assert_select "#comment-due-list li[data-due-comment='#{thread.id}'] .comment-followup", "Ha scritto dopo la tua risposta"
    assert_select "#comment-due-list li[data-due-comment='#{fresh.id}'][data-due-followup=false]", /21 ore rimaste|22 ore rimaste/
    assert_select "#comment-due-list li[data-due-comment='#{answered.id}']", 0

    on(:web, "/teacher/comments?state=answered", headers: TEACHER, remote_addr: EDGE)
    assert_select "#comment-due-list li", 3, "the panel does not follow the filters"

    on(:web, "/teacher/comments", headers: GUEST, remote_addr: EDGE)
    assert_select "#comment-due", 0
    assert_not_includes response.body, "Da poco."
  end

  # ---- D-380: the context on the teacher's card (the page, not only the API) -------------------------------------

  test "the card of a comment on an exercise with tries shows the revision he saw, his tries with his words, his earlier comments" do
    earlier = practice_comment(text_it: "Prima volta.", created_at: 2.days.ago)
    event(earlier, "reply", at: 2.days.ago + 600, text: "Guardo subito.")
    comment = practice_comment(text_size: "smallest", theme: "dark", viewport_width: 1759, viewport_height: 979)
    newest = newer_item_revision

    on(:web, "/teacher/comments", headers: TEACHER, remote_addr: EDGE)
    assert_response :success
    assert_select "#comment-#{comment.id} .comment-meta", /Schermo 1759×979, tema scuro, testo molto piccolo/
    assert_not_includes response.body, "tema dark"
    assert_not_includes response.body, "testo smallest"
    assert_select "#comment-#{comment.id} details.comment-context[data-exercise=true][data-changed=true]" do
      assert_select "summary", /Contesto: revisione cambiata da allora · \d+ tentativ\w+ · 1 commento precedente/
      assert_select "[data-context=revision]", /Revisione dell'esercizio che aveva davanti: #{@item.seq}\.\s+Ora c'è la revisione #{newest.seq}: è cambiata da allora/
      assert_select "[data-context=tries-behind]", /Tentativi dietro il commento/
      assert_select "ol li[data-try=?]", "practice-#{@try.id}", /Esercizi · sbagliata · tentativo #{@try.try_number}\s+Risposta: «99999 parola-sua»/
      assert_select "[data-earlier-comment='#{earlier.id}']", /Prima volta\.\s+Risposta: Guardo subito\./
    end
  end

  def matching_try
    item = Item.create!(subject: @subject, key: "match-demo-1", kind: "practice_item")
    body = { schema: "banco.item/1", schema_version: 1, kind: "practice_item", subject: "math", skill: SKILL, component: "matching", level: 1,
             expected_seconds: 60, hints_it: [], error_catalogue: [] }
    revision = ItemRevision.create!(item: item, seq: 1, body_json: JSON.generate(body), file_sessions_json: "{}")
    ItemValidation.create!(item_revision: revision, seq: 1, status: "passed", codes_json: "[]")
    left = %w[dimora desinare volto].each_with_index.map { |text, i| { id: "l#{i + 1}", text: text } }
    right = %w[aulico medio popolare comune].each_with_index.map { |text, i| { id: "r#{i + 1}", text: text } }
    instance = ItemInstance.create!(item_revision: revision, seed: 1, display_json: JSON.generate(stem_it: "Abbina le parole al loro registro.", left: left, right: right),
                                    answer_json: JSON.generate(l1: "r3", l2: "r1", l3: "r4"), errors_json: "[]", hints_json: "[]",
                                    solution_json: JSON.generate(steps: [], final: "x"), fingerprint: Digest::SHA256.hexdigest("match-demo-1"))
    serve = make_serve(@official, @topic_revision, instance, skill_key: SKILL, at: 2.days.ago)
    try = make_try(serve, raw: JSON.generate(l1: "r3", l2: "r2", l3: "r4"), verdict: "wrong", at: 2.days.ago + 60)
    comment = make_comment(practice_serve: serve, item_instance: instance, item_revision: revision, page_kind: "practice", page_path: PRACTICE_PATH,
                           anchor: "exercise/item/answer/row:2", text_it: "La seconda riga è giusta, mi sembra.")
    [ comment, try ]
  end

  test "the card shows a matching try and the row of the anchor in words, never the stored data; the API's context stays raw" do
    comment, try = matching_try

    on(:web, "/teacher/comments", headers: TEACHER, remote_addr: EDGE)
    assert_response :success
    assert_select "#comment-#{comment.id} details.comment-context li[data-try=?]", "practice-#{try.id}" do |rows|
      text = rows.first.text.squish
      assert_includes text, "Risposta: «dimora – popolare; desinare – medio; volto – comune»"
      assert_includes text, "Riga segnata: «desinare» · ha dato «medio», atteso «aulico»"
    end
    card = css_select("#comment-#{comment.id} details.comment-context").first.to_s
    assert_not_includes card, "{"
    assert_not_includes card, "&quot;"
    assert_no_match(/\b[lr]\d\b/, css_select("#comment-#{comment.id} details.comment-context").first.text)

    row = read_context(@teacher_token, comment)["tries"]["behind_the_comment"].first
    assert_equal JSON.generate(l1: "r3", l2: "r2", l3: "r4"), row["answer"]
    assert_equal({ "segment" => "row:2", "n" => 2, "column" => "left", "shown_id" => "l2", "stored_id" => "l2", "text" => "desinare", "resolved" => true,
                   "given_text" => "medio", "key_text" => "aulico" }, row["anchor_row"])
    assert_equal Comments::Context.new(comment, words: true).to_h.deep_stringify_keys["tries"], read_context(@teacher_token, comment)["tries"]
  end

  test "a typed answer reads as it is, and an answer that does not read in words says so in a short line, never its data" do
    comment = practice_comment
    make_try(@serve, try_number: 2, raw: JSON.generate(l1: "r4"), verdict: "wrong", at: 3.days.ago + 120)

    on(:web, "/teacher/comments", headers: TEACHER, remote_addr: EDGE)
    assert_select "#comment-#{comment.id} li[data-try=?]", "practice-#{@try.id}", /Risposta: «99999 parola-sua»/
    assert_select "#comment-#{comment.id} li[data-try]", /Risposta: non si legge in parole/
    card = css_select("#comment-#{comment.id} details.comment-context").first.to_s
    assert_not_includes card, "r4"
    assert_not_includes card, "&quot;"
  end

  test "the card of a comment on an exercise with no try and no earlier comment says so in one line each" do
    comment = make_comment(item_revision: @revisions[1], page_kind: "practice", page_path: PRACTICE_PATH, anchor: "exercise/item")

    on(:web, "/teacher/comments", headers: TEACHER, remote_addr: EDGE)
    assert_select "#comment-#{comment.id} details.comment-context[data-exercise=true][data-changed=false][data-tries='0'][data-earlier='0']" do
      assert_select "summary", /Contesto: revisione ancora quella attuale · nessun tentativo · nessun commento precedente/
      assert_select "[data-context=revision]", /È ancora l'ultima/
      assert_select "[data-context=tries-none]", "Nessun tentativo dello studente su questo esercizio."
      assert_select "[data-context=earlier-none]", "Nessun commento precedente su questo esercizio."
    end
  end

  test "a comment on no exercise has the context too, without the exercise lines, and an unsent screen setting is named «non indicato»" do
    comment = make_comment(theme: nil, text_size: nil, viewport_width: nil, viewport_height: nil)

    on(:web, "/teacher/comments", headers: TEACHER, remote_addr: EDGE)
    assert_select "#comment-#{comment.id} .comment-meta", /Schermo non indicato, tema non indicato, testo non indicato/
    assert_select "#comment-#{comment.id} details.comment-context[data-exercise=false]" do
      assert_select "[data-context=tries-none]", 0
      assert_select "[data-context=earlier-none]", "Nessun commento precedente su questa pagina."
    end
  end

  test "every theme and size a student can choose is named in Italian on the card, never by its stored code" do
    names = { "cream" => "crema", "light" => "chiaro", "dark" => "scuro", "auto" => "automatico" }
    sizes = { "minimum" => "minimo", "tiny" => "piccolissimo", "smallest" => "molto piccolo", "small" => "piccolo", "normal" => "normale", "large" => "grande", "larger" => "molto grande" }
    helper = ApplicationController.helpers
    names.each { |code, word| assert_includes helper.comment_device_line(make_comment(theme: code)), "tema #{word}" }
    sizes.each { |code, word| assert_includes helper.comment_device_line(make_comment(text_size: code)), "testo #{word}" }
  end

  test "an inbox with nothing waiting says so" do
    answered = make_comment
    event(answered, "reply", text: "Fatto.")
    on(:web, "/teacher/comments", headers: TEACHER, remote_addr: EDGE)
    assert_select "#comment-due-empty", /Nessun commento aspetta/
  end

  test "the late mark counts from the first message without a reply, so a follow-up does not restart the clock" do
    thread = make_comment(created_at: 60.hours.ago)
    event(thread, "reply", at: 50.hours.ago, text: "Guarda.")
    event(thread, "student_reply", at: 30.hours.ago, text: "Non torna.")
    event(thread, "student_reply", at: 1.hour.ago, text: "Aiuto?")
    thread = Comment.find(thread.id)
    assert thread.late?
    assert_in_delta 30.hours.ago.to_f, thread.waiting_since.to_f, 5
    assert_equal 1, Comments::Inbox.counts["late"]
    assert_equal "student_reply", thread.last_message.event.kind
  end
end
