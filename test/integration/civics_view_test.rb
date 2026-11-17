require "test_helper"
require_relative "../support/multi_user"
require_relative "../support/student_course_world"

# Educazione civica (D-345): a view in Materie over topics of other subjects, by the three nuclei of config/banco/civics.yml.
# Optional but visible: built only from what the student's course view shows, no progress of its own, never in Oggi.
class CivicsViewTest < ActionDispatch::IntegrationTest
  include MultiUser
  include StudentCourseWorld

  ROOT = "/teacher/preview".freeze
  DONE_TOPIC = "ripasso.law_economics.constitution-origins-structure".freeze   # constitution, programme, done
  TODO_TOPIC = "lezione.law_economics.rights-duties".freeze                    # constitution, programme, to do
  EXTRA_TOPIC = "extra.geography.europe".freeze                                # constitution, extra
  DIGITAL_TOPIC = "extra.computer_science.online-safety".freeze                # digital, extra
  DRAFT_TOPIC = "extra.computer_science.cyberbullying".freeze                  # digital, written but not approved
  HIDDEN_TOPIC = "lezione.law_economics.parliament-lawmaking".freeze           # in civics.yml, no lesson at all
  TITLES = { DONE_TOPIC => "Origini e struttura della Costituzione", TODO_TOPIC => "Diritti e doveri", EXTRA_TOPIC => "L'Europa",
             DIGITAL_TOPIC => "Sicurezza online", DRAFT_TOPIC => "Cyberbullismo", HIDDEN_TOPIC => "Parlamento" }.freeze
  SUBJECT_NAMES = { "law_economics" => "Diritto ed economia", "geography" => "Geografia economica", "computer_science" => "Informatica" }.freeze

  def page(headers, path) = on(:web, path, headers: headers, remote_addr: EDGE)

  def post_form(headers, path, params = {})
    page(headers, "#{ROOT}/today")
    token = css_select("meta[name=csrf-token]").first&.[]("content").to_s
    on(:web, path, method: :post, headers: headers.merge("X-CSRF-Token" => token), params: params, remote_addr: EDGE)
  end

  # The maths world of the course pages plus three subjects holding civics topics. Topics of the same subject share one course map.
  def build_civics_world(release: true)
    build_student_world(release: release)
    @clock = Diagnosis::FakeClock.new(Time.current - 20.days)
    math = @subject
    @civics_topics = {}
    { "law_economics" => [ DONE_TOPIC, TODO_TOPIC ], "geography" => [ EXTRA_TOPIC ], "computer_science" => [ DIGITAL_TOPIC, DRAFT_TOPIC ] }.each do |key, topics|
      @subject = Subject.find_by(key: key) || Subject.create!(key: key, name_it: SUBJECT_NAMES.fetch(key), position: Subject.count + 1)
      SkillGraphRevision.create!(subject: @subject, seq: 1, body_json: JSON.generate(ValidationFixtures::GRAPH))
      course = build_course_map(skills: [], topics: topics.map { |t| civics_map_entry(t) })
      topics.each do |topic|
        slug = topic.split(".").last
        lesson = Lesson.create!(subject: @subject, key: topic, kind: topic.split(".").first)
        body = lesson_body.merge(key: topic, kind: lesson.kind, subject: key, title_it: TITLES.fetch(topic), skills: [ civics_skill(topic) ], scope: "studied")
        revision = LessonRevision.create!(lesson: lesson, seq: 1, source_md: "---\n", source_sha256: Digest::SHA256.hexdigest(topic), rules_version: Validation::Rules.version.to_s,
                                          warnings_json: "[]", body_json: JSON.generate(body))
        items = Array.new(2) { |i| make_practice_item("#{slug}-#{i + 1}", civics_skill(topic), instances: 12, level: i + 1, subject: @subject) }
        @civics_topics[topic] = TopicRevision.create!(lesson: lesson, seq: 1, course_revision: course, lesson_revision: revision,
                                                      body_json: JSON.generate(schema: "banco.topic/1", key: topic,
                                                                               practice: [ { skill: civics_skill(topic), items: items.map { |r| { item: r.item.key, revision: r.id } } } ]))
        approve_topic!(@civics_topics[topic]) unless topic == DRAFT_TOPIC
      end
      release_course!(course) if release
    end
    @subject = math
    play_topic!(@civics_topics.fetch(DONE_TOPIC), civics_skill(DONE_TOPIC), 3)
  end

  def civics_skill(topic) = topic.split(".").drop(1).join(".")

  def civics_map_entry(topic)
    kind = topic.split(".").first
    { key: topic, kind: kind, title_it: TITLES.fetch(topic), skills: [ civics_skill(topic) ], minutes: 20, term: kind == "extra" ? nil : 1, after: [] }
  end

  def nucleus_keys = css_select("section.civics-nucleus").map { |s| s["data-nucleus"] }

  def keys_in(nucleus) = css_select("section[data-nucleus=#{nucleus}] li.topic").map { |li| li["data-topic"] }

  # ---- the card ---------------------------------------------------------------------------------------

  test "Materie shows the Educazione civica card after the subjects, optional, with the number of visible topics" do
    build_civics_world
    page(OFFICIAL, "/subjects")
    assert_response :success
    assert_select "#civics-card a.subject-name[href='/civics']", "Educazione civica"
    assert_select "#civics-card .pill", "Facoltativo · in più materie"
    assert_select "#civics-card [data-civics-count]", "4 argomenti", "two of law, one of geography, one of computer science; the draft and the missing lesson are not visible"
    assert_equal "civics-card", css_select("ul#subjects > li").last["id"], "after the subjects"
    assert_select "#civics-card .progress-line[data-line=required]", 0
    assert_select "#civics-card .progress-line[data-line=optional]", 0
    assert_select "#civics-card [role=progressbar]", 0
    assert_select "nav.student-menu a[href*='civics']", 0, "it lives in Materie, not in the menu"
    page(OFFICIAL, "/civics")
    assert_select "nav.student-menu a[aria-current=page]", "Materie"
  end

  test "the card and the page are not there for a student who sees none of the topics" do
    build_student_world
    page(OFFICIAL, "/subjects")
    assert_response :success
    assert_select "li.subject[data-subject=math]"
    assert_select "#civics-card", 0
    page(OFFICIAL, "/civics")
    assert_response :not_found
  end

  test "an official student whose courses are not released sees neither the card nor the page" do
    build_civics_world(release: false)
    page(OFFICIAL, "/subjects")
    assert_select "#civics-card", 0
    page(OFFICIAL, "/civics")
    assert_response :not_found
  end

  # ---- the page ---------------------------------------------------------------------------------------

  test "the page lists the visible topics under their nucleus, with subject, kind and status, and skips the invisible ones" do
    build_civics_world
    page(OFFICIAL, "/civics")
    assert_response :success
    assert_select "h1", "Educazione civica"
    assert_select "#civics-intro", /Non è una materia a sé: sono argomenti di altre materie/
    assert_select "a.back[href='/subjects']", /Materie/
    assert_equal %w[constitution digital], nucleus_keys, "the nucleus with no visible topic is not drawn"
    assert_equal [ DONE_TOPIC, TODO_TOPIC, EXTRA_TOPIC ], keys_in("constitution"), "in the order of civics.yml"
    assert_equal [ DIGITAL_TOPIC ], keys_in("digital")
    assert_select "section[data-nucleus=constitution] h2", "Costituzione"
    assert_select "section[data-nucleus=digital] h2", "Cittadinanza digitale"
    assert_select "li[data-topic=?]", HIDDEN_TOPIC, 0
    assert_select "li[data-topic=?]", DRAFT_TOPIC, 0
    assert_select "li[data-topic=?] a.topic-title[href=?]", DONE_TOPIC, "/topics/#{DONE_TOPIC}", text: TITLES.fetch(DONE_TOPIC)
    assert_select "li[data-topic=?] .topic-subject", DONE_TOPIC, text: Subject.find_by!(key: "law_economics").name_it
    assert_select "li[data-topic=?] .topic-subject", EXTRA_TOPIC, text: Subject.find_by!(key: "geography").name_it
    assert_select "li[data-topic=?] .topic-meta", DONE_TOPIC, text: /Ripasso di prima · 20 minuti/
    assert_select "li[data-topic=?] .topic-meta", TODO_TOPIC, text: /Programma di seconda/
    assert_select "li[data-topic=?][data-extra=true] .topic-meta", EXTRA_TOPIC, text: /Argomento facoltativo/
    assert_select "li[data-topic=?][data-extra=true] [data-extra-badge]", EXTRA_TOPIC, text: "Fuori programma"
    assert_select "li[data-topic=?][data-status=done] .pill.success", DONE_TOPIC, text: "Fatto"
    assert_select "li[data-topic=?][data-status=todo] .pill.muted", TODO_TOPIC, text: "Da fare"
    assert_select "li.topic .subject-chip", 4
    assert_select "section[data-nucleus=constitution] .section-count", "3 argomenti"
    assert_select "section[data-nucleus=digital] .section-count", "1 argomento"
  end

  test "the status is the one the subject page shows" do
    build_civics_world
    play_topic!(@civics_topics.fetch(TODO_TOPIC), civics_skill(TODO_TOPIC), 1)
    page(OFFICIAL, "/subjects/law_economics")
    subject_status = css_select("li.topic").to_h { |li| [ li["data-topic"], li["data-status"] ] }
    page(OFFICIAL, "/civics")
    civics_status = css_select("li.topic").to_h { |li| [ li["data-topic"], li["data-status"] ] }
    assert_equal "done", civics_status.fetch(DONE_TOPIC)
    assert_equal "in_progress", civics_status.fetch(TODO_TOPIC)
    assert_equal subject_status, civics_status.slice(*subject_status.keys)
  end

  test "a trial student also sees a draft topic, as in the subject" do
    build_civics_world
    page(TRIAL, "/civics")
    assert_response :success
    assert_equal [ DIGITAL_TOPIC, DRAFT_TOPIC ], keys_in("digital")
    assert_select "li[data-topic=?] .topic-why", DRAFT_TOPIC, text: /Bozza/
    page(TRIAL, "/subjects")
    assert_select "#civics-card [data-civics-count]", "5 argomenti"
  end

  test "the page has no progress of its own" do
    build_civics_world
    page(OFFICIAL, "/civics")
    assert_select ".progress-lines", 0
    assert_select "[role=progressbar]", 0
    assert_select "[data-section-count]", 0
  end

  # ---- what it does not touch -------------------------------------------------------------------------

  test "the progress of the subjects and Oggi do not change because of it" do
    build_civics_world
    page(OFFICIAL, "/subjects")
    assert_select "li.subject[data-subject=law_economics] .progress-line[data-line=required] .progress-text", "Obbligatori: 1 fatto su 2"
    assert_select "li.subject[data-subject=geography] .progress-line[data-line=required] .progress-text", "Obbligatori: nessuno"
    assert_select "li.subject[data-subject=geography] .progress-line[data-line=optional] .progress-text", "Facoltativi: 0 fatti su 1"
    assert_select "li.subject[data-subject=computer_science] .progress-line[data-line=optional] .progress-text", "Facoltativi: 0 fatti su 1"
    assert_select "li.subject[data-subject]", 4, "math and the three subjects holding civics topics: the card is not a subject"
    page(OFFICIAL, "/today")
    assert_response :success
    assert_select "#my-path .progress-line[data-line=required] .progress-text", "Argomenti obbligatori fatti: 1 su 3"
    assert_select "#my-path .progress-line[data-line=optional] .progress-text", "Facoltativi fatti: 0"
    assert_select "a[href='/civics']", 0
    assert_select "#civics-card", 0
    assert_select "#course-part [data-topic=?]", EXTRA_TOPIC, 0
    assert_select "#course-part [data-topic=?]", DIGITAL_TOPIC, 0
  end

  # ---- the teacher's preview and who may not --------------------------------------------------------------

  test "the preview has the card and the page on its own addresses, in the view the teacher chose" do
    build_civics_world
    page(TEACHER, "#{ROOT}/subjects")
    assert_select "#civics-card a.subject-name[href='#{ROOT}/civics']", "Educazione civica"
    assert_select "#civics-card [data-civics-count]", "4 argomenti"
    page(TEACHER, "#{ROOT}/civics")
    assert_response :success
    assert_select "a.back[href='#{ROOT}/subjects']"
    assert_equal [ DONE_TOPIC, TODO_TOPIC, EXTRA_TOPIC ], keys_in("constitution")
    assert_select "li[data-topic=?] a.topic-title[href=?]", TODO_TOPIC, "#{ROOT}/topics/#{TODO_TOPIC}"
    assert_select "li[data-topic=?][data-status=todo]", DONE_TOPIC, 1, "the preview student has its own rows"
    assert_select "a[href^='/topics']", 0
    post_form(TEACHER, "#{ROOT}/view", { view: "drafts", back: "#{ROOT}/civics" })
    page(TEACHER, "#{ROOT}/civics")
    assert_equal [ DIGITAL_TOPIC, DRAFT_TOPIC ], keys_in("digital"), "with the drafts the unapproved topic is there"
  end

  test "the teacher and a guest are refused like on the other student pages" do
    build_civics_world
    [ TEACHER, GUEST ].each do |who|
      page(who, "/civics")
      assert_response :forbidden, "/civics for #{who['Remote-User']}"
      page(who, "/subjects")
      assert_response :forbidden
    end
    page(GUEST, "#{ROOT}/civics")
    assert_response :forbidden
    page({}, "/civics")
    assert_response :forbidden
  end

  # ---- the list in git --------------------------------------------------------------------------------

  test "civics.yml: three nuclei, each with texts and topics, every key a well-formed lesson key, none twice" do
    nuclei = Course::Civics.config
    assert_equal %w[constitution sustainability digital], nuclei.map { |n| n.fetch("key") }
    assert_equal [ "Costituzione", "Sviluppo economico e sostenibilità", "Cittadinanza digitale" ], nuclei.map { |n| n.fetch("title_it") }
    nuclei.each do |nucleus|
      assert nucleus["intro_it"].to_s.strip.present?, "#{nucleus['key']} has a one-line intro"
      assert_not_includes nucleus["intro_it"], "\n"
      assert nucleus["topics"].is_a?(Array) && nucleus["topics"].any?, "#{nucleus['key']} has topics"
    end
    keys = nuclei.flat_map { |n| n.fetch("topics") }
    assert_equal keys.uniq, keys, "no key repeats, in a nucleus or across them"
    keys.each do |key|
      assert_match(/\A(ripasso|ponte|lezione|extra)\.[a-z_]+\.[a-z0-9]+(-[a-z0-9]+)*\z/, key)
      kind, = key.split(".")
      assert_includes Lesson::KINDS, kind, key
    end
  end
end
