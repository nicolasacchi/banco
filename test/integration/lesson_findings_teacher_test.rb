require "test_helper"
require_relative "../support/decision_world"
require_relative "../support/multi_user"
require_relative "../support/topic_world"
require_relative "../support/lesson_render_world"

# D-313: on the topic page of a lesson/2, the lesson review's findings are listed by card in the lesson box (a link
# opens the box on the card, another reads the finding) and in the findings step with the author's latest answer.
# The answer is the author's word: it decides nothing, for the teacher or the guest.
class LessonFindingsTeacherTest < ActionDispatch::IntegrationTest
  include DecisionWorld
  include MultiUser
  include TopicWorld
  include LessonRenderWorld

  # TopicWorld stores a lesson/1; this stores the served lesson/2 fixture under the topic's key.
  def lesson_revision_with_body!(key, skill)
    lesson = Lesson.find_by(key: key) || Lesson.create!(subject: Subject.find_by!(key: key.split(".", 3)[1]), key: key, kind: "ripasso")
    md = "---\nkey: #{key}\n---\n"
    body = served("equations").merge("key" => key, "skills" => [ skill ])
    LessonRevision.create!(lesson: lesson, seq: (lesson.revisions.maximum(:seq) || 0) + 1, source_md: md, source_sha256: Digest::SHA256.hexdigest(md),
                           body_json: JSON.generate(body), rules_version: Validation::Rules.version.to_s, warnings_json: "[]")
  end

  FINDINGS = [
    { severity: "major", card: 3, block: 1, quote: "peso", problem_it: "Il passaggio non si vede.", fix_it: "Mostra il peso tolto." },
    { severity: "minor", card: 0, quote: "Equazioni", problem_it: "Titolo lungo.", fix_it: "Accorcialo." },
    { severity: "blocker", card: 2, quote: "bilancia", problem_it: "Il conto è sbagliato.", fix_it: "Rifai il conto." }
  ].freeze

  setup do
    ENV["BANCO_TEACHER_USERS"] = "nik,teacher-a@example.test"
    ENV["BANCO_GUEST_USERS"] = "guest-a@example.test"
    @world = build_ui_subject(approve: false)
    @subject = @world[:subject]
    @graph = SkillGraphRevision.where(subject: @subject).order(:seq).last
    build_topic_world(review_findings: FINDINGS)
    author = AgentSession.create!(label: "a", role: "author", agent: "claude-code", model: "claude-opus-5-5")
    @id = ->(n) { "L#{@lesson_review.id}-#{n}" }
    LessonFindingResponse.create!(lesson_review: @lesson_review, finding_n: 1, agent_session: author, stance: "lesson_right",
                                  note_it: "Il peso tolto è nella figura della scheda.")
  end

  test "the lesson box lists the findings by card, with a link to the card and one to the finding" do
    open_topic_page!(headers: TEACHER)
    assert_response :success
    assert_select "#findings-line li[data-box-finding]", 3
    assert_select "#findings-line li[data-box-finding='#{@id.call(1)}'][data-severity=major][data-answered=true]" do
      assert_select "a[data-card='3'][data-action='lesson2-preview#goto']", "Scheda 3: Togli lo stesso peso dai due piatti · blocco 1"
      assert_select "a[href='#lesson-finding-#{@id.call(1)}']"
    end
    assert_select "#findings-line li[data-box-finding='#{@id.call(2)}'] a[data-card='0']", "Copertina"
    assert_select "#findings-line li[data-box-finding='#{@id.call(3)}'][data-answered=false]", /senza risposta/
  end

  test "the findings step shows each finding with its place and the author's answer, or that there is none" do
    open_topic_page!(headers: TEACHER)
    assert_select "#lesson-finding-#{@id.call(1)}" do
      assert_select "[data-place]", "Scheda 3: Togli lo stesso peso dai due piatti · blocco 1"
      assert_select ".author-response[data-response=lesson_right]", /Secondo l'autore la lezione è giusta\.\s*Il peso tolto è nella figura della scheda\./
    end
    assert_select "#lesson-finding-#{@id.call(3)} [data-response=none]", "L'autore non ha ancora risposto."
    assert_select "#topic-review [data-review-findings='3'][data-answered='1']"
    # The guest reads the same answers; the approval still asks the teacher for a reason.
    open_topic_page!(headers: GUEST)
    assert_response :success
    assert_select ".author-response[data-response=lesson_right]", /Il peso tolto/
    assert Approval::TopicGate.findings_need_reason?(@topic)
  end
end
