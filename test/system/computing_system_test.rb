require "application_system_test_case"
require_relative "../support/lesson_events_world"
require_relative "../support/student_session"

# register and column_calc on the student's page in Chrome (T9): the bits are switches the student can tap or reach with the keyboard, the readout
# and the goals follow, the ring's pointer moves round the circle, the column work appears one column at a time, and the polite live line says
# what changed. The gallery of the family (test/fixtures/lesson2/gallery/computing.md) is the lesson. Screenshots in BANCO_SHOT_DIR.
class ComputingSystemTest < ApplicationSystemTestCase
  include LessonEventsWorld
  include StudentSession

  TRIAL_HEADERS = { "Remote-User" => "trial-x", "Remote-Groups" => "banco-student" }.freeze
  SHOT_DIR = ENV.fetch("BANCO_SHOT_DIR", File.join(Dir.tmpdir, "banco-shots"))

  # The gallery is the lesson of the topic.
  def lesson_body
    @gallery_body ||= Lessons::Parser2.call(Rails.root.join("test/fixtures/lesson2/gallery/computing.md").read, Validation::Findings.new, allow_reserved: true).body.merge("key" => TOPIC)
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

  def shot(name) = page.driver.save_screenshot(File.join(SHOT_DIR, "computing-#{name}.png"), full: true)

  def open_card(n, size: [ 1280, 900 ])
    page.driver.resize(*size)
    visit "about:blank"
    visit "/topics/#{TOPIC}/lesson?n=#{SecureRandom.hex(3)}#scheda-#{n}"
    wait_for_lesson_ready(wait: 20)
    assert_selector ".l2-card .dg-register, .l2-card .dg-column_calc", wait: 10
  end

  test "the bits of a register are switches: a tap flips one, the readout and the goal follow, the live line says it" do
    open_card(2)
    assert_selector ".l2-card button.dg-switch[role=switch]", count: 8
    assert_text "Il registro vale 45"
    assert_selector ".dg-goaltext.dg-reachedtext", text: "45 Sì"
    last = all(".l2-card button.dg-switch").last
    assert_equal "true", last["aria-checked"]
    last.click
    assert_text "Il registro vale 44"
    assert_equal "false", all(".l2-card button.dg-switch").last["aria-checked"]
    assert_no_selector ".dg-reachedtext"
    assert_selector ".l2-card [role=status][aria-live=polite]", text: /Il registro è 0010.1100/, visible: :all
    # the keyboard does the same: focus a bit and press Space; the bits are one group, so the focus stays on the switch that was pressed, there is
    # one tab stop, and the arrows move inside
    focus = ->(i) { page.execute_script("document.querySelector(\".l2-card .dg-switch[data-control='bit-#{i}']\").focus()") }
    key = ->(name) { page.driver.browser.keyboard.type(name) }
    active = -> { page.evaluate_script("document.activeElement.dataset.control") }
    focus.call(0)
    key.call(:space)
    assert_text "Il registro vale 172"
    assert_equal "bit-0", active.call
    assert_selector ".l2-card .dg-switch[tabindex='0']", count: 1
    key.call(:Right)
    assert_equal "bit-1", active.call
    key.call(:space)
    assert_text "Il registro vale 236"
    assert_equal "bit-1", active.call
    key.call(:End)
    assert_equal "bit-7", active.call
    shot "register-toggle"
    # the description follows what is on show
    find(".l2-card .dg-desc summary").click
    assert_text "vale 236"
  end

  test "the two's complement lab says Sì when a goal is reached" do
    open_card(3)
    assert_selector ".l2-card button.dg-switch", count: 8
    bit = ->(i) { find(".l2-card .dg-switch[data-control='bit-#{i}']") }
    bit.call(0).click
    assert_selector ".dg-reachedtext", text: "−128 Sì"
    bit.call(0).click
    (1..7).each { |i| bit.call(i).click }
    assert_text "Il registro con segno vale 127"
    assert_selector ".dg-reachedtext", text: "127 Sì"
  end

  test "a state change puts the toggles back and Avanti steps the weights through the states" do
    open_card(1)
    assert_no_selector "button.dg-switch"
    assert_text "Passo 1 di 3"
    assert_text "Il registro con segno vale 5"
    click_button "Passo avanti"
    assert_text "Il registro con segno vale −6"
    assert_selector ".l2-card .dg-op", text: "Inverti ogni bit"
  end

  test "the ring's pointer moves round the circle with -1 and +1, at 390 px too" do
    open_card(5, size: [ 390, 844 ])
    assert_text "Puntatore 0010: senza segno 2, con segno 2"
    first(".l2-card .dg-stepper button", text: "+1").click
    assert_text "Puntatore 0011: senza segno 3, con segno 3"
    2.times { first(".l2-card .dg-stepper button", text: "−1").click }
    assert_text "Puntatore 0001: senza segno 1, con segno 1"
    3.times { first(".l2-card .dg-stepper button", text: "−1").click }
    assert_text "Puntatore 1110: senza segno 14, con segno −2"
    shot "ring-390"
  end

  test "a column calculation appears one column at a time and the last one drops the carry out of the register" do
    open_card(6)
    assert_text "Tocca Avanti: appare una colonna."
    assert_no_selector ".dg-outside .dg-digit"
    within(".l2-card .dg-stepper") { click_button "Avanti" }
    assert_text "Colonna 1: 1 più 1 fa 2, cioè 10 in base 2"
    7.times { within(".l2-card .dg-stepper") { click_button "Avanti" } }
    assert_text "Colonna 8"
    assert_selector ".l2-card .dg-outside", minimum: 1
    assert_text "Secondo numero vale −5"
    assert_text "Risultato vale 0"
    shot "column-add"
    within(".l2-card .dg-stepper") { click_button "Indietro" }
    assert_text "Colonna 7"
    assert_no_text "Colonna 8"
  end

  test "a multiplication shows its partial products one by one" do
    open_card(8)
    assert_text "Tocca Avanti: appare un prodotto."
    within(".l2-card .dg-stepper") { click_button "Avanti" }
    assert_text "Cifra 1 di b, che è 1: 00000101 per 1"
    within(".l2-card .dg-stepper") { click_button "Avanti" }
    assert_text "Cifra 2 di b, che è 0"
  end

  test "input: bits is eight switches in two groups: tapping builds the answer, the server grades the string" do
    open_check = -> {
      page.driver.resize(390, 844)
      visit "about:blank"
      visit "/topics/#{TOPIC}/lesson?n=#{SecureRandom.hex(3)}#scheda-9"
      wait_for_lesson_ready(wait: 20)
      assert_selector ".l2-card .bits-input", wait: 10
    }
    open_check.call
    assert_selector ".l2-card button.bit-switch[role=switch]", count: 8
    assert_selector ".l2-card .bit-group", count: 2
    assert_selector ".l2-card .bits-hint", text: "Tocca un bit per cambiarlo"
    # nothing is sent before a bit is touched
    click_button "Controlla"
    assert_selector ".verdict-invalid"
    switches = all(".l2-card button.bit-switch")
    # 11111101: every bit but the sixth from the right
    [ 0, 1, 2, 3, 4, 5, 7 ].each { |i| switches[i].click }
    assert_equal "true", switches[0]["aria-checked"]
    assert_equal "false", switches[6]["aria-checked"]
    assert_text(/1111.1101/)
    shot "input-bits-390"
    click_button "Controlla"
    assert_selector ".verdict-right", text: "Sì.", wait: 10
    assert_selector ".bit-switch[disabled]", count: 8
  end

  test "input: bits: a typical error is named and the string is the whole width" do
    page.driver.resize(1280, 900)
    visit "about:blank"
    visit "/topics/#{TOPIC}/lesson?n=#{SecureRandom.hex(3)}#scheda-9"
    assert_selector ".l2-card .bits-input", wait: 20
    switches = all(".l2-card button.bit-switch")
    [ 0, 1, 2, 3, 4, 5 ].each { |i| switches[i].click } # 11111100
    click_button "Controlla"
    assert_selector ".verdict-wrong", text: "Non ancora."
    assert_text "Manca il più 1."
  end
end
