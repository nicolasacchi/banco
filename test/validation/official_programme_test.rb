require "test_helper"
require_relative "../support/validation_fixtures"
require_relative "../support/lesson_md"

# D-344: the seconda programme has no section for scienze motorie, so for the subjects of course.official_programme_subjects the official
# programme (course.extra_source) is the current year's programme: its skills, lessons and graph cite it where the others cite the seconda one.
class OfficialProgrammeTest < ActiveSupport::TestCase
  OFFICIAL = "ufficiale-2026-27".freeze
  PE = "physical_education".freeze
  SKILL = "physical_education.bones-and-joints".freeze
  ERRORS = [ { "code" => "subst", "description_it" => "Sostituisce male.", "implicates" => [] } ].freeze

  def official_ref(role = "taught_in") = { "source" => OFFICIAL, "line" => 1, "fragment" => "disequazioni di primo grado", "role" => role }

  def course_skill(subject, slug, refs)
    { "key" => "#{subject}.#{slug}", "label_it" => "Sistemi lineari", "layer" => "core", "prerequisites" => [], "refs" => refs, "errors" => ERRORS }
  end

  def course_doc(subject, skill, topic_kind)
    topic = { "key" => "#{topic_kind}.#{subject}.#{skill['key'].split('.').last}", "kind" => topic_kind, "title_it" => "Equazioni", "term" => (topic_kind == "extra" ? nil : 1), "minutes" => 30,
              "skills" => [ skill["key"] ], "after" => [] }
    { "schema" => "banco.course/1", "schema_version" => 1, "subject" => subject, "skills" => [ skill ], "topics" => [ topic ] }
  end

  def graph(subject, skills = [])
    { "schema" => "banco.skill_graph/1", "schema_version" => 1, "subject" => subject, "skills" => skills, "excluded" => [] }
  end

  def course_findings(subject, doc)
    context = LessonMd.context(subject: subject, skills: [])
    Validation::CourseChecks.call(doc, subject: subject, graph: graph(subject), context: context)
  end

  def errors(findings) = findings.map(&:code).uniq.select { |c| c.start_with?("E-") }

  test "the rules name the subject, and the programme source is the official one for it only" do
    assert_equal [ PE ], Validation::Rules.list(:course, :official_programme_subjects)
    assert Validation::Rules.official_programme_subject?(PE)
    assert_not Validation::Rules.official_programme_subject?("math")
    assert_equal OFFICIAL, Validation::Rules.programme_source(PE)
    assert_equal "seconda-2025-26", Validation::Rules.programme_source("math")
  end

  test "a course skill of physical_education that cites only the official programme is held by a lezione topic with no finding" do
    skill = course_skill(PE, "bones-and-joints", [ official_ref ])
    %w[lezione ripasso ponte].each do |kind|
      found = course_findings(PE, course_doc(PE, skill, kind))
      assert_empty errors(found), "#{kind}: #{found.map { |f| [ f.code, f.message ] }}"
    end
  end

  test "the same map for another subject is still E-COURSE-EXTRA-SKILL in a lezione, and fine in an extra topic" do
    skill = course_skill("math", "demo-inequalities", [ official_ref ])
    assert_includes errors(course_findings("math", course_doc("math", skill, "lezione"))), "E-COURSE-EXTRA-SKILL"
    assert_empty errors(course_findings("math", course_doc("math", skill, "extra")))
  end

  test "a skill of physical_education still needs a taught_in ref on a programme" do
    skill = course_skill(PE, "bones-and-joints", [ official_ref("needed_by") ]) # a ref, but no taught_in on any programme
    assert_includes errors(course_findings(PE, course_doc(PE, skill, "lezione"))), "E-SOURCE"
  end

  def lesson_findings(subject, kind, refs, scope)
    key = "#{kind}.#{subject}.demo"
    md = LessonMd.build(front: { "key" => key, "kind" => kind, "subject" => subject, "skills" => [ "#{subject}.demo-skill" ], "uses" => [], "refs" => refs, "scope" => scope })
    Validation::LessonChecks.call(md, subject: subject, context: LessonMd.context(subject: subject, skills: [ "#{subject}.demo-skill" ])).findings
  end

  def refs_findings(findings) = findings.select { |f| f.code == "E-LESSON-REFS" }.map(&:message)

  test "a lezione, a ponte and a ripasso of physical_education take the official programme as their programme ref" do
    assert_empty refs_findings(lesson_findings(PE, "lezione", [ official_ref ], "seconda"))
    assert_empty refs_findings(lesson_findings(PE, "ponte", [ official_ref("needed_by") ], "not_in_prima"))
    assert_empty refs_findings(lesson_findings(PE, "ripasso", [ official_ref("needed_by") ], "studied")),
                "a ripasso needs no ref on the previous year's programme for it"
  end

  test "for another subject the programme ref is still the seconda one, and a ripasso still needs the previous year's" do
    assert_not_empty refs_findings(lesson_findings("math", "lezione", [ official_ref ], "seconda"))
    seconda = { "source" => "seconda-2025-26", "line" => 2, "fragment" => "equazioni di primo grado numeriche", "role" => "needed_by" }
    assert_not_empty refs_findings(lesson_findings("math", "ripasso", [ seconda ], "studied"))
  end

  test "a skill graph of physical_education is needed by a line of the official programme, the others by a seconda line" do
    skills = [ { "key" => SKILL, "prerequisites" => [], "composite_of" => [], "refs" => [ official_ref("needed_by") ] } ]
    index = skills.to_h { |s| [ s["key"], s ] }
    pe = Validation::Findings.new
    Validation::GraphChecks.needed_by(skills, index, PE, pe)
    assert_empty pe.map(&:code)
    math = Validation::Findings.new
    Validation::GraphChecks.needed_by(skills, index, "math", math)
    assert_equal [ "E-NEEDED-BY" ], math.map(&:code)
  end
end
