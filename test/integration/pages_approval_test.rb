require "test_helper"
require_relative "../support/decision_world"
require_relative "../support/multi_user"
require_relative "../support/topic_world"
require_relative "../support/practice_rows"
require_relative "../support/page_world"

# Free pages and the teacher's approval (D-261, D-289, SPEC B8): approve_topic carries one explicit confirmation per pinned page
# ("Ho provato ..."), the gate asks for a passed validation and an independent review of each, and what the click covers is what the
# page shows and teaches, not its code.
class PagesApprovalTest < ActionDispatch::IntegrationTest
  include DecisionWorld
  include MultiUser
  include TopicWorld
  include PracticeRows
  include PageWorld

  setup do
    ENV["BANCO_TEACHER_USERS"] = "nik,teacher-a@example.test"
    @world = build_ui_subject(approve: false)
    @subject = @world[:subject]
    build_topic_world
    @page = store_page!
    body = JSON.parse(@lesson_revision.body_json).merge(
      "schema" => "banco.lesson/2",
      "cards" => [ { "n" => 1, "id" => "c1", "role" => "idea", "level" => "extra", "title_it" => "Prova",
                     "blocks" => [ { "n" => 1, "type" => "page", "page" => "math.pages-sample", "revision" => @page.id, "caption_it" => "Prova tu." } ] } ]
    )
    md = "---\nkey: #{TOPIC_KEY}\n---\n"
    @lr2 = LessonRevision.create!(lesson: @lesson_revision.lesson, seq: 2, source_md: md, source_sha256: Digest::SHA256.hexdigest(md), body_json: JSON.generate(body),
                                  rules_version: Validation::Rules.version.to_s, warnings_json: "[]")
    review_lesson!(@lr2)
    LessonRender.create!(lesson_revision: @lr2, status: "passed", rules_version: "9", harness_version: "t", chrome_version: "t", attempt: 1, result_json: "{}", shots_json: "[]")
    @topic2 = make_topic(@lr2, { "math.number" => @topic_items }, course: @topic.course_revision)
    record_viewed!(@topic2)
  end

  def reasons(**options) = Approval::TopicGate.check(@topic2, confirm_seen: true, **options).reasons
  def approve(params = {}) = decide("/teacher/topic-revisions/#{@topic2.id}/approve", { confirm_seen: "1" }.merge(params))

  def review_page!(severity: nil, session: page_reviewer!)
    findings = severity ? [ { "severity" => severity, "file" => "main.mjs", "line" => 1, "quote" => "banco", "problem_it" => "Problema.", "fix_it" => "Correggi." } ] : []
    PageReview.create!(page_revision: @page, agent_session: session, checklist_json: "[]", findings_json: JSON.generate(findings))
  end

  test "the gate asks, in order, for a passed validation, an independent review, no blocker, and the teacher's tick" do
    assert_includes reasons, "the page math.pages-sample (revision #{@page.id}) has not passed validation in Chrome"
    PageValidation.create!(page_revision: @page, kit_version: "1.0", status: "failed", harness_version: "t", result_json: "{}", shots_json: "[]")
    assert_includes reasons, "the page math.pages-sample (revision #{@page.id}) has not passed validation in Chrome"
    pass_page!(@page)
    assert_includes reasons, "the page math.pages-sample (revision #{@page.id}) has no review by an independent session"
    review_page!(severity: "blocker")
    assert_includes reasons, "the page math.pages-sample (revision #{@page.id}) has 1 blocker finding(s) in its latest review"
    review_page!
    assert_equal [ "the teacher did not confirm having tried the page math.pages-sample (revision #{@page.id})" ], reasons
    assert_empty reasons(pages_confirmed: [ @page.id ])
    assert_empty reasons(pages_confirmed: [ @page.id.to_s ])
  end

  test "a major finding of the page review needs the same written reason as a lesson finding" do
    pass_page!(@page)
    review_page!(severity: "major")
    assert_includes reasons(pages_confirmed: [ @page.id ]), Approval::TopicGate::REASON_NEEDED
    assert_empty reasons(pages_confirmed: [ @page.id ], lesson_findings_reason_it: "Il difetto è piccolo e l'ho visto.")
  end

  test "approve_topic records pages_confirmed in the decision; without the tick it is refused with the page named" do
    pass_page!(@page)
    review_page!
    approve
    assert_response :unprocessable_entity
    assert(json["reasons"].any? { |r| r.include?("did not confirm having tried the page") })
    assert_difference "Decision.where(kind: 'approve_topic').count", 1 do
      approve(pages_confirmed: [ @page.id ])
    end
    assert_response :success
    payload = JSON.parse(Decision.where(kind: "approve_topic").last.payload_json)
    assert_equal [ @page.id ], payload["pages_confirmed"]
    approve(pages_confirmed: [ "x" ])
    assert_response :unprocessable_entity
  end

  test "a topic without a free page has no pages_confirmed in its decision and needs no tick" do
    record_viewed!(@topic)
    decide("/teacher/topic-revisions/#{@topic.id}/approve", { confirm_seen: "1" })
    assert_response :unprocessable_entity, "the older revision is not the latest"
    plain = make_topic(lesson_revision_with_body!("ripasso.math.plain", "math.number"), { "math.number" => @topic_items }, course: @topic.course_revision)
    assert_empty Approval::TopicGate.page_revisions(plain)
    assert_empty Approval::TopicGate.unconfirmed_pages(plain, [])
  end

  test "the topic page shows one box per page, in the teacher's words, and the page line of the box" do
    pass_page!(@page, shots: [])
    review_page!
    open_topic_page!(headers: TEACHER)
    assert_response :success
    assert_select "input[name='pages_confirmed[]'][value='#{@page.id}']", 1
    assert_select "label", /Ho provato «Due rette che si incontrano»/
    assert_select "#pages-line li[data-page='math.pages-sample'][data-state='passed']", /controllo passato \(kit 1\.0\), 1 riviste/
    assert_select "#approve-checks [data-check='pages']"
  end

  test "the Italian wording of the page reasons" do
    names = {}
    [ "the page math.pages-sample (revision 3) has not passed validation in Chrome", "the page math.pages-sample (revision 3) has no review by an independent session",
      "the page math.pages-sample (revision 3) has 2 blocker finding(s) in its latest review", "the teacher did not confirm having tried the page math.pages-sample (revision 3)" ].each do |reason|
      text = Teacher::Wording.italian(reason, names)
      assert_match(/pagina interattiva math.pages-sample/, text, reason)
    end
  end

  test "no new decision kind: the approval of the topic carries the confirmation of the pages" do
    assert_equal 19, DecisionRecorder::KINDS.size
    assert_empty DecisionRecorder::KINDS.grep(/page/i)
  end
end
