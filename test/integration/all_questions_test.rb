require "test_helper"
require_relative "../support/decision_world"

# The teacher's page of all the questions of one entry test (operator request 2026-10-07):
# every pinned item with every instance, read-only, answers behind a toggle, every item
# counted as opened, and a guarded confirmation.
class AllQuestionsTest < ActionDispatch::IntegrationTest
  include DecisionWorld

  PATH = "/teacher/subjects/math/test/all".freeze

  setup do
    build_decision_world
    @student_headers = { "Remote-User" => "student", "Remote-Groups" => "banco-student" }
  end

  def page(headers: TEACHER) = on(:web, PATH, headers: headers, remote_addr: EDGE)

  test "the teacher gets the page; the student, an outsider and the other listeners do not" do
    page
    assert_response :success
    page(headers: @student_headers)
    assert_response :forbidden
    on(:web, PATH, remote_addr: "127.0.0.1")
    assert_response :forbidden
    on(:api, PATH)
    assert_response :not_found
    on(:harness, PATH)
    assert_response :not_found
    on(:web, "/teacher/subjects/nothing/test/all", headers: TEACHER, remote_addr: EDGE)
    assert_response :not_found
  end

  test "every pinned item is there with every stored instance, grouped by skill, the first open and the others folded" do
    page
    ids = @blueprint.pinned_item_revision_ids
    assert_select "article.q-item", ids.size
    ids.each { |id| assert_select "article.q-item[data-revision='#{id}']" }
    assert_select "section.skill-group", @blueprint.reload && JSON.parse(@blueprint.body_json)["entries"].size
    assert_select "section.skill-group h2", /Abilità number/
    assert_select "section.skill-group .badge[data-scope=studied]"
    assert_select "section.skill-group .badge[data-role=entry]", /Abilità di partenza/
    assert_select "[data-component-badge]", text: "short_answer"
    assert_select "#all-summary", /Revisione #{@blueprint.seq} del test/
    assert_select "#all-summary", /non è ancora approvata/
    ItemRevision.where(id: ids).each do |rev|
      instances = rev.instances.order(:id).to_a
      instances.each { |i| assert_select "article[data-revision='#{rev.id}'] .q-instance[data-instance='#{i.id}']" }
      assert_select "article[data-revision='#{rev.id}'] > .q-instance", 1
      assert_select "article[data-revision='#{rev.id}'] details.q-others .q-instance", instances.size - 1
      assert_select "article[data-revision='#{rev.id}'] details.q-others summary", "Altre #{instances.size - 1} varianti"
    end
    assert_select "details[open]", 0
    assert_select "[data-presentation]", ItemInstance.where(item_revision_id: ids).count
  end

  test "the testlet is one passage with its sub items, in the presentation the browser draws" do
    world = build_ui_subject(key: "chemistry", name: "Chimica", position: 2, components: %w[testlet], approve: false)
    on(:web, "/teacher/subjects/chemistry/test/all", headers: TEACHER, remote_addr: EDGE)
    assert_response :success
    slot = css_select("article[data-component=testlet] [data-presentation]").first
    payload = JSON.parse(slot["data-presentation"])
    assert_equal "testlet", payload["kind"]
    assert_match(/brano/, payload["passage_it"])
    assert_equal 5, payload["sub_items"].size
    assert_equal world[:revisions]["testlet"].instances.count, css_select("article[data-revision='#{world[:revisions]['testlet'].id}'] [data-presentation]").size
  end

  test "keys, typical errors, solutions and rubrics are inside the hidden answers block, never in the visible part" do
    page
    assert_select ".q-answers[hidden]", ItemInstance.count
    assert_select ".q-answers:not([hidden])", 0
    number = @world[:revisions]["number"]
    first = number.instances.order(:id).first
    assert_select "article[data-revision='#{number.id}'] .q-instance[data-instance='#{first.id}'] .q-answers[hidden] [data-key]", JSON.parse(first.answer_json).to_s
    assert_select "article[data-revision='#{number.id}'] .q-answers[hidden] .errors", /adds_wrong: 99/
    assert_select "article[data-revision='#{number.id}'] .q-answers[hidden] .steps li", "Si fa il conto."
    assert_select "article[data-component=short_answer] .q-answers[hidden] .rubric li[data-point=a]", /1 pt.*Dice una cosa/
    assert_select "article[data-component=short_answer] .q-answers[hidden] [data-model-answer]", "Una risposta."
    # Nothing of it outside the hidden blocks.
    visible = Nokogiri::HTML5(response.body).tap { |doc| doc.css(".q-answers").each(&:remove) }
    text = visible.at_css("main").text
    refute_includes text, "adds_wrong"
    refute_includes text, "Si fa il conto."
    refute_includes text, "Una risposta."
    assert_select "input#show-answers[type=checkbox]"
    assert_select "label", /Mostra risposte/
    # The presentation the browser draws carries no key.
    css_select("[data-presentation]").each { |slot| refute_match(/adds_wrong|\"answer\"|solution|model_answer/, slot["data-presentation"]) }
  end

  test "opening the page records teacher_viewed_item for every pinned item, once; the student's computer writes nothing" do
    ids = @blueprint.pinned_item_revision_ids
    assert_difference -> { AppEvent.where(kind: "teacher_viewed_item").count }, ids.size do
      page
    end
    assert_equal ids.sort, Approval::BlueprintGate.viewed_ids.to_a.sort
    assert_no_difference -> { AppEvent.where(kind: "teacher_viewed_item").count } do
      page
    end
    assert_empty Approval::BlueprintGate.check(@blueprint).reasons.grep(/was not opened/)
  end

  test "the student's computer reads the page and writes no viewed event" do
    cookies[:banco_device] = "student"
    assert_no_difference -> { AppEvent.where(kind: "teacher_viewed_item").count } do
      page
    end
    assert_response :success
    assert_select "#all-confirm button[disabled]"
  end

  test "the confirmation form posts the decision for this very revision; once confirmed the button is off" do
    page
    assert_select "#all-confirm form[action='/teacher/blueprint-revisions/#{@blueprint.id}/confirm-reviewed'] button:not([disabled])", "Ho visto tutte le domande di questa prova"
    decide("/teacher/blueprint-revisions/#{@blueprint.id}/confirm-reviewed")
    assert_response :success
    page
    assert_select "#all-confirm[data-confirmed=true] button[disabled]"
    assert_select "#all-confirm", /Hai già confermato/
  end

  test "the test page and each skill page link to it, and the checklist says how the playing condition is met" do
    on(:web, "/teacher/subjects/math/test", headers: TEACHER, remote_addr: EDGE)
    assert_select "a#test-all-link[href='#{PATH}']", "Vedi tutte le domande"
    assert_select "#test-approve-why li", /oppure apri «Tutte le domande»/
    on(:web, "/teacher/subjects/math/test/skills/math.number", headers: TEACHER, remote_addr: EDGE)
    assert_select "a#skill-all-link[href^='#{PATH}#skill-math-number']"
  end
end
