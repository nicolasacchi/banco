require "test_helper"
require_relative "../support/decision_world"
require_relative "../support/multi_user"
require_relative "../support/topic_world"
require_relative "../support/lesson_render_world"

# The render check around the browser (R4, D-249): what the API says of it, the shots, the teacher's page and line, the
# topic gate's reason. The check itself (Chrome) is tested in test/validation/lesson_render_runner_test.rb.
class LessonRenderTest < ActionDispatch::IntegrationTest
  include ActiveJob::TestHelper
  include DecisionWorld
  include MultiUser
  include TopicWorld
  include LessonRenderWorld

  # TopicWorld stores a lesson/1; this stores the served lesson/2 fixture under the topic's key.
  def lesson_revision_with_body!(key, skill)
    lesson = Lesson.find_by(key: key) || Lesson.create!(subject: Subject.find_by!(key: key.split(".", 3)[1]), key: key, kind: "ripasso")
    md = "---\nkey: #{key}\n---\n"
    body = served("equations").merge("key" => key, "skills" => [ skill ])
    LessonRevision.create!(lesson: lesson, seq: 1, source_md: md, source_sha256: Digest::SHA256.hexdigest(md), body_json: JSON.generate(body),
                           rules_version: Validation::Rules.version.to_s, warnings_json: "[]")
  end

  setup do
    ENV["BANCO_TEACHER_USERS"] = "nik,teacher-a@example.test"
    ENV["BANCO_GUEST_USERS"] = "guest-a@example.test"
    @shots_dir = Dir.mktmpdir("lesson-shots")
    ENV["BANCO_LESSON_SHOTS_DIR"] = @shots_dir
    @world = build_ui_subject(approve: false)
    @subject = @world[:subject]
    @graph = SkillGraphRevision.where(subject: @subject).order(:seq).last
    build_topic_world
    @token = ApiToken.issue!(role: "agent_claude", label: "render test")
    @revision = @lesson_revision
  end

  teardown do
    ENV.delete("BANCO_LESSON_SHOTS_DIR")
    FileUtils.rm_rf(@shots_dir)
  end

  def webp(text) = "RIFF#{[ text.bytesize + 4 ].pack('V')}WEBP#{text}"

  # A render row with shots written to the store (card, viewport) => bytes.
  def render_row!(status: "passed", errors: [], cards: { 1 => "390x844-cream", 2 => "1280x800-cream" }, revision: @revision, at: Time.current)
    shots = cards.map do |card, spec|
      viewport, text = Array(spec)
      bytes = webp(text || "card #{card} #{viewport}")
      { "card" => card, "level" => "core", "viewport" => viewport, "sha256" => LessonShots.put(bytes), "bytes" => bytes.bytesize, "width" => viewport.to_i, "height" => 900 }
    end
    LessonRender.create!(lesson_revision: revision, status: status, rules_version: "8", harness_version: Validation::Harness.lesson_version, chrome_version: "Test/1",
                         attempt: 1, result_json: JSON.generate("errors" => errors, "elapsed_seconds" => 3.2), shots_json: JSON.generate(shots), created_at: at)
  end

  def api(path) = on(:api, path, headers: { "Authorization" => "Bearer #{@token}" })

  # ---- the gate ----

  test "a lesson/2 topic is not approvable until its render has no error, and the reason says which case" do
    record_viewed!
    reasons = -> { Approval::TopicGate.mechanical(@topic).reasons.grep(/render/) }
    assert_equal [ "the lesson revision has no render without errors yet: the render check has not run" ], reasons.call
    LessonRender.create!(lesson_revision: @revision, status: "error", harness_version: "x", result_json: "{}", shots_json: "[]")
    assert_match(/could not run/, reasons.call.first)
    render_row!(status: "failed", errors: [ { "code" => "E-LESSON-OVERFLOW", "card" => 3, "viewport" => "390x844-cream", "message" => "wide" } ])
    assert_match(/found 1 error\(s\) \(E-LESSON-OVERFLOW on card 3\)/, reasons.call.first)
    refute Approval::TopicGate.mechanical(@topic).approvable
    render_row!
    assert_empty reasons.call
    assert Approval::TopicGate.mechanical(@topic).approvable
  end

  test "the reasons are said in Italian" do
    assert_equal "Il controllo grafico della lezione non è ancora stato fatto.", Teacher::Wording.italian("the lesson revision has no render without errors yet: the render check has not run")
    assert_match(/trovato 2 errori/, Teacher::Wording.italian("the lesson revision has no render without errors: the render check found 2 error(s) (E-DIAGRAM-LAYOUT on card 3, E-LESSON-RENDER)"))
    assert_match(/riprova/, Teacher::Wording.italian("the lesson revision has no render without errors: the render check could not run, it runs again"))
  end

  # ---- the API ----

  test "lesson status shows the render: pending, then the result with its errors" do
    api("/api/v1/lesson-revisions/#{@revision.id}")
    assert_response :ok
    assert_equal "pending", response.parsed_body.dig("render", "status")
    render_row!(status: "failed", errors: [ { "code" => "E-DIAGRAM-LAYOUT", "card" => 3, "viewport" => "390x844-cream", "message" => "two labels overlap" } ])
    api("/api/v1/lesson-revisions/#{@revision.id}")
    status = response.parsed_body["render"]
    assert_equal "failed", status["status"]
    assert_equal 2, status["shots"]
    assert_equal 2, status["shots_available"]
    assert_equal "E-DIAGRAM-LAYOUT", status["errors"].first["code"]
    assert_equal 3.2, status["elapsed_seconds"]
  end

  test "lesson shots: the list, then each image by its content address, and a purged one is said to be removed" do
    api("/api/v1/lesson-revisions/#{@revision.id}/shots")
    assert_response :not_found
    row = render_row!
    api("/api/v1/lesson-revisions/#{@revision.id}/shots")
    assert_response :ok
    record_example "lesson shots", "list"
    shots = response.parsed_body["shots"]
    assert_equal [ [ 1, "390x844-cream" ], [ 2, "1280x800-cream" ] ], shots.map { |s| [ s["card"], s["viewport"] ] }
    api(shots.first["path"])
    assert_response :ok
    assert_equal "image/webp", response.media_type
    assert_equal webp("card 1 390x844-cream"), response.body.b
    File.delete(LessonShots.path(row.shots.last["sha256"]))
    api("/api/v1/lesson-revisions/#{@revision.id}/shots")
    assert_equal [ true, false ], response.parsed_body["shots"].map { |s| s["available"] }
    api(shots.last["path"])
    assert_response :not_found
    assert_match(/immagine rimossa/, response.parsed_body["message"])
    api("/api/v1/lesson-revisions/#{@revision.id}/shots/#{'0' * 64}")
    assert_response :not_found
    on(:api, "/api/v1/lesson-revisions/#{@revision.id}/shots")
    assert_response :unauthorized
  end

  test "lesson shots of a lesson/1 revision is not found" do
    lesson = Lesson.create!(subject: @subject, key: "ripasso.math.old", kind: "ripasso")
    md = "---\nkey: ripasso.math.old\n---\n"
    old = LessonRevision.create!(lesson: lesson, seq: 1, source_md: md, source_sha256: Digest::SHA256.hexdigest(md), body_json: JSON.generate(TopicWorld::LESSON_BODY), rules_version: "7", warnings_json: "[]")
    api("/api/v1/lesson-revisions/#{old.id}/shots")
    assert_response :not_found
  end

  test "a stored lesson/2 revision is queued for its render, a lesson/1 is not" do
    assert_enqueued_with(job: RenderLessonRevisionJob) do
      # the same call the submit makes after storing
      RenderLessonRevisionJob.perform_later(@revision.id)
    end
    job = RenderLessonRevisionJob.new
    assert_equal "chrome", job.queue_name
    assert_equal 10, job.priority
    assert_operator job.priority, :>, ValidateItemRevisionJob.new.priority.to_i, "a render waits for item validation"
  end

  test "the lesson-review open of a lesson/2 carries the render result and the address of the pictures" do
    session = AgentSession.create!(label: "r", role: "reviewer", agent: "omp", model: "gpt-5.2")
    render_row!
    on(:api, "/api/v1/lesson-revisions/#{@revision.id}/review", headers: { "Authorization" => "Bearer #{@token}", "X-Banco-Session" => session.id.to_s })
    body = response.parsed_body
    assert_equal "passed", body.dig("render", "status"), body.inspect
    assert_equal "/api/v1/lesson-revisions/#{@revision.id}/shots", body.dig("render", "shots_url")
  end

  # ---- the teacher ----

  test "the teacher and a guest see the pictures page and the images; a student does not; the API listener has none" do
    render_row!
    path = "/teacher/lesson-revisions/#{@revision.id}/shots"
    [ TEACHER, GUEST ].each do |headers|
      on(:web, path, headers: headers, remote_addr: EDGE)
      assert_response :success
      assert_select "img", 2
      assert_select "h2", /Scheda 1/
    end
    sha = LessonRender.last.shots.first["sha256"]
    on(:web, "#{path}/#{sha}", headers: GUEST, remote_addr: EDGE)
    assert_response :success
    assert_equal "image/webp", response.media_type
    on(:web, "#{path}/#{'1' * 64}", headers: TEACHER, remote_addr: EDGE)
    assert_response :not_found
    on(:web, path, headers: OFFICIAL, remote_addr: EDGE)
    assert_response :forbidden
    on(:api, path, headers: { "Authorization" => "Bearer #{@token}" })
    assert_response :not_found
    File.delete(LessonShots.path(sha))
    on(:web, "#{path}/#{sha}", headers: TEACHER, remote_addr: EDGE)
    assert_response :gone
    on(:web, path, headers: TEACHER, remote_addr: EDGE)
    assert_select "p", /immagine rimossa/
  end

  test "the topic page has one line: no error with the count, or the errors by card with a link that opens the box on it" do
    open_topic_page!(headers: TEACHER)
    assert_response :success
    assert_select "#render-line[data-render-state=pending]"
    render_row!(cards: (1..35).to_h { |i| [ i, "390x844-cream" ] })
    open_topic_page!(headers: TEACHER)
    assert_select "#render-line[data-render-state=passed]", /Controllo grafico:\s*nessun errore \(35 immagini\)/
    assert_select "#render-line a[href=?]", "/teacher/lesson-revisions/#{@revision.id}/shots"
    render_row!(status: "failed", errors: [ { "code" => "E-LESSON-OVERFLOW", "card" => 3, "viewport" => "390x844-cream", "message" => "wide" },
                                            { "code" => "E-DIAGRAM-LAYOUT", "card" => 3, "viewport" => "1280x800-cream", "message" => "overlap" } ])
    open_topic_page!(headers: TEACHER)
    assert_select "#render-line[data-render-state=failed]", /2 errori/
    assert_select "#render-line a[data-card='3'][data-action='lesson2-preview#goto']", /Scheda 3: Togli lo stesso peso/
    assert_select "#approve-checks [data-check=render][data-done=false]"
  end

  # ---- the job ----

  test "the job appends one verdict, does nothing twice, and Chrome trouble is an error row per attempt and never a pass" do
    fake = ->(revision, attempt: 1) { Struct.new(:revision) { define_method(:call) { LessonRender.create!(lesson_revision: revision, status: "passed", harness_version: Validation::Harness.lesson_version, result_json: "{}", shots_json: "[]") } }.new(revision) }
    Validation::LessonRenderCheck.stub(:new, fake) do
      RenderLessonRevisionJob.perform_now(@revision.id)
      RenderLessonRevisionJob.perform_now(@revision.id)
    end
    assert_equal %w[passed], LessonRender.where(lesson_revision_id: @revision.id).pluck(:status)

    other = lesson_revision_with_body!("ripasso.math.other", "math.number")
    runner = Object.new
    runner.define_singleton_method(:call) { raise Validation::ChromeRunner::Unavailable, "no chrome" }
    Validation::ChromeRunner.stub(:session, ->(**) { runner.call }) do
      perform_enqueued_jobs { RenderLessonRevisionJob.perform_later(other.id) }
    end
    assert_equal %w[error error error], LessonRender.where(lesson_revision_id: other.id).order(:id).pluck(:status)
    assert_includes LessonRender.where(lesson_revision_id: other.id).last.result["message"], "no chrome"
    assert_nil LessonRender.verdict_for(other)
  end

  test "an unknown revision and a lesson/1 revision are ignored" do
    assert_nothing_raised { RenderLessonRevisionJob.perform_now(0) }
  end

  # ---- the purge ----

  test "the purge removes the files of unpinned, superseded, old renders and only those" do
    # @revision is pinned by @topic: its old render stays
    pinned = render_row!(cards: { 1 => "390x844-cream" }, at: 90.days.ago)
    other_lesson = Lesson.create!(subject: @subject, key: "ripasso.math.gone", kind: "ripasso")
    md = "---\nkey: ripasso.math.gone\n---\n"
    revision = ->(seq) { LessonRevision.create!(lesson: other_lesson, seq: seq, source_md: md, source_sha256: Digest::SHA256.hexdigest(md + seq.to_s), body_json: @revision.body_json, rules_version: "8", warnings_json: "[]") }
    old = revision.call(1)
    latest = revision.call(2)
    doomed = render_row!(revision: old, cards: { 1 => [ "390x844-cream", "only doomed" ], 2 => [ "390x844-cream", "shared" ] }, at: 40.days.ago)
    young = render_row!(revision: old, cards: { 5 => "390x844-cream" }, at: 2.days.ago)
    of_latest = render_row!(revision: latest, cards: { 1 => [ "390x844-cream", "shared" ], 3 => [ "390x844-cream", "latest only" ] }, at: 60.days.ago)
    only_doomed = doomed.shots.first["sha256"]
    shared = doomed.shots.last["sha256"]
    assert_equal shared, of_latest.shots.first["sha256"], "one file, by content"

    dry = LessonShots.purge(dry_run: true)
    assert_equal [ only_doomed ], dry[:deleted]
    assert File.exist?(LessonShots.path(only_doomed)), "a dry run deletes nothing"

    result = LessonShots.purge
    assert_equal [ only_doomed ], result[:deleted]
    refute File.exist?(LessonShots.path(only_doomed))
    assert File.exist?(LessonShots.path(shared)), "a file that the latest revision's render also names stays"
    assert File.exist?(LessonShots.path(pinned.shots.first["sha256"])), "a pinned revision's render stays"
    assert File.exist?(LessonShots.path(young.shots.first["sha256"])), "a render under 30 days stays"
    assert File.exist?(LessonShots.path(of_latest.shots.last["sha256"])), "the latest revision of its lesson stays"
    assert_equal 4, LessonRender.count, "the rows stay (the ledger)"
    assert_equal [ false, true ], doomed.shots.map { |s| LessonShots.exist?(s["sha256"]) }
  end
end
