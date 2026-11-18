require "test_helper"
require "minitest/mock"
require_relative "../../support/practice_world"
require_relative "../../support/lesson_render_world"
require_relative "../../support/speech_world"

# D-359: the backfill finds the lesson revisions the official student sees now and the approved ones, says what each needs, and enqueues the jobs
# only when confirmed; the samples of «Prova le voci» are made like any clip.
class SpeechBackfillTest < ActiveJob::TestCase
  include PracticeWorld
  include SpeechWorld

  KEY = "lezione.math.linear-systems".freeze
  SKILL = "math.linear-system-substitution".freeze

  setup do
    build_course
    @official = practice_student("student")
    @course = build_course_map
    @item = make_practice_item("math-sp-1", SKILL)
    @lesson = Lesson.create!(subject: @subject, key: KEY, kind: "lezione")
    @first = lesson_revision!(1)
    @second = lesson_revision!(2)
    @third = lesson_revision!(3)
    @topics = [ @first, @second, @third ].map { |r| make_topic(r, { SKILL => [ @item ] }, course: @course) }
    decide!("approve_topic", @topics[0])
    decide!("approve_topic", @topics[1])
    decide!("release_course", nil)
    @stub = Speech::Client::Stub.new
  end

  def lesson_revision!(seq)
    body = served("equations").merge("key" => KEY, "skills" => [ SKILL ])
    LessonRevision.create!(lesson: @lesson, seq: seq, source_md: "---\n", source_sha256: seq.to_s * 64, body_json: JSON.generate(body),
                           rules_version: Validation::Rules.version.to_s, warnings_json: "[]")
  end

  def decide!(kind, topic)
    payload = kind == "approve_topic" ? { topic_revision_id: topic.id, topic: KEY, seq: topic.seq, course_revision_id: topic.course_revision_id } :
                                        { subject: "math", open: true, course_revision_id: @course.id }
    Decision.create!(kind: kind, subject: @subject, payload_json: JSON.generate(payload), request_id: SecureRandom.hex(4), teacher_login: "nik", remote_addr: "127.0.0.1")
  end

  test "it takes the revision the student sees and the approved ones, not a draft nobody approved" do
    assert_equal [ @first, @second ], Speech::Backfill.revisions
  end

  test "each revision is classified: clips to make, complete, to draw again, render failed" do
    render_row!(@first, [ seg("it", "Ciao."), seg("en", "Hello.") ])
    render_row!(@second, nil) # drawn before the segments were collected
    rows = Speech::Backfill.rows.index_by { |r| r.revision.id }
    assert_equal [ :speak, 2, 2 ], rows[@first.id].to_h.values_at(:action, :missing, :total)
    assert_equal :render, rows[@second.id].action

    Speech::Client.using(@stub) { SpeakLessonRevisionJob.perform_now(@first.id) }
    assert_equal :complete, Speech::Backfill.rows.find { |r| r.revision == @first }.action

    failed = lesson_revision!(4)
    render_row!(failed, nil, status: "failed")
    assert_equal :render_failed, Speech::Backfill.stub(:revisions, [ failed ]) { Speech::Backfill.rows.first.action }
    old = lesson_revision!(5)
    render_row!(old, nil, status: "failed", harness_version: "an older host")
    assert_equal :render, Speech::Backfill.stub(:revisions, [ old ]) { Speech::Backfill.rows.first.action }, "a failure of an older host is drawn again"
  end

  test "a dry run enqueues nothing and counts; a confirmed run enqueues the speak job, the render job and the samples" do
    render_row!(@first, [ seg("it", "Ciao.") ])
    render_row!(@second, nil)
    summary = nil
    assert_no_enqueued_jobs { summary = Speech::Backfill.run }
    assert_equal({ revisions: 2, speak: 1, render: 1, complete: 0, render_failed: 0, missing_clips: 1, samples_missing: 5 }, summary)
    assert_enqueued_jobs 3 do
      Speech::Backfill.run(confirm: true)
    end
    assert_enqueued_with(job: SpeakLessonRevisionJob, args: [ @first.id ])
    assert_enqueued_with(job: RenderLessonRevisionJob, args: [ @second.id ])
    assert_enqueued_with(job: SpeakSamplesJob)
  end

  test "the samples are the first sentence of each language's sample, once per server voice" do
    entries = Speech::Samples.entries
    assert_equal [ [ "im_nicola", "Ciao, questa è la mia voce." ], [ "af_heart", "Hello, this is my voice." ], [ "af_bella", "Hello, this is my voice." ],
                   [ "ef_dora", "Hola, esta es mi voz." ], [ "em_alex", "Hola, esta es mi voz." ] ], entries.map { |e| [ e.voice, e.text ] }
    assert_equal [ 1, 1, 2, 1, 2 ], entries.map(&:number)
    Speech::Client.using(@stub) { SpeakSamplesJob.perform_now }
    assert_equal 5, SpeechClip.count
    assert_equal 0, Speech::Backfill.run[:samples_missing]
    assert_equal "Hola, esta es mi voz.", Speech::Samples.first_sentence("Hola, esta es mi voz. Cuando llegue, te llamaré.")
    assert_equal "Una frase senza punto", Speech::Samples.first_sentence("Una frase senza punto")
  end
end
