require "application_system_test_case"
require_relative "../support/lesson_events_world"
require_relative "../support/student_session"

# A figure that cannot be drawn shows its alt text and its description, and nothing else: no empty <details>, which Chrome would label with its own
# English "Details" (found by the wave 2 final review on the strand and map cards). The data below is wrong on purpose (a base that is not A, C, G or T).
class FigureErrorSystemTest < ApplicationSystemTestCase
  include LessonEventsWorld
  include StudentSession

  TRIAL_HEADERS = { "Remote-User" => "trial-x", "Remote-Groups" => "banco-student" }.freeze
  SHOT_DIR = ENV.fetch("BANCO_SHOT_DIR", File.join(Dir.tmpdir, "banco-shots"))

  # The gallery's strand card with a letter that is not a base: the browser's check refuses it and the figure shows its fallback.
  def lesson_body
    @broken_body ||= begin
      body = Lessons::Parser2.call(Rails.root.join("test/fixtures/lesson2/gallery/science.md").read, Validation::Findings.new, allow_reserved: true).body.merge("key" => TOPIC)
      card = body["cards"].find { |c| c["blocks"].any? { |b| b["type"] == "diagram" && b.dig("diagram", "type") == "strand" } }
      figure = card["blocks"].find { |b| b["type"] == "diagram" && b.dig("diagram", "type") == "strand" }["diagram"]
      figure["top"] = "QQQ"
      @card_n = body["cards"].index(card) + 1
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

  test "a figure that fails shows no details without a summary" do
    lesson_body
    visit "about:blank"
    visit "/topics/#{TOPIC}/lesson?n=#{SecureRandom.hex(3)}#scheda-#{@card_n}"
    assert_selector "#lesson-root[data-ready='1']", wait: 20
    assert_selector "#scheda-#{@card_n} .dg-failed", wait: 10
    assert_equal [], page.evaluate_script("[...document.querySelectorAll('#scheda-#{@card_n} details')].filter((d) => getComputedStyle(d).display !== 'none' && !d.querySelector(':scope > summary')).map((d) => d.className)")
    assert_selector "#scheda-#{@card_n} .dg-desc summary", text: "Descrizione"
  end
end
