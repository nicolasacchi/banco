require "test_helper"
require_relative "../support/multi_user"
require_relative "../support/student_course_world"

# Practice the student can leave and come back to (D-337): the draft saved on the server, the list of the topic's exercises with what each one
# is, a click that opens an exercise, «Rifai», and the same for the teacher's preview. The addresses are the page's own (the base the view
# gives); the answers are the controller's JSON.
class PracticeNavigationTest < ActionDispatch::IntegrationTest
  include MultiUser
  include StudentCourseWorld

  JSON_HEADERS = { "Content-Type" => "application/json", "Accept" => "application/json" }.freeze
  PREVIEW = "/teacher/preview".freeze
  LONG_STEM = "Una frase molto lunga che non finisce mai e che continua ancora per superare di molto il limite di novanta caratteri del titolo".freeze
  LIST_KEYS = %w[done item n open_serve_id status title_it tried].freeze

  # The world of the student's pages with a second topic revision (approved, the one the student sees) that pins three items: the first of the
  # world (no stem), and two with a prompt stem. The instances show other texts than the prompt's, so the list cannot leak them by accident.
  def build_nav_world
    build_student_world
    @titled = [ make_titled_item("demo-stem-1", "Risolvi $x + 2 = 5$. Poi controlla il risultato."), make_titled_item("demo-stem-2", LONG_STEM) ]
    @pinned = [ @revisions.first, *@titled ]
    topic = make_topic(@lesson_revision, { SKILL => @pinned }, course: @course)
    approve_topic!(topic)
    @pinned_keys = @pinned.map { |r| r.item.key }
  end

  def make_titled_item(key, stem)
    item = Item.create!(subject: @subject, key: key, kind: "practice_item")
    body = { schema: "banco.item/1", schema_version: 1, kind: "practice_item", subject: @subject.key, skill: SKILL, component: "number", level: 1,
             expected_seconds: 60, hints_it: [ "Che cosa guardi prima?" ], error_catalogue: [ { code: "slip", message_it: "Hai sbagliato un segno." } ],
             prompt: { stem_it: stem } }
    revision = ItemRevision.create!(item: item, seq: 1, body_json: JSON.generate(body), file_sessions_json: "{}")
    ItemValidation.create!(item_revision: revision, seq: 1, status: "passed", codes_json: "[]")
    8.times do |i|
      ItemInstance.create!(item_revision: revision, seed: i + 1, display_json: JSON.generate(stem_it: "Istanza riservata #{key} numero #{i}"),
                           answer_json: JSON.generate((i + 2).to_s), errors_json: JSON.generate([ { code: "slip", value: (i + 3).to_s } ]),
                           hints_json: JSON.generate([ "Che cosa guardi prima?" ]), solution_json: JSON.generate(steps: [ { text_it: "Passo.", math: "$x$" } ], final: "$x$"),
                           fingerprint: Digest::SHA256.hexdigest("#{key}-#{i}"))
    end
    revision
  end

  # ---- the page's calls ---------------------------------------------------------------------------------

  # A post as the script does it, with the CSRF token of a page of the same side; the answer as parsed JSON (the status is in `response`).
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

  def serve_for(headers, root: "", **extra) = post_json(headers, "#{root}/practice/serves", { topic: TOPIC, skill: SKILL, **extra }, root: root)
  def draft_for(headers, id, raw, root: "", source: "text") = post_json(headers, "#{root}/practice/serves/#{id}/draft", { raw: raw, source: source }, root: root)
  def list_for(headers, root: "") = get_json(headers, "#{root}/practice/exercises?topic=#{TOPIC}")

  def answer_for(headers, serve, raw, root: "")
    post_json(headers, "#{root}/practice/answers", { serve_id: serve["serve_id"], client_attempt_id: SecureRandom.uuid, raw: raw, source: "text" }, root: root)
  end

  def right_raw(serve) = correct_raw(PracticeServe.find(serve["serve_id"]))
  def item_key_of(serve) = PracticeServe.find(serve["serve_id"]).item_instance.item_revision.item.key

  # {item key => the list's entry} of the world's one skill.
  def entries(list) = list["skills"].first["exercises"].index_by { |e| e["item"] }

  def status_by_item(list) = entries(list).transform_values { |e| e["status"] }

  # ---- drafts -------------------------------------------------------------------------------------------

  test "a draft is saved, left alone when unchanged, refused when too long, and a serve that is closed or another student's is refused" do
    build_nav_world
    serve = serve_for(OFFICIAL)
    id = serve["serve_id"]
    assert_nil serve["draft"]
    assert_equal({ "skill" => SKILL, "item" => item_key_of(serve), "n" => @pinned_keys.index(item_key_of(serve)) + 1 }, serve["exercise"])
    assert_equal "no-store", response.headers["Cache-Control"]

    assert_equal({ "status" => "saved" }, draft_for(OFFICIAL, id, "12"))
    assert_response :success
    assert_equal "no-store", response.headers["Cache-Control"]
    row = PracticeDraft.last
    assert_equal [ @official.id, id, "12", "text" ], [ row.student_id, row.practice_serve_id, row.raw, row.source ]

    assert_equal({ "status" => "unchanged" }, draft_for(OFFICIAL, id, "12"))
    assert_equal 1, PracticeDraft.count, "the same text writes nothing"
    assert_equal({ "status" => "saved" }, draft_for(OFFICIAL, id, "123"))
    assert_equal({ "status" => "saved" }, draft_for(OFFICIAL, id, ""), "an empty raw clears the draft")
    assert_equal({ "status" => "unchanged" }, draft_for(OFFICIAL, id, ""))
    assert_equal 3, PracticeDraft.count

    assert_equal({ "status" => "too_long" }, draft_for(OFFICIAL, id, "x" * 20_001))
    assert_response :unprocessable_entity
    assert_equal 3, PracticeDraft.count
    assert_equal({ "status" => "saved" }, draft_for(OFFICIAL, id, "x" * 20_000))
    assert_equal 4, PracticeDraft.count

    draft_for(OFFICIAL, id, nil)
    assert_response :unprocessable_entity
    assert_equal 4, PracticeDraft.count

    assert_equal({ "status" => "not_found" }, draft_for(TRIAL, id, "7"))
    assert_response :not_found
    assert_equal({ "status" => "not_found" }, draft_for(OFFICIAL, 0, "7"))
    assert_response :not_found
    assert_equal 4, PracticeDraft.count, "another student's serve takes no draft"

    assert_equal "correct", answer_for(OFFICIAL, serve, right_raw(serve))["outcome"]
    assert_equal({ "status" => "closed" }, draft_for(OFFICIAL, id, "7"))
    assert_response :conflict
    assert_equal 4, PracticeDraft.count
  end

  test "a draft written on an abandoned serve is refused as closed" do
    build_nav_world
    id = serve_for(OFFICIAL)["serve_id"]
    travel_to(Time.current + (Practice::Rules::V4::OPEN_SERVE_HOURS + 1).hours) do
      assert_equal({ "status" => "closed" }, draft_for(OFFICIAL, id, "7"))
      assert_response :conflict
    end
    assert_equal 0, PracticeDraft.count
  end

  test "the guest and the teacher have no draft and no list on the student's own addresses" do
    build_nav_world
    id = serve_for(OFFICIAL)["serve_id"]
    [ TEACHER, GUEST ].each do |who|
      post_json(who, "/practice/serves/#{id}/draft", { raw: "7" })
      assert_response :forbidden
      on(:web, "/practice/exercises?topic=#{TOPIC}", headers: who, remote_addr: EDGE)
      assert_response :forbidden
    end
    assert_equal 0, PracticeDraft.count
  end

  test "the official student sees no list before the release, and a topic she cannot see is a 404" do
    build_nav_world
    get_json(OFFICIAL, "/practice/exercises?topic=ripasso.math.nessuno")
    assert_response :not_found
    get_json(OFFICIAL, "/practice/exercises")
    assert_response :not_found
    release_course!(@course, open: false)
    get_json(OFFICIAL, "/practice/exercises?topic=#{TOPIC}")
    assert_response :not_found
  end

  test "the draft comes back in the serve body after a reload, and not after a newer try" do
    build_nav_world
    serve = serve_for(OFFICIAL)
    id = serve["serve_id"]
    draft_for(OFFICIAL, id, "7", source: "mathlive")

    again = serve_for(OFFICIAL)
    assert_equal id, again["serve_id"], "the same open serve"
    assert_equal({ "raw" => "7", "source" => "mathlive" }, again["draft"])
    assert_equal serve["exercise"], again["exercise"]

    draft_for(OFFICIAL, id, "")
    assert_nil serve_for(OFFICIAL)["draft"], "a cleared draft is no draft"
    draft_for(OFFICIAL, id, "7")

    assert_equal "unrecognised", answer_for(OFFICIAL, again, "99999")["outcome"]
    reload = serve_for(OFFICIAL)
    assert_equal id, reload["serve_id"], "one wrong try leaves the serve open"
    assert_nil reload["draft"], "what was typed before the try is not given back"

    assert_equal({ "status" => "saved" }, draft_for(OFFICIAL, id, "7"), "the same text typed after the try is a new draft")
    assert_equal({ "raw" => "7", "source" => "text" }, serve_for(OFFICIAL)["draft"])
    assert_equal 4, PracticeDraft.count
  end

  # ---- the list -----------------------------------------------------------------------------------------

  test "the list: one entry per pinned item in pin order, with a title, the skill and its address" do
    build_nav_world
    list = list_for(OFFICIAL)
    assert_response :success
    assert_equal "no-store", response.headers["Cache-Control"]
    assert_equal %w[skills topic], list.keys.sort
    assert_equal TOPIC, list["topic"]
    assert_equal 1, list["skills"].size
    skill = list["skills"].first
    assert_equal %w[exercises key label_it state state_it url], skill.keys.sort
    assert_equal SKILL, skill["key"]
    assert_equal "/topics/#{TOPIC}/practice/#{SKILL}", skill["url"]
    assert skill["label_it"].present? && skill["state_it"].present?
    assert_equal @pinned_keys, skill["exercises"].map { |e| e["item"] }
    assert_equal [ 1, 2, 3 ], skill["exercises"].map { |e| e["n"] }
    assert skill["exercises"].all? { |e| e.keys.sort == LIST_KEYS }
    assert skill["exercises"].all? { |e| e["status"] == "todo" && e["open_serve_id"].nil? && e["done"].zero? && e["tried"].zero? }

    titles = skill["exercises"].map { |e| e["title_it"] }
    assert_equal "", titles[0], "an item without a stem has no title"
    assert_equal "Risolvi $x + 2 = 5$.", titles[1], "the first sentence, the formula kept"
    assert_operator titles[2].length, :<=, 90
    assert titles[2].end_with?("…")
    cut = titles[2].delete_suffix("…")
    assert LONG_STEM.start_with?(cut)
    assert_equal " ", LONG_STEM[cut.length], "cut at a word"
  end

  test "the list holds no answer, no hint, no error text and no text of an instance" do
    build_nav_world
    serve = serve_for(OFFICIAL)
    draft_for(OFFICIAL, serve["serve_id"], "una risposta a metà")
    answer_for(OFFICIAL, serve, "99999")
    list = list_for(OFFICIAL)
    text = JSON.generate(list)
    ItemInstance.find_each do |instance|
      stem = JSON.parse(instance.display_json)["stem_it"]
      assert_not_includes text, stem, "an instance's text"
    end
    [ "Istanza riservata", "Che cosa guardi prima?", "Hai sbagliato un segno.", "una risposta a metà", "99999", "slip", "answer", "solution", "hint" ].each do |word|
      assert_not_includes text, word
    end
    assert list["skills"].first["exercises"].all? { |e| e.keys.sort == LIST_KEYS }
  end

  test "the statuses go todo, skipped, left, done, and a solution after a try makes an exercise tried" do
    build_nav_world
    assert_equal [ "todo" ], status_by_item(list_for(OFFICIAL)).values.uniq

    first = serve_for(OFFICIAL)
    first_key = item_key_of(first)
    list = list_for(OFFICIAL)
    assert_equal "skipped", entries(list)[first_key]["status"], "served, nothing typed"
    assert_equal first["serve_id"], entries(list)[first_key]["open_serve_id"]
    assert_equal [ "todo" ], status_by_item(list).except(first_key).values.uniq

    # «Salta»: the next exercise opens, the first one stays open
    second = serve_for(OFFICIAL, advance: true)
    second_key = item_key_of(second)
    assert_not_equal first["serve_id"], second["serve_id"]
    assert_not_equal first_key, second_key, "another exercise"
    assert_equal first["serve_id"], entries(list_for(OFFICIAL))[first_key]["open_serve_id"]
    assert_equal [ "skipped", "skipped" ], status_by_item(list_for(OFFICIAL)).values_at(first_key, second_key)
    assert_equal 2, PracticeServe.where(student: @official).count

    # typed something and left: the draft, not a try
    draft_for(OFFICIAL, first["serve_id"], "12")
    after_draft = list_for(OFFICIAL)
    assert_equal [ "left", "skipped" ], status_by_item(after_draft).values_at(first_key, second_key)
    assert_equal 0, entries(after_draft)[first_key]["tried"], "a draft is not a try"
    assert_equal 0, PracticeAttempt.count

    # a click in the list on the first one: its open serve with the draft put back
    reopened = serve_for(OFFICIAL, item: first_key)
    assert_equal first["serve_id"], reopened["serve_id"]
    assert_equal "12", reopened["draft"]["raw"]
    assert_equal first_key, reopened["exercise"]["item"]

    # a wrong try on the second: retry (answered once, can try again; D-339), one try; its solution closes it: tried
    assert_equal "unrecognised", answer_for(OFFICIAL, second, "99999")["outcome"]
    left = list_for(OFFICIAL)
    assert_equal "retry", entries(left)[second_key]["status"]
    assert_equal 1, entries(left)[second_key]["tried"]
    post_json(OFFICIAL, "/practice/serves/#{second['serve_id']}/solution")
    assert_response :success
    tried = list_for(OFFICIAL)
    assert_equal "tried", entries(tried)[second_key]["status"]
    assert_nil entries(tried)[second_key]["open_serve_id"]
    assert_equal [ 0, 1 ], entries(tried)[second_key].values_at("done", "tried")

    # the first one answered right: done
    assert_equal "correct", answer_for(OFFICIAL, reopened, right_raw(reopened))["outcome"]
    done = list_for(OFFICIAL)
    assert_equal "done", entries(done)[first_key]["status"]
    assert_nil entries(done)[first_key]["open_serve_id"]
    assert_equal [ 1, 1 ], entries(done)[first_key].values_at("done", "tried")
    third_key = (@pinned_keys - [ first_key, second_key ]).first
    assert_equal "todo", entries(done)[third_key]["status"]
  end

  test "«Rifai» on a done exercise gives a new serve of the same exercise, and the done stays counted" do
    build_nav_world
    first = serve_for(OFFICIAL)
    key = item_key_of(first)
    assert_equal "correct", answer_for(OFFICIAL, first, right_raw(first))["outcome"]
    assert_equal "done", entries(list_for(OFFICIAL))[key]["status"]

    redo_serve = serve_for(OFFICIAL, item: key)
    assert_response :success
    assert_not_equal first["serve_id"], redo_serve["serve_id"], "a new serve, not the closed one"
    assert_equal key, item_key_of(redo_serve)
    assert_equal key, redo_serve["exercise"]["item"]
    assert_nil redo_serve["draft"]
    entry = entries(list_for(OFFICIAL))[key]
    assert_equal redo_serve["serve_id"], entry["open_serve_id"], "a click resumes the redo"
    assert_equal 1, entry["done"]
    assert_equal "done", entry["status"], "an open serve with nothing typed does not hide the done"
    draft_for(OFFICIAL, redo_serve["serve_id"], "12")
    assert_equal "left", entries(list_for(OFFICIAL))[key]["status"], "typed in the redo: left"

    # a click on an exercise with no open serve opens a new one of that exercise; one that is not pinned is a 404
    other = (@pinned_keys - [ key ]).first
    clicked = serve_for(OFFICIAL, item: other)
    assert_equal other, item_key_of(clicked)
    serve_for(OFFICIAL, item: "demo-item-9")
    assert_response :not_found
    assert_equal({ "status" => "not_found" }, response.parsed_body)
  end

  test "a skip counts for nothing: no try, the skill is not helped" do
    build_nav_world
    serve_for(OFFICIAL)
    serve_for(OFFICIAL, advance: true)
    assert_equal 0, PracticeAttempt.count
    assert_equal 2, PracticeServe.where(student: @official).count
    input = Practice::Loader.for(@official, subject: @subject, skill: SKILL, seeds: false)
    assert_empty input.tries, "a skipped serve has no try"
    assert_equal 2, input.serves.size
    assert_not_equal "demonstrated", Course::StudentView.new(@official).state(SKILL).state
  end

  test "the list tells each student her own statuses" do
    build_nav_world
    serve = serve_for(OFFICIAL)
    assert_equal [ "todo" ], status_by_item(list_for(TRIAL)).values.uniq
    assert_equal "skipped", entries(list_for(OFFICIAL))[item_key_of(serve)]["status"]
    assert_nil entries(list_for(TRIAL))[item_key_of(serve)]["open_serve_id"]
  end

  test "the list follows the topic revision the student sees: a trial student sees the draft's pins, S the approved one" do
    build_nav_world
    newer = make_titled_item("demo-stem-3", "Una terza domanda.")
    make_topic(@lesson_revision, { SKILL => [ *@pinned, newer ] }, course: @course)
    assert_equal @pinned_keys, entries(list_for(OFFICIAL)).keys, "not approved: S does not see it"
    assert_equal [ *@pinned_keys, "demo-stem-3" ], entries(list_for(TRIAL)).keys
    assert_equal [ 1, 2, 3, 4 ], list_for(TRIAL)["skills"].first["exercises"].map { |e| e["n"] }
  end

  # ---- the teacher's preview ------------------------------------------------------------------------------

  test "the preview has the draft and the list on its own addresses and writes only the preview student" do
    build_nav_world
    serve = serve_for(TEACHER, root: PREVIEW)
    assert_response :success
    preview = Student.where(kind: "preview").order(:id).last
    assert_equal [ preview.id ], PracticeServe.pluck(:student_id).uniq

    list = list_for(TEACHER, root: PREVIEW)
    assert_response :success
    skill = list["skills"].first
    assert_equal "#{PREVIEW}/topics/#{TOPIC}/practice/#{SKILL}", skill["url"], "the preview's links stay in the preview"
    assert_equal "skipped", entries(list)[item_key_of(serve)]["status"]

    assert_equal({ "status" => "saved" }, draft_for(TEACHER, serve["serve_id"], "12", root: PREVIEW))
    assert_equal({ "status" => "unchanged" }, draft_for(TEACHER, serve["serve_id"], "12", root: PREVIEW))
    assert_equal "left", entries(list_for(TEACHER, root: PREVIEW))[item_key_of(serve)]["status"]
    assert_equal "12", serve_for(TEACHER, root: PREVIEW)["draft"]["raw"]
    second = serve_for(TEACHER, root: PREVIEW, advance: true)
    assert_not_equal serve["serve_id"], second["serve_id"]
    assert_equal({ "status" => "saved" }, draft_for(TEACHER, second["serve_id"], "5", root: PREVIEW))

    assert_equal [ preview.id ], PracticeDraft.pluck(:student_id).uniq
    assert_equal [ preview.id ], PracticeServe.pluck(:student_id).uniq
    assert_equal 2, PracticeDraft.count
    assert_equal 0, PracticeDraft.where(student: @official).count

    # the official student's own list is untouched, and the preview's serve is not hers
    assert_equal [ "todo" ], status_by_item(list_for(OFFICIAL)).values.uniq
    assert_equal({ "status" => "not_found" }, draft_for(OFFICIAL, serve["serve_id"], "9"))
    assert_response :not_found
    assert_equal 2, PracticeDraft.count

    # and the student's own addresses stay closed to the teacher
    draft_for(TEACHER, serve["serve_id"], "9")
    assert_response :forbidden
    on(:web, "/practice/exercises?topic=#{TOPIC}", headers: TEACHER, remote_addr: EDGE)
    assert_response :forbidden
    assert_equal 2, PracticeDraft.count
  end

  test "the preview's list shows the draft view's pins when the teacher switches to the drafts" do
    build_nav_world
    newer = make_titled_item("demo-stem-3", "Una terza domanda.")
    make_topic(@lesson_revision, { SKILL => [ *@pinned, newer ] }, course: @course)
    assert_equal @pinned_keys, entries(list_for(TEACHER, root: PREVIEW)).keys
    on(:web, "#{PREVIEW}/view", method: :post, headers: TEACHER.merge("X-CSRF-Token" => csrf_for(TEACHER)), params: { view: "drafts" }, remote_addr: EDGE)
    assert_equal [ *@pinned_keys, "demo-stem-3" ], entries(list_for(TEACHER, root: PREVIEW)).keys
  end

  def csrf_for(headers)
    on(:web, "#{PREVIEW}/today", headers: headers, remote_addr: EDGE)
    css_select("meta[name=csrf-token]").first&.[]("content").to_s
  end

  # ---- the title ----------------------------------------------------------------------------------------

  test "the title is the first sentence, at most 90 characters, with the lesson's markup kept whole" do
    title = ->(text) { Practice::Exercises.title_of(text) }
    assert_equal "", title.(nil)
    assert_equal "", title.("   ")
    assert_equal "Di che registro è ogni frase?", title.("Di che registro è ogni frase? Scegli.")
    assert_equal "Che cosa fa $a.b$ qui?", title.("Che cosa fa $a.b$ qui? Poi altro.")
    assert_equal "Leggi [[en:Hi. there]] e rispondi!", title.("Leggi [[en:Hi. there]] e rispondi! Fine.")
    assert_equal "Un peso di 2.5 kg.", title.("Un peso di 2.5 kg. Poi altro.")
    assert_equal "Una frase senza punto", title.("Una frase\nsenza   punto")
    long = "#{'parola ' * 20}$x + y$ fine"
    cut = title.(long)
    assert_operator cut.length, :<=, 90
    assert cut.end_with?("…")
    assert_equal 0, cut.count("$") % 2, "a formula is never cut"
    inside = "#{'parola ' * 10}$#{'x' * 30} + #{'y' * 30}$ fine"
    cut = title.(inside)
    assert_operator cut.length, :<=, 90
    assert_equal 0, cut.count("$") % 2, "a formula that crosses the limit is left out"
  end

  test "the new table is append-only" do
    build_nav_world
    id = serve_for(OFFICIAL)["serve_id"]
    draft_for(OFFICIAL, id, "7")
    row = PracticeDraft.last
    assert_raises(ActiveRecord::StatementInvalid) { PracticeDraft.where(id: row.id).update_all(raw: "8") }
    assert_raises(ActiveRecord::StatementInvalid) { PracticeDraft.where(id: row.id).delete_all }
    assert_equal "7", row.reload.raw
  end
end
