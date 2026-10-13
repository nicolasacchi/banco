require "test_helper"
require_relative "../support/multi_user"
require_relative "../support/lesson_events_world"

# T2 (D-283): a check with the `listen` option. The text of what is heard is served (behind "Mostra il testo" in the page); an answer sent after the
# text was shown is recorded as text_shown in the check_answered row, and only for a check that has the option; the glossary of the front matter is
# served to the student and the lists of words the lesson teaches stay with the author.
class LessonListenTest < ActionDispatch::IntegrationTest
  include MultiUser
  include LessonEventsWorld

  JSON_HEADERS = { "Content-Type" => "application/json", "Accept" => "application/json" }.freeze

  def post_json(headers, path, body = {})
    on(:web, "/today", headers: headers, remote_addr: EDGE)
    token = css_select("meta[name=csrf-token]").first&.[]("content")
    on(:web, path, method: :post, headers: headers.merge(JSON_HEADERS, "X-CSRF-Token" => token.to_s), params: body.to_json, remote_addr: EDGE)
    response.parsed_body
  end

  def check_url(card, block) = "/topics/#{TOPIC}/lesson/checks/#{card}/#{block}"
  def cid = "e-" + SecureRandom.hex(8)

  setup do
    build_student_world(approve: true, release: true)
    @card, @block, = find_block { |_, b| b["type"] == "check" && b["component"] == "choice" }
    body = JSON.parse(@lesson_revision.body_json)
    body["cards"].find { |c| c["n"] == @card }["blocks"].find { |b| b["n"] == @block }["listen"] = { "text_en" => "I will call you when I get home." }
    body["glossary"] = [ { "term_it" => "presente", "def_it" => "Il tempo del verbo adesso." } ]
    body["teaches_en"] = %w[quokka]
    @lesson_revision = LessonRevision.create!(lesson: @lesson, seq: 2, source_md: "---\n", source_sha256: "1" * 64, rules_version: Validation::Rules.version.to_s,
                                              warnings_json: "[]", body_json: JSON.generate(body))
    @topic_revision = TopicRevision.create!(lesson: @lesson, seq: 2, course_revision: @course, lesson_revision: @lesson_revision, body_json: @topic_revision.body_json)
    approve_topic!(@topic_revision)
  end

  test "the page is told the text to hear and the glossary, and not the words the lesson teaches" do
    served = Lessons::StudentBody.project(@lesson_revision.body, revision_id: @lesson_revision.id, seed: "s")
    check = served["cards"].find { |c| c["n"] == @card }["blocks"].find { |b| b["n"] == @block }
    assert_equal({ "text_en" => "I will call you when I get home." }, check["listen"])
    assert_equal [ { "term_it" => "presente", "def_it" => "Il tempo del verbo adesso." } ], served["glossary"]
    assert_not served.key?("teaches_en")
    assert_not check.key?("answer")
  end

  test "an answer after the text was looked at is recorded as text_shown, an answer by ear is not, and a check without the option never is" do
    wrong = shown_id(@official, @card, @block, "a")
    by_ear = post_json(OFFICIAL, check_url(@card, @block), { response: wrong, try: 1, client_event_id: cid })
    assert_equal "wrong", by_ear["verdict"]
    post_json(OFFICIAL, check_url(@card, @block), { response: wrong, try: 2, client_event_id: cid, text_shown: true })
    rows = LessonEvent.where(kind: "check_answered").order(:id)
    assert_nil rows.first.payload["text_shown"]
    assert_equal true, rows.last.payload["text_shown"]
    other_card, other_block, = find_block { |c, b| b["type"] == "check" && b["component"] == "number" && !(c["n"] == @card && b["n"] == @block) }
    post_json(OFFICIAL, check_url(other_card, other_block), { response: "999", try: 1, client_event_id: cid, text_shown: true })
    assert_nil LessonEvent.where(kind: "check_answered").order(:id).last.payload["text_shown"], "the check has no listen option: nothing to record"
  end
end
