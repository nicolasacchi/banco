require_relative "decision_world"
require_relative "topic_world"
require_relative "practice_rows"
require_relative "arbiter_rows"

# A small invented course for the teacher's course path and guided review: four topics of one subject in a fixed
# order, in four situations (ready for the teacher, being worked on by the agents, not written, approved), with
# lessons, practice items of three levels, reviews, findings with opinions and trial practice. Nothing of a real
# programme and no real person.
module CoursePathWorld
  include TopicWorld
  include PracticeRows
  include ArbiterRows

  READY = "ripasso.math.number-basics".freeze
  WORKING = "ponte.math.fraction-bridge".freeze
  MISSING = "lezione.math.choice-new".freeze
  DONE = "ripasso.math.ordering-basics".freeze

  PATH_TOPICS = [
    { key: READY, kind: "ripasso", title_it: "Operazioni con i numeri", skills: [ "math.number" ], minutes: 25, term: 1, after: [] },
    { key: WORKING, kind: "ponte", title_it: "Frazioni: la base che serve", skills: [ "math.fraction" ], minutes: 30, term: 1, after: [ READY ] },
    { key: MISSING, kind: "lezione", title_it: "Ragionare con le scelte", skills: [ "math.choice" ], minutes: 35, term: 2, after: [ WORKING ] },
    { key: DONE, kind: "ripasso", title_it: "Mettere in ordine", skills: [ "math.ordering" ], minutes: 20, term: 1, after: [] }
  ].freeze

  # Builds the subject (not approved), the course map and the four situations. Sets @subject, @graph, @course, @official, @trial,
  # @ready (topic revision), @ready_items, @ready_lesson, @working, @done.
  def build_course_path_world
    @world = build_ui_subject(approve: false)
    @subject = @world[:subject]
    @graph = SkillGraphRevision.where(subject: @subject).order(:seq).last
    @reviewer = AgentSession.find_or_create_by!(label: "topic-reviewer", role: "reviewer") { |s| s.agent = "omp"; s.model = "gpt-5.2" }
    @course = build_course_map(subject: @subject, topics: PATH_TOPICS)
    @official = Student.official
    @trial = Student.create!(key: "prova-1", kind: "student")

    @ready_lesson = path_lesson!(READY, "math.number", reviewed: true, lesson_findings: [ { severity: "minor", section: "idea", quote: "bilancia", problem_it: "Frase lunga.", fix_it: "Spezzala." } ])
    @ready_items = [ 1, 2, 3 ].map { |level| path_item!("number-basics-#{level}", "math.number", level) }
    @ready = make_topic(@ready_lesson, { "math.number" => @ready_items }, course: @course)

    working_lesson = path_lesson!(WORKING, "math.fraction", reviewed: false)
    @working_items = [ 1, 2 ].map { |level| path_item!("fraction-bridge-#{level}", "math.fraction", level, component: "fraction", worked: false) }
    @working = make_topic(working_lesson, { "math.fraction" => @working_items }, course: @course)

    done_lesson = path_lesson!(DONE, "math.ordering", reviewed: true)
    @done_items = [ 1, 2 ].map { |level| path_item!("ordering-basics-#{level}", "math.ordering", level, component: "ordering") }
    @done = make_topic(done_lesson, { "math.ordering" => @done_items }, course: @course)
    approve_path_topic!(@done, DONE)
  end

  def path_lesson!(key, skill, reviewed:, lesson_findings: [])
    revision = lesson_revision_with_body!(key, skill)
    review_lesson!(revision, findings: lesson_findings) if reviewed
    revision
  end

  def path_item!(key, skill, level, component: "number", worked: true)
    revision = make_practice_item(key, skill, subject: @subject, instances: 6, level: level, component: component)
    work_item!(revision) if worked
    revision
  end

  def approve_path_topic!(topic, key)
    Decision.create!(kind: "approve_topic", subject: @subject, request_id: SecureRandom.uuid, teacher_login: "nik", remote_addr: DecisionWorld::EDGE,
                     payload_json: { topic_revision_id: topic.id, topic: key, seq: topic.seq }.to_json)
  end

  # A finding on a ready item, with the third reviewer's opinions. Returns the finding.
  def path_finding!(revision, severity: "major", opinions: [ "finding_right", "finding_right" ])
    review = revision.reviews.max_by(&:id) || ItemReview.create!(item_revision: revision, agent_session: @reviewer, checklist_json: "[]")
    finding = ReviewFinding.create!(item_revision: revision, source: "review", item_review: review, severity: severity, field: "stem", quote: "x",
                                    problem_it: "L'enunciato si presta a due letture.", fix_it: "Riscrivi l'enunciato.")
    opinions.each_with_index do |verdict, i|
      assess!(finding, verdict, session: arbiter_session(i.zero? ? ArbiterRows::FIRST_MODEL : ArbiterRows::SECOND_MODEL))
    end
    finding
  end

  def dispose_finding!(finding, disposition = "dismissed")
    Decision.create!(kind: "dispose_finding", subject: @subject, request_id: SecureRandom.uuid, teacher_login: "nik", remote_addr: DecisionWorld::EDGE,
                     payload_json: { finding_id: finding.id, disposition: disposition, reason_it: "Va bene così." }.to_json)
  end

  def open_course!
    approve_graph_row!(@subject, @graph)
    Decision.create!(kind: "release_course", subject: @subject, request_id: SecureRandom.uuid, teacher_login: "nik", remote_addr: DecisionWorld::EDGE,
                     payload_json: { open: true, course_revision_id: @course.id }.to_json)
  end

  # Some tries of the official student and the trial student on the ready topic's first item.
  def practice_on_ready!
    [ [ @official, "1", "correct", 0 ], [ @official, "9", "wrong", 1 ], [ @trial, "1", "correct", 2 ] ].each do |student, raw, verdict, index|
      instance = @ready_items.first.instances.order(:id)[index]
      serve = make_serve(student, @ready, instance, skill_key: "math.number", at: Time.utc(2026, 11, 2, 8, index))
      make_try(serve, raw: raw, verdict: verdict, error_codes: verdict == "wrong" ? [ "slip" ] : [], at: Time.utc(2026, 11, 2, 8, index, 30))
    end
  end
end
