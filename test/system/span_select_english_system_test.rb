require "application_system_test_case"
require_relative "../support/lesson_events_world"
require_relative "../support/student_session"

# A span_select written in English (text_en and spans[].text_en, D-292): the sentence is drawn word for word with its lang, each span is a button that toggles. Screenshots for the look gate go to BANCO_SHOT_DIR (span-select-en-*.png).
class SpanSelectEnglishSystemTest < ApplicationSystemTestCase
  include LessonEventsWorld
  include StudentSession

  TRIAL_HEADERS = { "Remote-User" => "trial-x", "Remote-Groups" => "banco-student" }.freeze
  SHOT_DIR = ENV.fetch("BANCO_SHOT_DIR", File.join(Dir.tmpdir, "banco-shots"))

  # The first card of the science gallery with an English span_select added after its figure.
  def lesson_body
    @span_body ||= begin
      body = Lessons::Parser2.call(Rails.root.join("test/fixtures/lesson2/gallery/science.md").read, Validation::Findings.new, allow_reserved: true).body.merge("key" => TOPIC)
      body["cards"][0]["blocks"] << { "type" => "check", "component" => "span_select", "prompt_it" => "Tocca la frase temporale.", "text_en" => "I will text you as soon as the film ends.",
                                      "spans" => [ { "id" => "s1", "text_en" => "I will text you" }, { "id" => "s2", "text_en" => "as soon as" }, { "id" => "s3", "text_en" => "the film ends." } ],
                                      "answer" => %w[s2 s3] }
      body
    end
  end

  setup do
    @saved_users = ENV["BANCO_STUDENT_USERS"]
    ENV["BANCO_STUDENT_USERS"] = "trial-x=prova-1"
    FileUtils.mkdir_p(SHOT_DIR)
    build_student_world(approve: false, release: false)
    sign_in_as :student
    page.driver.headers = TRIAL_HEADERS
    page.driver.resize(1280, 900)
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

  [ [ 390, 844 ], [ 1366, 900 ] ].each do |width, height|
    test "an English span_select at #{width}: the words in the sentence's lang and spans that toggle" do
      lesson_body
      page.driver.resize(width, height)
      visit "about:blank"
      visit "/topics/#{TOPIC}/lesson?n=#{SecureRandom.hex(3)}#scheda-1"
      assert_selector "#lesson-root[data-ready='1']", wait: 20
      assert_selector "#scheda-1 .spans[lang='en']", wait: 10
      assert_equal "I will text you as soon as the film ends.", page.evaluate_script("document.querySelector('#scheda-1 .spans').textContent.replace(/\\s+/g, ' ').trim()")
      chips = page.evaluate_script("[...document.querySelectorAll('#scheda-1 .span-chip')].map((b) => b.textContent)")
      assert_equal [ "I will text you", "as soon as", "the film ends." ], chips
      find("#scheda-1 .span-chip[data-span='s3']").click
      find("#scheda-1 .span-chip[data-span='s2']").click
      assert_equal [ "false", "true", "true" ], page.evaluate_script("[...document.querySelectorAll('#scheda-1 .span-chip')].map((b) => b.getAttribute('aria-pressed'))")
      sleep 0.5
      page.driver.save_screenshot(File.join(SHOT_DIR, "span-select-en-#{width}.png"), full: true)
    end
  end
end
