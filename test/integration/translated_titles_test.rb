require "test_helper"
require_relative "../support/multi_user"
require_relative "../support/student_course_world"

# The course pages of english and spanish (D-402): topic titles, the topic intro and the skill names in the target language when the course
# entry, the topic revision and the skill graph carry the pair (`title_en`, `intro_en`, `label_en`), each with its Italian under it, one tap away;
# an entry without the pair reads as it always did. The test world has a math subject, so the language is told through Lessons::Lang.target.
class TranslatedTitlesTest < ActionDispatch::IntegrationTest
  include MultiUser
  include StudentCourseWorld

  TITLE_EN = "Linear equations".freeze
  INTRO_EN = "Here you learn to solve equations.".freeze
  LABEL_EN = "Equations with whole numbers".freeze

  setup { build_student_world }

  # math teaches english for the length of the block
  def as_english
    original = Lessons::Lang.method(:target)
    Lessons::Lang.define_singleton_method(:target) { |subject| subject.to_s == "math" ? "en" : original.call(subject) }
    yield
  ensure
    Lessons::Lang.define_singleton_method(:target, original)
  end

  # A new graph, course map and topic revision on top of the world's, released and approved; each pair is optional.
  def pair!(title: true, intro: true, label: true)
    with_intro = intro
    graph = JSON.parse(@graph.body_json)
    graph["skills"].find { |s| s["key"] == SKILL }["label_en"] = LABEL_EN if label
    SkillGraphRevision.create!(subject: @subject, seq: 2, body_json: JSON.generate(graph))
    entry = { key: TOPIC, kind: "ripasso", title_it: TOPIC_TITLE, skills: [ SKILL ], minutes: 30, term: 1, after: [] }
    entry[:title_en] = TITLE_EN if title
    course = build_course_map(skills: [], topics: [ entry ])
    texts = { intro_it: "Qui impari a risolvere le equazioni." }
    texts[:intro_en] = INTRO_EN if with_intro
    topic = TopicRevision.create!(lesson: @lesson, seq: 2, course_revision: course, lesson_revision: @lesson_revision,
                                  body_json: JSON.generate({ schema: "banco.topic/1", key: TOPIC, practice: [ { skill: SKILL, items: @revisions.map { |r| { item: r.item.key, revision: r.id } } } ] }.merge(texts)))
    approve_topic!(topic)
    release_course!(course)
  end

  def page(headers, path) = on(:web, path, headers: headers, remote_addr: EDGE)

  test "a paired entry shows the target-language title with its Italian under it, on Oggi and on the subject's list" do
    pair!
    as_english do
      [ "/today", "/subjects/math" ].each do |path|
        page(OFFICIAL, path)
        assert_response :success
        assert_select "a.topic-title span[lang=en]", TITLE_EN, path
        assert_select "a.topic-title .tr[lang=it][data-nospeech]", TOPIC_TITLE, path
        assert_select "main[data-tr-scope=page][data-translation=off][data-tr-surface=topics][data-tr-url='/translations']", 1, path
        assert_select "button.tr-toggle[aria-pressed=false][data-controller=translation][data-action='click->translation#toggle']", text: "Traduzione"
        assert_select "html[data-translation=ask]"
      end
    end
  end

  test "an entry without the pair reads as before: the Italian title, no translation node, no scope, no button" do
    pair!(title: false, intro: false, label: false)
    as_english do
      [ "/today", "/subjects/math", "/topics/#{TOPIC}" ].each do |path|
        page(OFFICIAL, path)
        assert_select ".tr", 0, path
        assert_select "[data-tr-scope]", 0, path
        assert_select "button.tr-toggle", 0, path
      end
      page(OFFICIAL, "/subjects/math")
      assert_select "a.topic-title", TOPIC_TITLE
    end
  end

  test "a subject that teaches no language never pairs, whatever the course map holds" do
    pair!
    page(OFFICIAL, "/subjects/math")
    assert_select "a.topic-title", TOPIC_TITLE
    assert_select ".tr", 0
    assert_select "[data-tr-scope]", 0
  end

  test "the topic page: the title, the intro and the skill name each with its Italian, in one scope named for the topic" do
    pair!
    as_english do
      page(OFFICIAL, "/topics/#{TOPIC}")
      assert_response :success
      assert_select "title", TITLE_EN
      assert_select "h1 span[lang=en]", TITLE_EN
      assert_select "h1 .tr[lang=it]", TOPIC_TITLE
      assert_select "p#intro[lang=en]", INTRO_EN
      assert_select "p#intro + p.tr[lang=it][data-nospeech]", "Qui impari a risolvere le equazioni."
      assert_select ".skill-name span[lang=en]", LABEL_EN
      assert_select ".skill-name .tr[lang=it]", "Equazioni lineari intere"
      assert_select "main[data-tr-scope=page][data-tr-topic='#{TOPIC}']", 1
      assert_select "header.page-header .page-actions button.tr-toggle", 1
    end
  end

  test "the topic's lone halves: an intro or a label without its pair is the Italian text, the title pair still offers its translation" do
    pair!(intro: false, label: false)
    as_english do
      page(OFFICIAL, "/topics/#{TOPIC}")
      assert_select "p#intro", "Qui impari a risolvere le equazioni."
      assert_select "p#intro + p.tr", 0
      assert_select ".skill-name", "Equazioni lineari intere"
      assert_select ".skill-name .tr", 0
      assert_select "h1 .tr[lang=it]", TOPIC_TITLE
    end
  end

  test "the schema page names the topic in the target language with its Italian under the title" do
    pair!
    as_english do
      page(OFFICIAL, "/topics/#{TOPIC}/schema")
      assert_response :success
      assert_select "title", /#{TITLE_EN}/
      assert_select "p.tr[lang=it]", /#{TOPIC_TITLE}/
    end
  end

  test "the preview shows the translation open and posts nothing: no address on the scope" do
    pair!
    as_english do
      page(TEACHER, "/teacher/preview/subjects/math")
      assert_response :success
      assert_select "html[data-translation=always]"
      assert_select "a.topic-title .tr[lang=it]", TOPIC_TITLE
      assert_select "main[data-tr-scope=page]:not([data-tr-url])", 1
    end
  end

  test "the practice page names the skill in the language it teaches with its Italian under it, in a page scope of its own" do
    pair!
    as_english do
      page(OFFICIAL, "/topics/#{TOPIC}/practice/#{SKILL}")
      assert_response :success
      assert_select "title", /#{LABEL_EN}/
      assert_select "h1#skill-name[lang=en]", LABEL_EN
      assert_select "header.page-header p.tr[lang=it][data-nospeech]", "Equazioni lineari intere"
      assert_select "main.practice[data-tr-scope=page][data-translation=off][data-tr-surface=practice][data-tr-topic='#{TOPIC}'][data-tr-url='/translations']", 1
      assert_select "p.tr-bar button.tr-toggle[data-controller=translation]", text: "Traduzione"
      assert_select ".exercise-card[data-tr-surface=practice]", 1, "the exercise card keeps its own scope"
    end
  end

  test "the practice page of a skill without the pair is as before: the Italian name, no translation node, no page scope" do
    pair!(label: false)
    as_english do
      page(OFFICIAL, "/topics/#{TOPIC}/practice/#{SKILL}")
      assert_select "h1#skill-name:not([lang])", "Equazioni lineari intere"
      assert_select "header.page-header .tr", 0
      assert_select "main.practice[data-tr-scope]", 0
      assert_select "p.tr-bar", 0
    end
  end

  test "the exercise list is told the skill as a pair, and the views give the pairs the serve and the closing screen carry" do
    pair!
    as_english do
      on(:web, "/practice/exercises?topic=#{TOPIC}", headers: OFFICIAL.merge("Accept" => "application/json"), remote_addr: EDGE)
      listed = response.parsed_body["skills"].first
      assert_equal [ LABEL_EN, "Equazioni lineari intere" ], listed.values_at("label_en", "label_it")
      view = Course::StudentView.new(Student.find_by!(key: "student"))
      assert_equal({ label_en: LABEL_EN, label_it: "Equazioni lineari intere" }, view.label_pair(SKILL))
      assert_equal({ title_en: TITLE_EN, title_it: TOPIC_TITLE }, view.find_topic(TOPIC).last.title_pair)
    end
  end

  test "an entry or a skill without the pair is told as the one Italian text" do
    pair!(title: false, label: false, intro: false)
    as_english do
      on(:web, "/practice/exercises?topic=#{TOPIC}", headers: OFFICIAL.merge("Accept" => "application/json"), remote_addr: EDGE)
      listed = response.parsed_body["skills"].first
      assert_equal "Equazioni lineari intere", listed["label_it"]
      assert_not listed.key?("label_en")
      view = Course::StudentView.new(Student.find_by!(key: "student"))
      assert_equal({ label_it: "Equazioni lineari intere" }, view.label_pair(SKILL))
      assert_equal({ title_it: TOPIC_TITLE }, view.find_topic(TOPIC).last.title_pair)
    end
  end

  test "the API and the teacher keep the Italian: label_italian and the topic's title_it" do
    pair!
    as_english do
      view = Course::StudentView.new(Student.find_by!(key: "student"))
      assert_equal LABEL_EN, view.label(SKILL)
      assert_equal "Equazioni lineari intere", view.label_italian(SKILL)
      assert_equal "Equazioni lineari intere", view.label_translation(SKILL)
      _, topic = view.find_topic(TOPIC)
      assert_equal [ TITLE_EN, TOPIC_TITLE, true ], [ topic.title, topic.title_it, topic.title_paired? ]
      assert_equal "en", topic.lang
      student = Student.find_by!(key: "student")
      json = Course::StudentProgress.new(student, view: view).as_json.to_json
      assert_includes json, TOPIC_TITLE
      assert_includes json, "Equazioni lineari intere"
      refute_includes json, TITLE_EN
      refute_includes json, LABEL_EN
    end
  end

  test "without a pair the view answers the Italian label and no translation" do
    pair!(title: false, label: false, intro: false)
    as_english do
      view = Course::StudentView.new(Student.find_by!(key: "student"))
      assert_equal "Equazioni lineari intere", view.label(SKILL)
      assert_nil view.label_translation(SKILL)
      _, topic = view.find_topic(TOPIC)
      assert_equal [ TOPIC_TITLE, false ], [ topic.title, topic.title_paired? ]
    end
  end

  test "the changelog line of a revised topic names it as the student's course does" do
    update = Changelog::ContentUpdates::Update.new(decision_id: 1, at: Time.current, subject_key: "math", topic: TOPIC, title_it: TOPIC_TITLE, old_revision_id: 1,
                                                   new_revision_id: 2, reason_it: nil, via: "web", title_target: TITLE_EN)
    assert_equal TITLE_EN, update.title
    assert_equal TOPIC_TITLE, update.with(title_target: nil).title
  end
end
