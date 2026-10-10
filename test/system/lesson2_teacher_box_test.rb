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
end
