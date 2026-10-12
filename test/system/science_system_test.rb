require "application_system_test_case"
require_relative "../support/lesson_events_world"
require_relative "../support/student_session"

# formula, molecule, periodic_table and strand on the student's page in Chrome (T7): Avanti steps a formula through its states and the live line says what
# changed, a select check over a formula's pieces is answered by touch, the table's elements open their card, a base lights its partner. The gallery of the
# family (test/fixtures/lesson2/gallery/science.md) is the lesson. Screenshots in BANCO_SHOT_DIR (the look gate).
class ScienceSystemTest < ApplicationSystemTestCase
  include LessonEventsWorld
  include StudentSession

  TRIAL_HEADERS = { "Remote-User" => "trial-x", "Remote-Groups" => "banco-student" }.freeze
  SHOT_DIR = ENV.fetch("BANCO_SHOT_DIR", File.join(Dir.tmpdir, "banco-shots"))

  # The gallery is the lesson of the topic.
  def lesson_body
    @gallery_body ||= Lessons::Parser2.call(Rails.root.join("test/fixtures/lesson2/gallery/science.md").read, Validation::Findings.new, allow_reserved: true).body.merge("key" => TOPIC)
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

  def shot(name) = page.driver.save_screenshot(File.join(SHOT_DIR, "science-#{name}.png"), full: true)

  def open_card(n, size: [ 1280, 900 ])
    page.driver.resize(*size)
    visit "about:blank"
    visit "/topics/#{TOPIC}/lesson?n=#{SecureRandom.hex(3)}#scheda-#{n}"
    assert_selector "#lesson-root[data-ready='1']", wait: 20
    assert_selector "#scheda-#{n} .dg", wait: 10
  end

  test "a formula steps through its states: Avanti shows the count, the molecules and the highlighted element, the live line says it" do
    open_card(1)
    assert_text "Passo 1 di 3"
    assert_no_text "Atomi in tutto"
    assert_selector "#scheda-1 .dg-arrow", count: 1
    click_button "Passo avanti"
    assert_text "Atomi in tutto"
    assert_selector "#scheda-1 .dg-rowfocus", text: "H"
    assert_selector "#scheda-1 .dg-op", text: "Il pedice 2 è dell'H"
    assert_no_selector "#scheda-1 .dg-atom"
    click_button "Passo avanti"
    assert_selector "#scheda-1 .dg-atom", count: 9
    assert_selector "#scheda-1 .dg-molname", text: "acqua"
    find("#scheda-1 .dg-desc summary").click
    assert_text "tre molecole d'acqua"
    shot "formula-states"
  end

  test "the brackets of a group: a frame, two arrows and a count that multiplies through, at 390 px too" do
    open_card(2, size: [ 390, 844 ])
    assert_selector "#scheda-2 .dg-gframe"
    assert_selector "#scheda-2 .dg-arrow", count: 2
    assert_selector "#scheda-2 .dg-rowchain", text: "= 12"
    shot "formula-brackets-390"
  end

  test "a salt is a patch of ions with one unit framed, never molecules; a metal is a patch of atoms" do
    open_card(4)
    assert_selector "#scheda-4 .dg-unitframe", count: 1
    assert_selector "#scheda-4 .dg-ion", count: 8
    assert_selector "#scheda-4 .dg-unitword", text: "unità"
    within("#scheda-4 .dg") { assert_no_text "molecola" }
    open_card(3)
    assert_selector "#scheda-3 .dg-atom-Co", count: 7
    assert_selector "#scheda-3 .dg-atom-C, #scheda-3 .dg-atom-O", minimum: 2
    shot "formula-compare"
  end

  test "select over the pieces of a formula: every piece is a neutral target, touching the subscript and checking answers right" do
    open_card(5)
    assert_selector "#scheda-5 .dg-target", count: 4
    labels = all("#scheda-5 .dg-target").map { |b| b["aria-label"] }
    assert_equal "zona 1 di 4, Pezzo 1 di 4", labels.first
    assert(labels.none? { |l| l.match?(/pedice|simbolo|coefficiente/) }, "no piece is named: #{labels.inspect}")
    find("#scheda-5 .dg-target[data-target='t1']").click
    click_button "Controlla"
    assert_selector "#scheda-5 .verdict-wrong", wait: 5
    assert_text "Quello è il coefficiente"
    find("#scheda-5 .dg-target[data-target='t1']").click
    find("#scheda-5 .dg-target[data-target='t3']").click
    click_button "Controlla"
    assert_selector "#scheda-5 .verdict-right", wait: 5
    shot "formula-select"
  end

  test "molecule: every atom has its symbol inside, hydrogens are smaller, the angle and the signs of the charges are drawn from the library" do
    open_card(6)
    assert_selector "#scheda-6 .dg-atom", count: 2 + 3 + 3 + 4
    radii = ->(sym) { all("#scheda-6 .dg-atom-#{sym}").map { |c| c["r"].to_f }.max }
    assert_operator radii.call("H"), :<, radii.call("O"), "the hydrogens are the smallest"
    assert_equal %w[C C H H H H O O O O O O], all("#scheda-6 .dg-atomtext").map(&:text).sort
    assert_selector "#scheda-6 .dg-molname", text: "acqua ossigenata"
    open_card(7)
    assert_selector "#scheda-7 .dg-angletext", text: "104,5°"
    assert_selector "#scheda-7 .dg-angletext", text: "180°"
    assert_selector "#scheda-7 .dg-partial", count: 6
    assert_selector "#scheda-7 .dg-anglearc", count: 2
    find("#scheda-7 .dg-desc summary").click
    assert_text "L'angolo tra i due legami è di 104,5 gradi"
    assert_text "Carica parziale negativa: ossigeno. Positiva: idrogeno."
    shot "molecule-angle-partial"
    open_card(9, size: [ 390, 844 ])
    assert_selector "#scheda-9 .dg-unitframe", count: 3
    assert_selector "#scheda-9 .dg-unitword", count: 3
    shot "molecule-patches-390"
  end

  test "molecule: select over the groups, every group is a neutral dashed box named only by its place, the answer is graded" do
    open_card(10, size: [ 390, 844 ])
    assert_selector "#scheda-10 .dg-target", count: 4
    assert_equal "zona 1 di 4, Gruppo 1 di 4", find("#scheda-10 .dg-target[data-target='t1']")["aria-label"]
    assert_no_selector "#scheda-10 .dg-atomtext"
    find("#scheda-10 .dg-target[data-target='t2']").click
    click_button "Controlla"
    assert_selector "#scheda-10 .verdict-wrong", wait: 5
    assert_text "Quella ha tre atomi"
    find("#scheda-10 .dg-target[data-target='t2']").click
    find("#scheda-10 .dg-target[data-target='t4']").click
    click_button "Controlla"
    assert_selector "#scheda-10 .verdict-right", wait: 5
    shot "molecule-select-390"
  end
end
