require "application_system_test_case"
require_relative "../support/lesson2_page_world"
require_relative "../support/student_session"

# What "Ascolta" reads (D-282, WAVE2 4.3 and 5.4): the golden files of test/fixtures/lesson2/speech, one per family gallery and one for the text layer.
# Each card of a gallery is drawn by the student's page in Chrome and lesson/speech.js `speechOf` is asked what it would say, in segments of one language
# each. The lead reads the files (are the numbers, the formulas, the figures said the way a person would say them?) and the operator listens to two of
# them on the student's device. The test fails when what is read changes, so a change is always seen; GOLDEN=1 writes the files again.
class LessonSpeechGoldenSystemTest < ApplicationSystemTestCase
  include Lesson2PageWorld
  include StudentSession

  TRIAL_HEADERS = { "Remote-User" => "trial-x", "Remote-Groups" => "banco-student" }.freeze
  GOLDEN = Rails.root.join("test/fixtures/lesson2/speech")
  GALLERY = Rails.root.join("test/fixtures/lesson2/gallery")
  # name => where the lesson body comes from: a served body of test/fixtures/lesson2/served, or a gallery file parsed
  SOURCES = {
    "text" => [ :served, "text" ], "text_chemistry" => [ :served, "text_chemistry" ],
    "graph" => [ :gallery, "graph.md" ], "chart" => [ :gallery, "chart.md" ], "maps" => [ :gallery, "maps.md" ],
    "docs" => [ :gallery, "docs-lesson.md" ], "computing" => [ :gallery, "computing.md" ]
  }.freeze

  setup do
    @saved_users = ENV["BANCO_STUDENT_USERS"]
    ENV["BANCO_STUDENT_USERS"] = "trial-x=prova-1"
  end

  teardown do
    begin
      page.driver.resize(1280, 900)
    rescue StandardError
      nil
    end
    sign_out_env
    @saved_users ? ENV["BANCO_STUDENT_USERS"] = @saved_users : ENV.delete("BANCO_STUDENT_USERS")
  end

  def lesson_body = @golden_body

  def body_of(name)
    kind, file = SOURCES.fetch(name)
    return served_body(file).merge("key" => TOPIC) if kind == :served

    Lessons::Parser2.call(GALLERY.join(file).read, Validation::Findings.new, allow_reserved: true).body.merge("key" => TOPIC)
  end

  def go(n) = page.execute_script("window.lessonApi.goTo(#{n}, { focus: true })")

  def read_card(n)
    go n
    assert_selector "#scheda-#{n}", wait: 10
    figures = page.evaluate_script("document.querySelectorAll('#scheda-#{n} .dg').length")
    assert_selector "#scheda-#{n} .dg-stage svg", minimum: figures, wait: 20 if figures.positive?
    assert_no_selector "#scheda-#{n} .dg-failed"
    sleep 0.4
    page.evaluate_async_script("import('lesson/speech').then((m) => arguments[0](m.speechOf(document.querySelector('#scheda-#{n}')).map(({ lang, text }) => ({ lang, text }))))")
  end

  SOURCES.each_key do |name|
    test "what the voice reads for #{name}" do
      @golden_body = body_of(name)
      build_student_world(approve: false, release: false)
      sign_in_as :student
      page.driver.headers = TRIAL_HEADERS
      page.driver.resize(1366, 900)
      visit "about:blank"
      visit "/topics/#{TOPIC}/lesson?n=#{SecureRandom.hex(3)}"
      assert_selector "#lesson-root[data-ready='1']", wait: 30
      read = @golden_body["cards"].to_h { |card| [ card["id"], read_card(card["n"]) ] }
      read.each { |id, segments| assert_not_empty segments, "#{name}/#{id} reads nothing" }
      path = GOLDEN.join("#{name}.json")
      if ENV["GOLDEN"] == "1"
        FileUtils.mkdir_p(GOLDEN)
        path.write("#{JSON.pretty_generate(read)}\n")
      else
        assert path.file?, "#{path} is missing: run with GOLDEN=1 and read it"
        assert_equal JSON.parse(path.read), JSON.parse(read.to_json), "what is read for #{name} changed (GOLDEN=1 writes it again; read the diff)"
      end
    end
  end
end
