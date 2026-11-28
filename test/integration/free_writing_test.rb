require "test_helper"
require_relative "../support/decision_world"
require_relative "../support/multi_user"
require_relative "../support/public_api_tokens"
require_relative "../support/writing_world"

# D-407, free writing corrected by the teacher: the student sends a text of his own on a writing task of a topic (an idempotent POST), sees it as sent, the
# teacher corrects it with the decision `correct_writing` (her own words: the browser and the console, never the API), the student sees the correction under his
# text and sends a new version. A writing task is never an exercise: no serve, no try, no skill state, nothing of the topic's completion.
class FreeWritingTest < ActionDispatch::IntegrationTest
  include DecisionWorld
  include MultiUser
  include PublicApiTokens
  include WritingWorld

  JSON_HEADERS = { "Content-Type" => "application/json", "Accept" => "application/json" }.freeze
  TEXT = "Ho spostato il sette a destra e ho diviso per tre. Poi ho fatto la verifica.".freeze
  CORRECTION = "Bene i passaggi. Attento: «ho fatto la verifica» va dopo il risultato.".freeze

  # DecisionWorld turns CSRF protection on and restores it; saving it again here under the same name would restore it as on.
  setup { build_writing_world }

  # ---- helpers -------------------------------------------------------------------------------------------

  def wid = "w-" + SecureRandom.hex(8)

  def token_for(headers, path = "/today")
    on(:web, path, headers: headers, remote_addr: EDGE)
    css_select("meta[name=csrf-token]").first&.[]("content").to_s
  end

  def post_json(headers, path, body = {}, token: nil)
    token ||= token_for(headers)
    on(:web, path, method: :post, headers: headers.merge(JSON_HEADERS, "X-CSRF-Token" => token), params: body.to_json, remote_addr: EDGE)
    response.parsed_body
  end

  # The student's POST of a text; the default is the official student's first task.
  def write(text = TEXT, headers: OFFICIAL, path: writings_path, **extra)
    post_json(headers, path, { client_writing_id: wid, item_revision_id: @task.id, text: text }.merge(extra))
  end

  def page(headers, path) = on(:web, path, headers: headers, remote_addr: EDGE)

  # The teacher's own computer is not the student's: the cookie that his pages leave in this session would refuse the decision (D-08).
  def correct!(submission, text = CORRECTION)
    cookies.delete("banco_device")
    decide("/teacher/writing-submissions/#{submission.id}/correct", { text_it: text })
  end

  def console = DecisionRecorder::Console.new(login: "nik", os_user: "tester")

  def snapshot(except = %w[writing_submissions students app_events decisions])
    (ActiveRecord::Base.connection.tables - except - %w[schema_migrations ar_internal_metadata sqlite_sequence]).to_h do |t|
      [ t, ActiveRecord::Base.connection.select_value("SELECT COUNT(*) FROM #{t}") ]
    end
  end

  # ---- the student sends a text ---------------------------------------------------------------------------

  test "the topic page draws «Scrivi tu» after the exercises with the task, the range, a box and no draft of the server" do
    page(OFFICIAL, topic_path)
    assert_response :success
    assert_select "section#writing h2", "Scrivi tu"
    assert_select "#writing .writing-task[data-writing-task='#{TASK_KEY}'][data-state=new]", 1
    assert_select "#writing-1-stem", TASK_TEXT
    assert_select "#writing .writing-range", "Da 20 a 60 parole."
    assert_select "#writing form.writing-form:not([hidden]) textarea[maxlength='4000']"
    assert_select "#writing form button[type=submit]", "Consegna"
    assert_select "#writing .writing-sent[hidden]"
    assert_no_match(/Guarda se nomina la verifica/, response.body, "the teacher's notes are never served to the student")
    assert_select "#writing[data-comment-anchor=writing]"
  end

  # D-410: the advice of the item's `answer_format_*` (the rubric grades what it asks for) is drawn under the task, as the practice page draws it.
  test "the writing block shows the answer format of an Italian task as a plain line under the task, before the range, with no translation and nothing to open" do
    page(OFFICIAL, topic_path)
    assert_response :success
    assert_select "#writing-1[data-controller='writing markup']", 1, "the task is drawn again with the items' markup by the page's markup controller"
    assert_select "#writing-1-stem[data-markup=block]", TASK_TEXT
    assert_select "#writing-1-stem + p.answer-format[data-markup=inline] + p.writing-range", 1
    assert_select "#writing-1 p.answer-format", TASK_FORMAT
    assert_select "#writing-1 p.answer-format[lang]", 0, "an Italian format carries no language of its own"
    assert_select "#writing-1 .tr", 0, "an Italian task has no translation to offer"
    assert_select "#writing-1 details, #writing-1 button.tr-toggle", 0, "a plain line, not a collapsible"
  end

  test "a bilingual task shows the stem and the answer format in the language he studies, each with its Italian in a translation node" do
    task = make_writing_item("eng-write-1", prompt: { stem_en: "Describe your day.\n\n1. Where are you?\n2. What do you do?", stem_it: "Descrivi la tua giornata." },
                                            format_it: "Scrivi al presente e usa «and», «then», «but».",
                                            extra: { bilingual: true, answer_format_en: "Write in the present simple and use \"and\", \"then\", \"but\"." })
    english = Struct.new(:topic_revision, :lang).new(make_writing_topic(@practice_topic, [ task ]), "en")
    shown = Writings::StudentBlock.new(@official, english)
    assert shown.translations?, "the page offers the «Traduzione» button"
    html = ApplicationController.render(partial: "topics/writing_prompt", locals: { prompt: shown.tasks.sole.prompt, id: "writing-1" })
    fragment = Nokogiri::HTML5.fragment(html)
    assert_select fragment, "#writing-1-stem[lang=en][data-markup=block]", text: /Describe your day\./
    assert_select fragment, "#writing-1-stem + .tr[lang=it][data-nospeech][data-markup=inline]", text: "Descrivi la tua giornata."
    assert_select fragment, "p.answer-format[lang=en][data-markup=inline]", text: "Write in the present simple and use \"and\", \"then\", \"but\"."
    assert_select fragment, "p.answer-format + .tr[lang=it][data-markup=inline]", text: "Scrivi al presente e usa «and», «then», «but»."
    assert_select fragment, "p.answer-format ~ p.writing-range", text: "Da 20 a 60 parole."

    # an item with no english format keeps the Italian one alone; a task of a topic that teaches no language ignores the target keys
    plain = Writings::Prompt.of({ "prompt" => { "stem_it" => "Scrivi." }, "answer_format_it" => "Usa il presente.", "words_min" => 5, "words_max" => 9 }, "en")
    assert_equal [ "Scrivi.", nil, nil, "Usa il presente.", nil, nil ], plain.to_h.values_at(:stem, :stem_tr, :lang, :format, :format_tr, :format_lang)
    none = Writings::Prompt.of({ "prompt" => { "stem_it" => "Scrivi." }, "words_min" => 5, "words_max" => 9 }, nil)
    assert_nil none.format
    html = ApplicationController.render(partial: "topics/writing_prompt", locals: { prompt: none, id: "writing-1" })
    assert_select Nokogiri::HTML5.fragment(html), ".answer-format", 0
    assert_not none.translations?
  end

  test "a topic with no writing task has no block" do
    page(OFFICIAL, "/subjects/math")
    assert_response :success
    plain = TopicRevision.find(@practice_topic.id)
    approve_topic!(plain) # the latest approval is the one he is shown
    page(OFFICIAL, topic_path)
    assert_select "#writing", 0
    assert_select "#skills .skill", 1
  end

  test "sending a text records one row: derived from what he was shown, word count, idempotent on the client id" do
    id = wid
    reply = write(client_writing_id: id)
    assert_response :success
    assert_equal "recorded", reply["status"]
    row = WritingSubmission.sole
    assert_equal [ @official.id, @topic_revision.id, @task.id, id, TEXT, 16 ], [ row.student_id, row.topic_revision_id, row.item_revision_id, row.client_writing_id, row.text, row.word_count ]
    assert_equal({ "id" => row.id, "item_revision_id" => @task.id, "text" => TEXT, "word_count" => 16 }, reply["submission"])

    assert_no_difference "WritingSubmission.count" do
      2.times { assert_equal reply, write(client_writing_id: id) }
    end
  end

  test "after sending, the page says «Consegnato» and shows the text read-only; no form, no new-version button" do
    write
    page(OFFICIAL, topic_path)
    assert_select "#writing .writing-task[data-state=sent]"
    assert_select "#writing form.writing-form[hidden]"
    assert_select "#writing .writing-sent:not([hidden]) .writing-note", "Consegnato. Lo corregge il docente."
    assert_select "#writing .writing-sent .writing-text", TEXT
    assert_select "#writing .writing-correction[hidden]"
    assert_select "#writing button[data-writing-target=again][hidden]"
  end

  test "an empty text and a text over 4000 characters are refused; 4000 is accepted; the page keeps the words" do
    [ "", "   \n  " ].each do |blank|
      reply = write(blank)
      assert_response :unprocessable_entity
      assert_equal [ "invalid", "empty" ], reply.values_at("status", "error")
    end
    reply = write("a" * 4001)
    assert_response :unprocessable_entity
    assert_equal [ "invalid", "too_long" ], reply.values_at("status", "error")
    assert_equal 0, WritingSubmission.count
    assert_equal "recorded", write("a" * 4000)["status"]
    assert_equal 4000, WritingSubmission.sole.text.length
  end

  test "the row keeps what the server derived, never the browser's words: another item revision, another topic, an unknown id, a bad client id" do
    other = make_writing_item("math-write-other")
    assert_equal [ "invalid", "item_revision_id" ], write(item_revision_id: other.id).values_at("status", "error")
    assert_equal [ "invalid", "item_revision_id" ], write(item_revision_id: @revisions.first.id).values_at("status", "error"), "an exercise is not a writing task"
    assert_equal [ "invalid", "item_revision_id" ], write(item_revision_id: "x").values_at("status", "error")
    assert_equal [ "invalid", "client_writing_id" ], write(client_writing_id: "no").values_at("status", "error")
    assert_equal [ "invalid", "topic" ], post_json(OFFICIAL, "/topics/lezione.math.unknown/writings", { client_writing_id: wid, item_revision_id: @task.id, text: TEXT }).values_at("status", "error")
    assert_equal 0, WritingSubmission.count
  end

  test "a new text is refused while his latest one waits for the teacher; another student's id is refused" do
    id = wid
    write(client_writing_id: id)
    assert_equal [ "invalid", "pending" ], write.values_at("status", "error")
    assert_response :unprocessable_entity
    on(:web, writings_path, method: :post, headers: TRIAL.merge(JSON_HEADERS, "X-CSRF-Token" => token_for(TRIAL)),
                            params: { client_writing_id: id, item_revision_id: @task.id, text: TEXT }.to_json, remote_addr: EDGE)
    assert_response :unprocessable_entity
    assert_equal "client_writing_id", response.parsed_body["error"]
    assert_equal 1, WritingSubmission.count
  end

  test "the teacher, a guest, nobody and an unmapped login never write as a student; the preview writes only the preview student" do
    body = { client_writing_id: wid, item_revision_id: @task.id, text: TEXT }
    [ GUEST, UNMAPPED ].each do |headers|
      on(:web, writings_path, method: :post, headers: headers.merge(JSON_HEADERS), params: body.to_json, remote_addr: EDGE)
      assert_operator response.status, :>=, 400, headers.inspect
    end
    on(:web, writings_path, method: :post, headers: TEACHER.merge(JSON_HEADERS, "X-CSRF-Token" => csrf_token), params: body.to_json, remote_addr: EDGE)
    assert_response :forbidden
    assert_equal 0, WritingSubmission.count

    reply = post_json(TEACHER, "/teacher/preview#{writings_path}", body, token: csrf_token)
    assert_response :success
    assert_equal "recorded", reply["status"]
    row = WritingSubmission.sole
    assert_equal "preview", row.student.kind
    assert_equal 0, WritingSubmission.where(student: @official).count
    page(TEACHER, "/teacher/preview#{topic_path}")
    assert_select "#writing .writing-task[data-state=sent]"
    # the student's own page is untouched by it
    page(OFFICIAL, topic_path)
    assert_select "#writing .writing-task[data-state=new]"
  end

  test "the ledger refuses to change or delete a text" do
    write
    assert_raises(ActiveRecord::StatementInvalid) { WritingSubmission.first.update_columns(text: "altro") }
    assert_raises(ActiveRecord::StatementInvalid) { WritingSubmission.first.delete }
    assert_equal TEXT, WritingSubmission.sole.text
  end

  # ---- the teacher corrects --------------------------------------------------------------------------------

  test "the teacher corrects through the decision; the row says who, from where and what; the student sees it under his text" do
    write
    submission = WritingSubmission.sole
    assert_difference "Decision.where(kind: 'correct_writing').count", 1 do
      correct!(submission)
    end
    assert_response :success
    decision = Decision.where(kind: "correct_writing").sole
    assert_equal [ "nik", "banco-teacher", @official, @subject ], [ decision.teacher_login, decision.groups, decision.student, decision.subject ]
    assert_equal({ "writing_submission_id" => submission.id, "topic" => TOPIC, "item" => TASK_KEY, "text_it" => CORRECTION }, JSON.parse(decision.payload_json))

    page(OFFICIAL, topic_path)
    assert_select "#writing .writing-task[data-state=corrected]"
    assert_select "#writing .writing-sent .writing-text", TEXT
    assert_select "#writing .writing-correction:not([hidden]) .writing-correction-text", CORRECTION
    assert_select "#writing button[data-writing-target=again]:not([hidden])", "Scrivi una nuova versione"
    assert_select "#writing form.writing-form[hidden]"
  end

  test "Oggi says a correction is new until the student opens the topic page, which records an app event; nothing for the preview" do
    write
    submission = WritingSubmission.sole
    page(OFFICIAL, "/today")
    assert_select ".writing-today", 0
    correct!(submission)
    page(OFFICIAL, "/today")
    assert_select ".writing-today[data-topic='#{TOPIC}'] strong", /Il docente ha corretto un tuo testo/
    assert_select ".writing-today a[href$='/topics/#{TOPIC}#writing']", "Leggi la correzione"
    page(OFFICIAL, "/today")
    assert_select ".writing-today", 1, "reading Oggi opens nothing"

    assert_difference -> { AppEvent.where(kind: "writing_correction_seen", student: @official).count }, 1 do
      page(OFFICIAL, topic_path)
    end
    assert_no_difference -> { AppEvent.where(kind: "writing_correction_seen").count } do
      page(OFFICIAL, topic_path)
    end
    page(OFFICIAL, "/today")
    assert_select ".writing-today", 0
    event = AppEvent.where(kind: "writing_correction_seen").sole
    assert_equal({ "writing_submission_id" => submission.id, "decision_id" => Decision.where(kind: "correct_writing").sole.id }, JSON.parse(event.payload_json))

    # a corrected correction is new again
    correct!(submission, "Meglio così: «dopo il risultato».")
    page(OFFICIAL, "/today")
    assert_select ".writing-today", 1
    page(TEACHER, "/teacher/preview/today")
    assert_select ".writing-today", 0
  end

  test "the student sends a new version after the correction: a new row, the old one stays, the page shows both" do
    write
    first = WritingSubmission.sole
    correct!(first)
    assert_difference "WritingSubmission.count", 1 do
      assert_equal "recorded", write("Seconda versione, con la verifica dopo il risultato.")["status"]
    end
    second = WritingSubmission.order(:id).last
    assert_equal [ TEXT, "Seconda versione, con la verifica dopo il risultato." ], WritingSubmission.order(:id).pluck(:text)
    assert_equal first.item_revision_id, second.item_revision_id

    page(OFFICIAL, topic_path)
    assert_select "#writing .writing-task[data-state=sent] .writing-sent .writing-text", "Seconda versione, con la verifica dopo il risultato."
    assert_select "#writing .writing-correction[hidden]"
    assert_select "#writing details.writing-versions summary", "Le versioni di prima (1)"
    assert_select "#writing .writing-version[data-version='1'] .writing-correction-text", CORRECTION
    assert_equal [ "invalid", "pending" ], write("Una terza.").values_at("status", "error"), "the second one waits for the teacher too"
  end

  test "the student's English interface draws the block in English" do
    Diagnosis::Preferences.record(@official, language: "en")
    page(OFFICIAL, topic_path)
    assert_select "section#writing h2", "Write it yourself"
    assert_select "#writing form button[type=submit]", "Send it in"
    assert_select "#writing .writing-range", "From 20 to 60 words."
  end

  # ---- the decision's guards ------------------------------------------------------------------------------

  test "the guards of every decision hold: guest, the student's device, no CSRF, the flag off, a bad id, an empty or over-long correction" do
    write
    submission = WritingSubmission.sole
    path = "/teacher/writing-submissions/#{submission.id}/correct"
    cookies.delete("banco_device")
    decide(path, { text_it: CORRECTION }, headers: GUEST)
    assert_response :forbidden
    decide(path, { text_it: CORRECTION }, headers: OFFICIAL)
    assert_response :forbidden
    decide(path, { text_it: CORRECTION }, headers: TEACHER.merge("Cookie" => "banco_device=x"))
    assert_response :forbidden
    decide(path, { text_it: CORRECTION }, csrf: false)
    assert_response :forbidden
    %i[api harness].each do |listener|
      decide(path, { text_it: CORRECTION }, listener: listener)
      assert_response :not_found, listener
    end
    ENV["BANCO_DECISIONS_ENABLED"] = "0"
    decide(path, { text_it: CORRECTION })
    assert_response :forbidden
    ENV["BANCO_DECISIONS_ENABLED"] = "1"
    assert_equal 0, Decision.where(kind: "correct_writing").count

    decide(path, { text_it: "  " })
    assert_response :unprocessable_entity
    decide(path, { text_it: "x" * (WritingSubmission::CORRECTION_MAX + 1) })
    assert_response :unprocessable_entity
    decide("/teacher/writing-submissions/99999/correct", { text_it: CORRECTION })
    assert_response :not_found
    assert_equal 0, Decision.where(kind: "correct_writing").count
  end

  test "the form without a script goes back to the page with a sentence in Italian; a refusal is worded too" do
    write
    submission = WritingSubmission.sole
    cookies.delete("banco_device")
    token = csrf_token
    on(:web, "/teacher/writing-submissions/#{submission.id}/correct", method: :post, headers: TEACHER,
                                                                  params: { text_it: CORRECTION, back: "/teacher/writings", authenticity_token: token }, remote_addr: EDGE)
    assert_redirected_to "/teacher/writings"
    assert_equal "Correzione registrata: lo studente la vede sotto il suo testo.", flash[:notice]
    on(:web, "/teacher/writing-submissions/#{submission.id}/correct", method: :post, headers: TEACHER, params: { text_it: "", back: "/teacher/writings", authenticity_token: token }, remote_addr: EDGE)
    assert_redirected_to "/teacher/writings"
    assert_equal "Scrivi la correzione.", flash[:alert]
    assert_equal 1, Decision.where(kind: "correct_writing").count
  end

  test "a correction is a person's: the API refuses the kind, a dry run included, with a teacher token; the console records it" do
    write
    submission = WritingSubmission.sole
    refute_includes DecisionRecorder::Api::KINDS, "correct_writing"
    assert_includes DecisionRecorder::KINDS, "correct_writing"
    teacher = issue_token("teacher")
    [ nil, true ].each do |confirm|
      assert_no_difference "Decision.count" do
        api_as(teacher, "/api/v1/decisions", method: :post, body: { kind: "correct_writing", params: { writing_submission_id: submission.id, text_it: CORRECTION }, confirm: confirm })
      end
      assert_includes [ 403, 422 ], response.status
    end

    dry = DecisionConsole.call(kind: "correct_writing", teacher: "nik", params: { writing_submission_id: submission.id, text_it: CORRECTION }, confirm: false)
    assert dry.ok, dry.errors.inspect
    assert_equal 0, Decision.where(kind: "correct_writing").count
    done = DecisionConsole.call(kind: "correct_writing", teacher: "nik", params: { writing_submission_id: submission.id, text_it: CORRECTION }, confirm: true)
    assert done.ok, done.errors.inspect
    decision = Decision.where(kind: "correct_writing").sole
    assert_predicate decision, :console?
    assert_equal [ "console", CORRECTION ], [ JSON.parse(decision.payload_json)["via"], JSON.parse(decision.payload_json)["text_it"] ]
    page(OFFICIAL, topic_path)
    assert_select "#writing .writing-correction-text", CORRECTION
    refused = DecisionConsole.call(kind: "correct_writing", teacher: "nobody", params: { writing_submission_id: submission.id, text_it: CORRECTION }, confirm: true)
    assert_not refused.ok
  end

  test "the preview student's text is not corrected" do
    post_json(TEACHER, "/teacher/preview#{writings_path}", { client_writing_id: wid, item_revision_id: @task.id, text: TEXT }, token: csrf_token)
    submission = WritingSubmission.sole
    correct!(submission)
    assert_response :unprocessable_entity
    assert_equal 0, Decision.where(kind: "correct_writing").count
  end

  # ---- the teacher's page ---------------------------------------------------------------------------------

  test "«Testi da correggere» lists the pending texts first, then the corrected ones, with the task, the notes and the form" do
    write
    first = WritingSubmission.sole
    correct!(first)
    write("Seconda versione: ho fatto tutto.")
    second = WritingSubmission.order(:id).last

    cookies.delete("banco_device")
    page(TEACHER, "/teacher/writings")
    assert_response :success
    assert_select "h1", "Testi da correggere"
    assert_select "#writings-summary", "Da correggere: 1. Corretti: 1."
    ids = css_select("article.writing-entry").map { |a| a["data-writing-submission"].to_i }
    assert_equal [ second.id, first.id ], ids, "pending first"
    assert_select "article#writing-#{second.id}[data-status=pending]" do
      assert_select "[data-writing-task-text]", TASK_TEXT
      assert_select "[data-writing-notes]", /Guarda se nomina la verifica/
      assert_select "[data-student-text]", "Seconda versione: ho fatto tutto."
      assert_select "form[action='/teacher/writing-submissions/#{second.id}/correct'] textarea[name=text_it][required]"
      assert_select "form button:not([disabled])", "Invia la correzione"
    end
    assert_select "article#writing-#{first.id}[data-status=corrected]" do
      assert_select "[data-writing-correction]", CORRECTION
      assert_select "form textarea[name=text_it]", CORRECTION
    end
    assert_select "#menu-writings[href='/teacher/writings']", "Testi da correggere"
  end

  test "a guest reads the page without the form; the default is the official student and ?student=KEY picks a trial one; an unknown key is a 404" do
    write
    page(GUEST, "/teacher/writings")
    assert_response :success
    assert_select "article.writing-entry", 1
    assert_select "article.writing-entry form", 0
    assert_select "[data-student-text]", TEXT

    trial_text = "Il mio testo di prova."
    on(:web, writings_path, method: :post, headers: TRIAL.merge(JSON_HEADERS, "X-CSRF-Token" => token_for(TRIAL)),
                            params: { client_writing_id: wid, item_revision_id: @task.id, text: trial_text }.to_json, remote_addr: EDGE)
    assert_response :success
    page(TEACHER, "/teacher/writings")
    assert_select "[data-student-text]", count: 1, text: TEXT
    page(TEACHER, "/teacher/writings?student=prova-1")
    assert_select "[data-student-text]", count: 1, text: trial_text
    page(TEACHER, "/teacher/writings?student=nobody")
    assert_response :not_found
    page(OFFICIAL, "/teacher/writings")
    assert_response :forbidden
  end

  test "the Cruscotto counts the texts that wait and says it in «Da fare adesso»; the count falls when the teacher corrects" do
    page(TEACHER, "/teacher")
    assert_select "[data-count=writings] b", "0"
    write
    page(TEACHER, "/teacher")
    assert_select "[data-count=writings] b", "1"
    assert_select "[data-count=writings] span", "Testi da correggere"
    assert_select "#todo-list li[data-todo=writings]", /Un testo scritto dallo studente da correggere/
    correct!(WritingSubmission.sole)
    page(TEACHER, "/teacher")
    assert_select "[data-count=writings] b", "0"
    assert_select "#todo-list li[data-todo=writings]", 0
  end

  test "the teacher's topic page shows the writing task with its range and notes, in the review, beside the exercises" do
    cookies.delete("banco_device")
    page(TEACHER, "/teacher/subjects/math/topics/#{TOPIC}")
    assert_response :success
    assert_select "#topic-writing[aria-labelledby]" do
      assert_select "[data-writing-task='#{@task.id}']", 1
      assert_select "[data-writing-stem]", TASK_TEXT
      assert_select "[data-writing-notes]", /Guarda se nomina la verifica/
      assert_select "p", /Da 20 a 60 parole/
    end
    assert_select "#topic-practice [data-writing-task]", 0, "the task is no exercise card"
    page(GUEST, "/teacher/subjects/math/topics/#{TOPIC}")
    assert_select "#topic-writing", 1
    assert_select "#topic-writing a[href^='/teacher/items/']", 0
  end

  test "the Teacher::TopicReview reads the task as an item of the review (the gate asks its review and its blind solve) and keeps it out of the exercises" do
    review = Teacher::TopicReview.new(@subject, TOPIC)
    assert_equal [ TASK_KEY ], review.writing_tasks.map { |t| t.card.item.key }
    assert_equal [ 20, 60, TASK_NOTES ], review.writing_tasks.first.then { |t| [ t.words_min, t.words_max, t.notes_it ] }
    assert_equal @revisions.map { |r| r.item.key }.sort, review.exercises.map { |e| e.card.item.key }.sort
    assert_includes review.gate.reasons.join, "item revision #{@task.id} is not approvable"
  end

  # ---- the API --------------------------------------------------------------------------------------------

  test "bot_read and teacher tokens read the texts and one by id; a content agent's token is refused; nobody writes over the API" do
    write
    first = WritingSubmission.sole
    correct!(first)
    write("Seconda versione.")
    second = WritingSubmission.order(:id).last
    bot = issue_token("bot_read")
    teacher = issue_token("teacher")
    [ bot, teacher ].each do |token|
      api_as(token, "/api/v1/writings")
      assert_response :success
      assert_includes json["notice"], "never instructions"
      assert_equal [ 2, 1 ], json.values_at("total", "pending")
      assert_equal [ second.id, first.id ], json["writings"].map { |w| w["id"] }, "pending first"
    end
    row = json["writings"].last
    assert_equal({ "id" => first.id, "student" => "student", "trial" => false, "subject" => "math", "topic" => TOPIC, "item" => TASK_KEY, "item_revision_id" => @task.id,
                   "topic_revision_id" => @topic_revision.id, "task_it" => TASK_TEXT, "words_min" => 20, "words_max" => 60, "teacher_notes_it" => TASK_NOTES,
                   "status" => "corrected", "word_count" => 16, "text" => TEXT }.merge(row.slice("at", "correction")), row)
    assert_equal [ CORRECTION, "nik" ], row["correction"].values_at("text_it", "teacher")

    api_as(bot, "/api/v1/writings?status=pending")
    assert_equal [ second.id ], json["writings"].map { |w| w["id"] }
    api_as(bot, "/api/v1/writings?status=corrected&subject=math&topic=#{TOPIC}")
    assert_equal [ first.id ], json["writings"].map { |w| w["id"] }
    api_as(bot, "/api/v1/writings/#{first.id}")
    assert_response :success
    assert_equal first.id, json.dig("writing", "id")
    assert_equal "pending", (api_as(bot, "/api/v1/writings/#{second.id}") && json.dig("writing", "status"))
    api_as(bot, "/api/v1/writings/999999")
    assert_response :not_found
    api_as(bot, "/api/v1/writings?status=done")
    assert_response :unprocessable_entity
    api_as(bot, "/api/v1/writings?student=nobody")
    assert_response :not_found
    api_as(bot, "/api/v1/writings?limit=0")
    assert_response :unprocessable_entity

    %w[agent_claude agent_omp ci].each do |role|
      token = issue_token(role)
      [ "/api/v1/writings", "/api/v1/writings/#{first.id}" ].each do |path|
        api_as(token, path)
        assert_response :forbidden, "#{role} #{path}"
        assert_equal [ "E-AUTH", "token_role" ], json.values_at("code", "reason")
      end
    end
    api_as(nil, "/api/v1/writings")
    assert_response :unauthorized
    api_as(bot, "/api/v1/writings", method: :post, body: { text: "x" })
    assert_includes [ 403, 404, 405 ], response.status
  end

  test "the teacher's topic over the API lists the writing tasks beside the exercises, with the gate and the notes" do
    api_as(issue_token("bot_read"), "/api/v1/teacher/subjects/math/topics/#{TOPIC}")
    assert_response :success
    task = json["writing"].sole
    assert_equal [ TASK_KEY, @task.id, TASK_TEXT, 20, 60, TASK_NOTES ], task.values_at("item", "revision_id", "task_it", "words_min", "words_max", "teacher_notes_it")
    assert_equal false, task.dig("gate", "approvable")
    assert_equal @revisions.map { |r| r.item.key }.sort, json["exercises"].map { |e| e["item"] }.sort
  end

  test "the contract lists the two read commands and no writing one" do
    api_as(issue_token("bot_read"), "/api/v1/schema")
    commands = json["commands"].select { |c| c["name"].start_with?("writings") }
    assert_equal [ "writings list", "writings show" ], commands.map { |c| c["name"] }.sort
    assert_equal %w[GET GET], commands.map { |c| c["method"] }
  end

  # ---- a writing task is not an exercise ------------------------------------------------------------------

  test "a writing task never enters the practice: no serve for it, the topic's skills and status are the same, and a text changes nothing else" do
    before_status = nil
    view = ->(student) { Course::StudentView.new(student) }
    topic = view.call(@official).find_topic(TOPIC).last
    before_status = view.call(@official).status(topic)
    assert_equal [ SKILL ], topic.skills
    assert_equal [ SKILL ], Course::Catalog.skills_of(@topic_revision)
    assert_raises(Practice::Selector::NotPinned) { serve!(student: @official, topic: @topic_revision, skill: SKILL, item: TASK_KEY) }
    assert_equal @revisions.map { |r| r.item.key }.sort, @topic_revision.body["practice"].flat_map { |p| p["items"].map { |i| i["item"] } }.sort

    snapshot_before = snapshot
    write
    correct!(WritingSubmission.sole)
    write("Una nuova versione.")
    page(OFFICIAL, topic_path)
    assert_equal snapshot_before, snapshot, "no row of the practice, the diagnosis, the lessons or the course changed"
    after = view.call(@official).find_topic(TOPIC).last
    assert_equal before_status, view.call(@official).status(after), "the topic is neither started nor done because of a text"
    assert_empty PracticeServe.where(student: @official)
    assert_empty PracticeAttempt.where(student: @official)

    # the practice page of the skill still serves only the exercises
    page(OFFICIAL, "/topics/#{TOPIC}/practice/#{SKILL}")
    assert_response :success
    assert_no_match(/#{TASK_TEXT}/, response.body)
  end

  test "the student's texts are never indexed by search: not a Searchable, named by no builder or scope, and a teacher's search does not find one" do
    refute_includes WritingSubmission.ancestors, Searchable
    sources = Dir[Rails.root.join("app/models/search/**/*.rb").to_s, Rails.root.join("app/models/search.rb").to_s].map { |f| File.read(f) }.join("\n")
    assert_no_match(/WritingSubmission|writing_submissions/, sources)
    write
    page(TEACHER, "/teacher/search?q=verifica")
    assert_response :success
    assert_no_match(/Ho spostato il sette a destra/, response.body)
  end
end
