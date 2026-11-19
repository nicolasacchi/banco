require "test_helper"
require_relative "../support/course_rows"
require_relative "../support/topic_world"

# D-374: the independence of a review of a lesson revision is judged against the authors of the revisions after the last
# revision the teacher approved, when that base had an independent review on record; otherwise against every author.
# The write-time refusal (Providers.refusal with the revision) and the read-time counting (Providers.counting) are one rule
# (LessonSessions#model_authors), so they agree.
class LessonDeltaIndependenceTest < ActionDispatch::IntegrationTest
  include CourseRows
  include TopicWorld

  OPUS = "claude-opus-5-5".freeze
  SONNET = "claude-sonnet-5-5".freeze
  KEY = "lezione.math.delta".freeze

  setup do
    @token = ApiToken.issue!(role: "agent_claude", label: "delta test")
    build_course
    @lesson = Lesson.create!(subject: @subject, key: KEY, kind: "lezione")
    @opus_author = session!(:author, OPUS)
    @sonnet_author = session!(:author, SONNET)
  end

  def session!(role, model) = AgentSession.create!(label: "t", role: role.to_s, agent: "test", model: model)

  def revision!(author)
    seq = (@lesson.revisions.maximum(:seq) || 0) + 1
    md = "---\nkey: #{KEY}\n---\n#{seq}"
    LessonRevision.create!(lesson: @lesson, seq: seq, source_md: md, source_sha256: Digest::SHA256.hexdigest(md), author_session: author,
                           body_json: JSON.generate(LESSON_BODY.merge(key: KEY, skills: [ "math.number" ])), rules_version: Validation::Rules.version.to_s, warnings_json: "[]")
  end

  def approve!(revision)
    course = CourseRevision.where(subject: @subject).order(:seq).last || build_course_map(subject: @subject)
    topic = TopicRevision.create!(lesson: @lesson, seq: (@lesson.topic_revisions.maximum(:seq) || 0) + 1, course_revision: course, lesson_revision: revision,
                                  body_json: JSON.generate(schema: "banco.topic/1", key: KEY, practice: []))
    Decision.create!(kind: "approve_topic", subject: @subject, request_id: SecureRandom.hex(4), teacher_login: "teacher", remote_addr: "127.0.0.1",
                     payload_json: JSON.generate(topic_revision_id: topic.id, topic: KEY, seq: topic.seq, lesson_revision_id: revision.id))
  end

  def reviewed!(revision, by) = review_lesson!(revision, session: by)

  def refusal(reviewer, revision) = Providers.refusal(reviewer, item: @lesson, revision: revision)

  def counts?(review) = Providers.counting([ review ], @lesson).any?

  def api_open(reviewer, revision)
    on(:api, "/api/v1/lesson-revisions/#{revision.id}/review", headers: { "Authorization" => "Bearer #{@token}", "X-Banco-Session" => reviewer.id.to_s })
  end

  # Opus authors the base, a sonnet reviewer reviews it, the teacher approves, sonnet authors a new revision.
  def base_then_sonnet_delta
    @base = revision!(@opus_author)
    @base_review = reviewed!(@base, session!(:reviewer, SONNET))
    approve!(@base)
    @delta = revision!(@sonnet_author)
  end

  test "after an independently reviewed approved base, an Opus reviewer of a Sonnet delta is accepted and counts; a Sonnet reviewer is refused" do
    base_then_sonnet_delta
    opus = session!(:reviewer, OPUS)
    sonnet = session!(:reviewer, SONNET)

    assert_nil refusal(opus, @delta)
    assert_match(/different model/, refusal(sonnet, @delta))
    assert counts?(reviewed!(@delta, opus))
    assert_not counts?(reviewed!(@delta, sonnet))
    assert_equal [ @delta.reviews.find_by(agent_session: opus) ], @delta.counting_reviews

    # Sessions that have not reviewed it yet: the API open and submit.
    fresh_opus = session!(:reviewer, OPUS)
    sonnet = session!(:reviewer, SONNET)
    api_open(fresh_opus, @delta)
    assert_response :ok, response.body
    api_open(sonnet, @delta)
    assert_response :unprocessable_entity
    assert_equal "E-PROVIDER-NOT-ALLOWED", response.parsed_body["code"]
    on(:api, "/api/v1/lesson-revisions/#{@delta.id}/review", method: :post, as: :json, params: { review: {} },
                                                                headers: { "Authorization" => "Bearer #{@token}", "X-Banco-Session" => sonnet.id.to_s })
    assert_equal "E-PROVIDER-NOT-ALLOWED", response.parsed_body["code"]
  end

  test "the base: the review of the base itself still follows the old rule (no base before it), yet it qualifies the base for the delta" do
    base_then_sonnet_delta
    assert counts?(@base_review) == false, "today's rule, no base before it: every author of the lesson, the sonnet delta's author among them"
    assert_equal @base, LessonSessions.new(@lesson).base_of(@delta)
    assert_nil LessonSessions.new(@lesson).base_of(@base)
  end

  test "without an approved base the old rule applies: every author of the lesson" do
    base = revision!(@opus_author)
    delta = revision!(@sonnet_author)
    opus = session!(:reviewer, OPUS)
    sonnet = session!(:reviewer, SONNET)
    assert_match(/different model/, refusal(opus, delta))
    assert_match(/different model/, refusal(sonnet, delta))
    assert_not counts?(reviewed!(delta, opus))
    assert_not counts?(reviewed!(delta, sonnet))
    assert_nil LessonSessions.new(@lesson).base_of(delta)
    assert_equal [ @opus_author, @sonnet_author ], LessonSessions.new(@lesson).model_authors(base)
  end

  test "an approved base without a review, or with a review of its own author's model, is no base: the old rule applies" do
    base = revision!(@opus_author)
    approve!(base)
    delta = revision!(@sonnet_author)
    opus = session!(:reviewer, OPUS)
    assert_match(/different model/, refusal(opus, delta), "approved, never reviewed")
    reviewed!(base, session!(:reviewer, OPUS))
    assert_match(/different model/, refusal(opus, delta), "its only review shares the author's model")
    assert_not counts?(reviewed!(delta, opus))
  end

  test "a reviewer on the model of an author of the delta is refused and never counts, even if it authored the base too" do
    @base = revision!(@sonnet_author)
    reviewed!(@base, session!(:reviewer, OPUS))
    approve!(@base)
    delta = revision!(@sonnet_author)
    sonnet = session!(:reviewer, SONNET)
    opus = session!(:reviewer, OPUS)
    assert_match(/different model/, refusal(sonnet, delta))
    assert_not counts?(reviewed!(delta, sonnet))
    assert_nil refusal(opus, delta)
    assert counts?(reviewed!(delta, opus))
  end

  test "the base is the last approved revision before the reviewed one; a revision after it from Opus is part of the delta" do
    base_then_sonnet_delta
    later = revision!(@opus_author)
    opus = session!(:reviewer, OPUS)
    sonnet = session!(:reviewer, SONNET)
    # Delta of `later` since the base: sonnet (the delta) and opus (itself): both models are authors now.
    assert_match(/different model/, refusal(opus, later))
    assert_match(/different model/, refusal(sonnet, later))
    other = session!(:reviewer, "gpt-5.2")
    assert_nil refusal(other, later)
  end

  test "the refusal and the counting agree for every model on every revision" do
    base_then_sonnet_delta
    later = revision!(@opus_author)
    [ @base, @delta, later ].each do |revision|
      [ OPUS, SONNET, "gpt-5.2", "kimi-k3" ].each do |model|
        reviewer = session!(:reviewer, model)
        review = reviewed!(revision, reviewer)
        assert_equal refusal(reviewer, revision).nil?, counts?(review), "#{model} on revision #{revision.seq}"
      end
    end
  end

  test "a later approval does not change how an earlier review counts" do
    base_then_sonnet_delta
    opus = session!(:reviewer, OPUS)
    sonnet = session!(:reviewer, SONNET)
    good = reviewed!(@delta, opus)
    bad = reviewed!(@delta, sonnet)
    approve!(@delta)
    assert counts?(good)
    assert_not counts?(bad)
  end

  test "items keep the rule over every author" do
    item = Item.create!(subject: @subject, key: "delta-item-1", kind: "practice_item")
    body = { schema: "banco.item/1", schema_version: 1, kind: "practice_item", subject: "math", skill: "math.number", component: "number", level: 1, expected_seconds: 60 }
    revision = ItemRevision.create!(item: item, seq: 1, body_json: JSON.generate(body), file_sessions_json: "{}", author_session: @opus_author)
    assert_match(/different model/, Providers.refusal(session!(:reviewer, OPUS), item: item))
    review = ItemReview.create!(item_revision: revision, agent_session: session!(:reviewer, OPUS), checklist_json: "[]")
    assert_not Providers.counting([ review ], item).any?
  end
end
