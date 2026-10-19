require "application_system_test_case"
require_relative "../support/decision_world"
require_relative "../support/topic_world"
require_relative "../support/arbiter_rows"
require_relative "../support/student_session"

# D-316 on the teacher's pages in Chrome: the model of a corrected session beside the declared one, «non indipendente» on a
# review that no longer counts, and the finding card with an old second opinion as history. With BANCO_SHOT_DIR set, it takes
# screenshots of these places at 390 and 1280 px.
class ProvenanceSystemTest < ApplicationSystemTestCase
  include DecisionWorld
  include TopicWorld
  include ArbiterRows
  include StudentSession

  OPUS = "claude-opus-5-5".freeze

  setup do
    @world = build_ui_subject(approve: false)
    @subject = @world[:subject]
    @graph = SkillGraphRevision.where(subject: @subject).order(:seq).last
    @author = AgentSession.create!(label: "a", role: "author", agent: "omp", model: OPUS)
    @checker = AgentSession.create!(label: "r", role: "reviewer", agent: "omp", model: "claude-sonnet-5-5")
    build_topic_world
    lesson = @lesson_revision.lesson
    revision = LessonRevision.create!(lesson: lesson, seq: lesson.revisions.maximum(:seq) + 1, source_md: "x", source_sha256: "0" * 64, body_json: @lesson_revision.body_json,
                                      rules_version: Validation::Rules.version.to_s, warnings_json: "[]", author_session: @author)
    LessonReview.create!(lesson_revision: revision, agent_session: @checker, checklist_json: JSON.generate((1..8).map { |i| { id: i, result: "pass", evidence: "ok #{i}" } }),
                         recomputed_json: "[]", findings_json: "[]")
    make_topic(revision, { "math.number" => @topic_items })
    @normalized = @world[:revisions]["normalized_text"]
    other = AgentSession.create!(label: "o", role: "reviewer", agent: "omp", model: "claude-sonnet-5-5")
    @review = ItemReview.create!(item_revision: @normalized, agent_session: other, checklist_json: "[]")
    @finding = ReviewFinding.create!(item_revision: @normalized, item_review: @review, source: "review", severity: "major", field: "stem", quote: "x", problem_it: "Il testo è ambiguo.", fix_it: "Chiarisci.")
    @checker_review = ItemReview.create!(item_revision: @normalized, agent_session: @checker, checklist_json: "[]")
    @same = ReviewFinding.create!(item_revision: @normalized, item_review: @checker_review, source: "review", severity: "major", field: "stem", quote: "y", problem_it: "Un altro rilievo.", fix_it: "Cambia.")
    assess!(@same, "author_right", session: arbiter_session(FIRST_MODEL), note: "Qui ha ragione l'autore.")
    assess!(@finding, "author_right", session: arbiter_session(FIRST_MODEL), note: "Il testo si legge in un solo modo.")
    assess!(@finding, "finding_right", session: arbiter_session(OLD_SECOND_MODEL), note: "Mi sembra ambiguo.")
    sign_in_as :teacher
  end

  teardown { sign_out_env }

  def shot(name)
    dir = ENV["BANCO_SHOT_DIR"].presence or return
    FileUtils.mkdir_p(dir)
    [ [ 1280, 900, "1280" ], [ 390, 844, "390" ] ].each do |w, h, label|
      page.driver.resize(w, h)
      sleep 0.5
      page.driver.save_screenshot(File.join(dir, "#{name}-#{label}.png"), full: true)
    end
    page.driver.resize(1280, 900)
  end

  test "a corrected session shows both models and non indipendente on the topic page; the finding card shows the history" do
    AgentSessionCorrection.create!(agent_session: @checker, model: OPUS, reason: "il flusso girava su Opus", request_id: "sys-1")
    AgentSessionCorrection.create!(agent_session: AgentSession.find_by!(label: "ui-author"), model: OPUS, reason: "gli autori giravano su Opus", request_id: "sys-2")
    visit "/teacher/subjects/math/topics/#{TopicWorld::TOPIC_KEY}"
    assert_selector "[data-lesson-review] [data-not-independent]", text: "non indipendente"
    assert_selector "[data-lesson-review]", text: "dichiarato: claude-sonnet-5-5, corretto dall'operatore: il flusso girava su Opus"
    shot("topic-review-corrected")
    visit "/teacher/subjects/math/test/skills/math.normalized-text"
    assert_selector "#finding-#{@finding.id} [data-opinion-history=second_opinion]", text: "non più richiesto"
    assert_selector "#finding-#{@finding.id} [data-opinion=first]"
    assert_selector "#finding-#{@same.id} [data-opinion-history=same_model_as_raiser]", text: "stesso modello di chi ha segnalato"
    assert_selector "#finding-#{@same.id} [data-opinion=first]", count: 0
    assert_selector "[data-review-by] [data-not-independent]", text: "non indipendente"
    shot("finding-card-history")
  end
end
