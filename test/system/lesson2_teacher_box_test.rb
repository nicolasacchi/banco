require "application_system_test_case"
require_relative "../support/decision_world"
require_relative "../support/student_session"
require_relative "../support/topic_world"
require_relative "../support/lesson2_page_world"

# The teacher's box (A14, R2): the topic page draws a lesson/2 with the student's renderer, live, in a box whose
# width, theme and text size the teacher picks. Nothing is recorded by it.
class Lesson2TeacherBoxTest < ApplicationSystemTestCase
  include DecisionWorld
  include StudentSession
  include TopicWorld

  # TopicWorld stores a lesson/1 body; this stores the served lesson/2 fixture under the topic's key.
  def lesson_revision_with_body!(key, skill)
    lesson = Lesson.find_by(key: key) || Lesson.create!(subject: Subject.find_by!(key: key.split(".", 3)[1]), key: key, kind: "ripasso")
    md = "---\nkey: #{key}\n---\n"
    body = JSON.parse(File.read(Rails.root.join("test/fixtures/lesson2/served/equations.json"))).merge("key" => key, "skills" => [ skill ])
    LessonRevision.create!(lesson: lesson, seq: 1, source_md: md, source_sha256: Digest::SHA256.hexdigest(md), body_json: JSON.generate(body),
                           rules_version: Validation::Rules.version.to_s, warnings_json: "[]")
  end

  setup do
    unless defined?(Lessons::StudentBody)
      skip "Lessons::StudentBody is not loaded"
    end
    @world = build_ui_subject(approve: false)
    @subject = @world[:subject]
    @graph = SkillGraphRevision.where(subject: @subject).order(:seq).last
    build_topic_world
    sign_in_as :teacher
  end

  teardown { sign_out_env }

  test "the box shows the student's cover, navigates, and switches width, theme and size" do
    page.driver.resize(1280, 900) # the window another test left narrow would clamp the 390 box
    visit "/teacher/subjects/math/topics/#{TopicWorld::TOPIC_KEY}"
    assert_selector ".l2-box [data-ready='1']", wait: 20
    assert_selector ".l2-box .l2-cover h1", text: "Equazioni di primo grado intere"
    find(".l2-box .l2-start").click
    assert_selector ".l2-box .l2-counter", text: "Scheda 1 di 11"
    choose "390"
    assert_equal 390, page.evaluate_script("document.querySelector('.l2-box').getBoundingClientRect().width").round
    choose "Scuro"
    assert_equal "dark", find(".l2-box")["data-theme"]
    choose "Più grande"
    assert_selector ".l2-box[data-size=larger]"
    # nothing leaves the box: no event and no question address is in its configuration
    assert_equal 0, page.evaluate_script("document.querySelectorAll('.l2-box .question').length")
    # the teacher mode reads full.json (R3); its own test with a body that has answers is in lesson_events_system_test.rb
    check "Modalità docente"
    assert_no_selector "[data-lesson2-preview-target=status]", text: "Le risposte non sono disponibili ora."
  end

  test "the render line names the errors by card, and its link opens the box on that card" do
    revision = @topic.lesson_revision
    LessonRender.create!(lesson_revision: revision, status: "failed", harness_version: "x", chrome_version: "Test", attempt: 1, shots_json: "[]",
                         result_json: JSON.generate("errors" => [ { "code" => "E-DIAGRAM-LAYOUT", "card" => 3, "viewport" => "390x844-cream", "message" => "two labels overlap" } ]))
    visit "/teacher/subjects/math/topics/#{TopicWorld::TOPIC_KEY}"
    assert_selector ".l2-box [data-ready='1']", wait: 20
    assert_selector "#render-line[data-render-state=failed]", text: "Controllo grafico: 1 errore."
    assert_selector "#render-line", text: "le scritte del disegno non stanno"
    if (dir = ENV["BANCO_SHOT_DIR"].presence)
      FileUtils.mkdir_p(dir)
      page.driver.resize(1280, 1000)
      sleep 0.6
      page.driver.save_screenshot(File.join(dir, "teacher-render-line-failed.png"), selector: "#render-line")
    end
    find("#render-line a[data-card='3']").click
    assert_selector ".l2-box .l2-counter", text: "Scheda 3 di 11"
  end

  test "a passed render says so in one line with the count and the link to the pictures" do
    revision = @topic.lesson_revision
    shots = (1..35).map { |i| { "card" => (i % 11) + 1, "viewport" => "390x844-cream", "sha256" => (i.to_s * 64)[0, 64] } }
    LessonRender.create!(lesson_revision: revision, status: "passed", harness_version: "x", attempt: 1, result_json: "{}", shots_json: JSON.generate(shots))
    visit "/teacher/subjects/math/topics/#{TopicWorld::TOPIC_KEY}"
    assert_selector "#render-line[data-render-state=passed]", text: "Controllo grafico: nessun errore (35 immagini)"
    assert_selector "#render-line a[href='/teacher/lesson-revisions/#{revision.id}/shots']", text: "Vedi le immagini"
    if (dir = ENV["BANCO_SHOT_DIR"].presence)
      FileUtils.mkdir_p(dir)
      page.driver.resize(1280, 1000)
      sleep 0.6
      page.driver.save_screenshot(File.join(dir, "teacher-render-line-passed.png"), selector: "#render-line")
    end
  end

  # A 1 x 1 lossless WebP: the page of the pictures only needs files that exist.
  PIXEL = Base64.decode64("UklGRhoAAABXRUJQVlA4TA0AAAAvAAAAEAcQERGIiP4HAA==")

  test "the page of the pictures lists every card at its viewports, and says when a file was removed" do
    dir = Dir.mktmpdir("lesson-shots")
    ENV["BANCO_LESSON_SHOTS_DIR"] = dir
    revision = @topic.lesson_revision
    kept = LessonShots.put(PIXEL)
    shots = [ [ 1, "390x844-cream" ], [ 1, "1280x800-cream" ], [ 1, "1280x800-dark" ], [ 2, "390x844-cream" ] ].map do |card, viewport|
      { "card" => card, "level" => "core", "viewport" => viewport, "sha256" => card == 2 ? "e" * 64 : kept, "bytes" => PIXEL.bytesize, "width" => viewport.to_i, "height" => 900 }
    end
    LessonRender.create!(lesson_revision: revision, status: "passed", harness_version: "x", attempt: 1, result_json: "{}", shots_json: JSON.generate(shots))
    visit "/teacher/lesson-revisions/#{revision.id}/shots"
    assert_selector "h1", text: "Immagini della lezione"
    assert_selector "section.shots-card", count: 2
    assert_selector "figure img", count: 3
    assert_selector "figcaption", text: "1280 px, scuro"
    assert_text "immagine rimossa"
    assert_selector "h2", text: "Scheda 1: I pezzi di un'equazione"
  ensure
    ENV.delete("BANCO_LESSON_SHOTS_DIR")
    FileUtils.rm_rf(dir) if dir
  end
end
