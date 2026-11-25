require "test_helper"
require_relative "../support/course_rows"
require_relative "../support/public_api_tokens"
require_relative "../support/contract_examples"

# The item shots around the browser (D-336): the API (roles, one job per request, the list, the image), the harness listener's render host (no key in the
# page, the figure's address), the append-only rows and the purge. The drawing itself (Chrome) is tested in test/validation/item_render_runner_test.rb.
class ItemShotsApiTest < ActionDispatch::IntegrationTest
  include ActiveJob::TestHelper
  include CourseRows
  include PublicApiTokens

  SECRET = "zq-secret-91".freeze

  setup do
    build_course
    @shots_dir = Dir.mktmpdir("item-shots-api")
    ENV["BANCO_LESSON_SHOTS_DIR"] = @shots_dir
    @revision = make_revision("shots-1", "math.number", instances: 3, component: "choice")
    @agent = issue_token("agent_claude")
    @bot = issue_token("bot_read")
    @teacher = issue_token("teacher")
  end

  teardown do
    ENV.delete("BANCO_LESSON_SHOTS_DIR")
    FileUtils.rm_rf(@shots_dir)
  end

  def webp(text) = "RIFF#{[ text.bytesize + 4 ].pack('V')}WEBP#{text}"

  def shots_path(revision = @revision) = "/api/v1/item-revisions/#{revision.id}/shots"

  def post_shots(token, query = "", headers: {}) = api_as(token, "#{shots_path}#{query}", method: :post, headers: headers)

  # A verdict row with one stored picture per instance, as Validation::ItemRenderCheck leaves it.
  def verdict!(status: "passed", errors: [], revision: @revision, at: Time.current, instances: 2, tag: "")
    shots = (1..instances).map do |n|
      bytes = webp("instance #{n}#{tag}")
      { "instance" => n, "seed" => "item-shots|#{revision.id}|#{n}", "shown_order" => { "options" => %w[o3 o1 o4 o2] }, "viewport" => "390x844-cream", "width" => 390,
        "height" => 700 + n, "scale" => 1, "sha256" => LessonShots.put(bytes), "bytes" => bytes.bytesize }
    end
    ItemRender.create!(item_revision: revision, status: status, rules_version: "10", harness_version: Validation::Harness.item_version, chrome_version: "Test/1", attempt: 1,
                       result_json: JSON.generate("errors" => errors, "instances" => instances, "instances_total" => instances, "viewport" => "390x844-cream", "elapsed_seconds" => 4.2),
                       shots_json: JSON.generate(shots), created_at: at)
  end

  # ---- reading ----

  test "a revision with no render says so and says how to ask; the list needs a token and a known revision" do
    api_as(@agent, shots_path)
    assert_response :ok
    assert_equal "none", json["status"]
    assert_equal [], json["shots"]
    assert_equal 3, json["instances"]
    assert_match(/banco item shots #{@revision.id} --dir DIR --wait/, json["next"])
    api_as(nil, shots_path)
    assert_response :unauthorized
    api_as(@agent, "/api/v1/item-revisions/999999/shots")
    assert_response :not_found
    assert_equal "E-NOT-FOUND", json["code"]
  end

  test "every token role reads the list and the image" do
    verdict!
    sha = ItemRender.last.shots.first["sha256"]
    [ @agent, @bot, @teacher, issue_token("agent_omp"), issue_token("ci") ].each do |token|
      api_as(token, shots_path)
      assert_response :ok, "list"
      api_as(token, "#{shots_path}/#{sha}")
      assert_response :ok, "image"
    end
  end

  test "the list: status, findings apart from notes, the shots with seed, shown order, size and address; the image is the file" do
    verdict!(status: "failed", errors: [ { "code" => "E-ITEM-OVERFLOW", "instance" => 2, "message" => "the page is 900 px wide in a 390 px window", "where" => "page" },
                                         { "code" => "E-ITEM-RENDER", "message" => "the item has 90 instances: the first 40 are pictured", "where" => "instances", "level" => "note" } ])
    api_as(@agent, shots_path)
    assert_response :ok
    record_example "item shots", "list"
    assert_equal "failed", json["status"]
    assert_equal [ "E-ITEM-OVERFLOW" ], json["errors"].map { |e| e["code"] }
    assert_equal [ "note" ], json["notes"].map { |e| e["level"] }
    assert_equal "390x844-cream", json["viewport"]
    assert_match(/shown_order\[column\]\[n-1\]/, json["seed_note"])
    first = json["shots"].first
    assert_equal [ 1, "item-shots|#{@revision.id}|1", { "options" => %w[o3 o1 o4 o2] }, 390, 1, true ], first.values_at("instance", "seed", "shown_order", "width", "scale", "available")
    api_as(@bot, first["path"])
    assert_response :ok
    assert_equal "image/webp", response.media_type
    assert_equal webp("instance 1"), response.body.b
  end

  # D-402: a bilingual item has a second picture of instance 1, with the Italian translation open. It is its own shot (its own bytes, its own address), the list
  # says `state: "tr"` for it and nothing for the pictures as drawn, so that a client can save the two apart (banco item shots: instance-01-tr_390x844.webp).
  test "the picture with the translation open is a shot of its own in the list, with its state and its own address" do
    plain = webp("instance 1 as drawn")
    open = webp("instance 1 with the translation open")
    shots = [ { "instance" => 1, "seed" => "item-shots|#{@revision.id}|1", "shown_order" => {}, "sha256" => LessonShots.put(plain), "bytes" => plain.bytesize, "height" => 700 },
              { "instance" => 1, "state" => Items::ShotPresentation::TRANSLATION_STATE, "seed" => "item-shots|#{@revision.id}|1", "shown_order" => {}, "sha256" => LessonShots.put(open),
                "bytes" => open.bytesize, "height" => 820 } ].map { |s| s.merge("viewport" => "390x844-cream", "width" => 390, "scale" => 1) }
    ItemRender.create!(item_revision: @revision, status: "passed", rules_version: "10", harness_version: Validation::Harness.item_version, chrome_version: "Test/1", attempt: 1,
                       result_json: JSON.generate("errors" => [], "instances" => 1, "instances_total" => 1, "viewport" => "390x844-cream"), shots_json: JSON.generate(shots))
    api_as(@agent, shots_path)
    assert_response :ok
    assert_equal [ [ 1, nil ], [ 1, "tr" ] ], json["shots"].map { |s| [ s["instance"], s["state"] ] }
    assert_not json["shots"].first.key?("state"), "the picture as drawn says no state"
    assert_equal 2, json["shots"].map { |s| s["path"] }.uniq.size
    assert_equal [ plain, open ], json["shots"].map { |s| api_as(@bot, s["path"]) && response.body.b }
  end

  test "a purged image is said to be removed, an unknown one is not found, and an image of another revision is not served" do
    row = verdict!
    other = make_revision("shots-2", "math.number", instances: 1, component: "choice")
    File.delete(LessonShots.path(row.shots.last["sha256"]))
    api_as(@agent, shots_path)
    assert_equal [ true, false ], json["shots"].map { |s| s["available"] }
    api_as(@agent, "#{shots_path}/#{row.shots.last['sha256']}")
    assert_response :not_found
    assert_match(/immagine rimossa/, json["message"])
    api_as(@agent, "#{shots_path}/#{'0' * 64}")
    assert_response :not_found
    api_as(@agent, "#{shots_path(other)}/#{row.shots.first['sha256']}")
    assert_response :not_found, "a content address of one revision is not a key to the store"
  end

  test "while a forced render is queued the list says queued and keeps the pictures of the last verdict" do
    verdict!
    ItemRender.create!(item_revision: @revision, status: "queued", harness_version: "x", result_json: "{}", shots_json: "[]")
    api_as(@agent, shots_path)
    assert_equal "queued", json["status"]
    assert_equal 2, json["shots"].size
    assert_match(/--wait/, json["next"])
  end

  # ---- asking ----

  test "a content role's request appends one queued row and enqueues one job; a second request while it is queued enqueues nothing" do
    assert_enqueued_jobs 1, only: RenderItemRevisionJob do
      post_shots(@agent)
    end
    assert_response :accepted
    assert_equal true, json["enqueued"]
    assert_equal "queued", json["status"]
    row = ItemRender.where(item_revision_id: @revision.id).sole
    assert_equal "queued", row.status
    assert_enqueued_with(job: RenderItemRevisionJob, args: [ @revision.id, row.id ])
    assert_no_enqueued_jobs only: RenderItemRevisionJob do
      post_shots(issue_token("agent_omp"))
    end
    assert_response :ok
    assert_equal false, json["enqueued"]
    assert_match(/already queued/, json["why_not"])
    assert_equal 1, ItemRender.where(item_revision_id: @revision.id).count
  end

  test "a revision that has been rendered is not queued again unless force; an error or a lost job is asked again" do
    verdict!
    assert_no_enqueued_jobs only: RenderItemRevisionJob do
      post_shots(@agent)
    end
    assert_equal false, json["enqueued"]
    assert_match(/--force/, json["why_not"])
    assert_enqueued_jobs 1, only: RenderItemRevisionJob do
      post_shots(@agent, "?force=1")
    end
    assert_response :accepted
    # the forced request is pending: a plain one waits for it
    assert_no_enqueued_jobs only: RenderItemRevisionJob do
      post_shots(@agent)
    end
    # not even a forced one while a request is pending
    assert_no_enqueued_jobs only: RenderItemRevisionJob do
      post_shots(@agent, "?force=1")
    end
    assert_equal false, json["enqueued"]
    # a job lost for longer than the stale time is asked again
    travel_to 2.hours.from_now do
      assert_enqueued_jobs 1, only: RenderItemRevisionJob do
        post_shots(@agent)
      end
      assert_response :accepted
    end
    # Chrome that could not be reached is not a render
    other = make_revision("shots-3", "math.number", instances: 1, component: "choice")
    ItemRender.create!(item_revision: other, status: "error", harness_version: "x", result_json: JSON.generate("message" => "down"), shots_json: "[]")
    assert_enqueued_jobs 1, only: RenderItemRevisionJob do
      api_as(@agent, "#{shots_path(other)}", method: :post)
    end
    api_as(@agent, shots_path(other))
    assert_equal "queued", json["status"]
  end

  test "a request whose job still waits in Solid Queue is not stale however old it is: no twenty-first job behind twenty (D-402); a failed or finished job is" do
    c = ApplicationRecord.connection
    c.create_table(:solid_queue_jobs) do |t|
      t.string :queue_name, null: false
      t.string :class_name, null: false
      t.text :arguments
      t.datetime :finished_at
      t.datetime :created_at, null: false
    end
    c.create_table(:solid_queue_failed_executions) do |t|
      t.bigint :job_id, null: false
      t.text :error
      t.datetime :created_at, null: false
    end
    [ SolidQueue::Job, SolidQueue::FailedExecution ].each(&:reset_column_information)
    row = ItemRender.create!(item_revision: @revision, status: "queued", harness_version: Validation::Harness.item_version, result_json: "{}", shots_json: "[]")
    job = c.insert("INSERT INTO solid_queue_jobs (queue_name, class_name, arguments, created_at) VALUES ('chrome', 'RenderItemRevisionJob', " \
                   "#{c.quote(%({"job_class":"RenderItemRevisionJob","arguments":[#{@revision.id},#{row.id}]}))}, #{c.quote(Time.current)})")
    travel_to 3.hours.from_now do
      ActiveJob::Base.stub(:queue_adapter_name, "solid_queue") do
        refute Items::ShotRequest.stale?(row), "the job is still in the queue"
        assert_no_enqueued_jobs only: RenderItemRevisionJob do
          post_shots(@agent)
        end
        assert_equal false, json["enqueued"]
        assert_equal "queued", json["status"]
        c.execute("INSERT INTO solid_queue_failed_executions (job_id, created_at) VALUES (#{job}, #{c.quote(Time.current)})")
        assert Items::ShotRequest.stale?(row), "a job that failed is lost: ask again"
        assert_enqueued_jobs 1, only: RenderItemRevisionJob do
          post_shots(@agent)
        end
      end
    end
  end

  test "while a request is queued the list says how many requests wait before it: the queued rows that are the latest of their revision and not stale" do
    queued = ->(rev, at = Time.current) { ItemRender.create!(item_revision: rev, status: "queued", harness_version: Validation::Harness.item_version, result_json: "{}", shots_json: "[]", created_at: at) }
    other = make_revision("shots-q2", "math.number", instances: 1, component: "choice")
    third = make_revision("shots-q3", "math.number", instances: 1, component: "choice")
    answered = make_revision("shots-q4", "math.number", instances: 1, component: "choice")
    lost = make_revision("shots-q5", "math.number", instances: 1, component: "choice")
    queued.call(lost, 2.hours.ago) # a lost job: not counted
    queued.call(answered)
    verdict!(revision: answered) # answered: not counted
    queued.call(other)
    queued.call(@revision)
    queued.call(third)
    api_as(@agent, shots_path)
    assert_equal "queued", json["status"]
    assert_equal 1, json["queue_ahead"], "only `other` waits before it"
    api_as(@agent, shots_path(third))
    assert_equal 2, json["queue_ahead"]
    api_as(@agent, shots_path(answered))
    assert_not json.key?("queue_ahead"), "a revision that is not queued has no place"
  end

  test "a verdict made by an older host is asked for again without force" do
    row = verdict!
    stale = ItemRender.create!(item_revision: @revision, status: "passed", harness_version: "an-older-host", result_json: "{}", shots_json: "[]")
    assert_operator stale.id, :>, row.id
    assert_enqueued_jobs 1, only: RenderItemRevisionJob do
      post_shots(@agent)
    end
    assert_response :accepted
  end

  test "two requests in one go enqueue one job" do
    first = Items::ShotRequest.call(@revision)
    second = Items::ShotRequest.call(@revision)
    assert first.enqueued
    refute second.enqueued
    assert_equal first.row, second.row
  end

  test "only the content roles request: a bot_read or a teacher token is refused and nothing is queued" do
    assert_no_enqueued_jobs only: RenderItemRevisionJob do
      post_shots(@bot)
      assert_response :forbidden
      assert_equal "read_only_token", json["reason"]
      post_shots(@teacher)
      assert_response :forbidden
      assert_equal "teacher_token_no_content", json["reason"]
      post_shots(nil)
      assert_response :unauthorized
    end
    assert_equal 0, ItemRender.count
    [ "agent_omp", "ci" ].each do |role|
      post_shots(issue_token(role))
      assert_response :success, role # the first enqueues (202), the next finds it queued (200): never a refusal
      assert_equal "queued", json["status"], role
    end
  end

  test "a revision with no instance cannot be drawn, and a dry run queues nothing" do
    empty = make_revision("shots-empty", "math.number", instances: 0, component: "choice")
    api_as(@agent, shots_path(empty), method: :post)
    assert_response :unprocessable_entity
    assert_equal "E-ITEM-NOT-PASSED", json["code"]
    assert_no_enqueued_jobs only: RenderItemRevisionJob do
      post_shots(@agent, headers: { "X-Banco-Dry-Run" => "1" })
    end
    assert_response :ok
    assert_equal true, json["dry_run"]
    assert_equal true, json["would_enqueue"]
    assert_equal 0, ItemRender.count
    api_as(@agent, "/api/v1/item-revisions/999999/shots", method: :post)
    assert_response :not_found
  end

  test "the rows are append-only" do
    row = verdict!
    assert_raises(ActiveRecord::StatementInvalid) { ItemRender.connection.execute("UPDATE item_renders SET status = 'failed' WHERE id = #{row.id}") }
    assert_raises(ActiveRecord::StatementInvalid) { ItemRender.connection.execute("DELETE FROM item_renders WHERE id = #{row.id}") }
  end

  # ---- the job ----

  test "the job is on the chrome queue below item validation, and draws unless a verdict has been appended since its request" do
    job = RenderItemRevisionJob.new
    assert_equal "chrome", job.queue_name
    assert_equal 20, job.priority
    assert_operator job.priority, :>, ValidateItemRevisionJob.new.priority.to_i
    assert_operator job.priority, :>, RenderLessonRevisionJob.new.priority, "a shot waits for the lesson renders that gate approval"
    drew = []
    fake = Struct.new(:calls) { def call = calls << true }.new(drew)
    queued = ItemRender.create!(item_revision: @revision, status: "queued", harness_version: "x", result_json: "{}", shots_json: "[]")
    Validation::ItemRenderCheck.stub(:new, ->(*) { fake }) { RenderItemRevisionJob.perform_now(@revision.id, queued.id) }
    assert_equal [ true ], drew, "a request with no verdict after it is drawn"
    verdict!
    Validation::ItemRenderCheck.stub(:new, ->(*) { flunk "a verdict after the request is its answer" }) { RenderItemRevisionJob.perform_now(@revision.id, queued.id) }
    forced = ItemRender.create!(item_revision: @revision, status: "queued", harness_version: "x", result_json: JSON.generate("force" => true), shots_json: "[]")
    Validation::ItemRenderCheck.stub(:new, ->(*) { fake }) { RenderItemRevisionJob.perform_now(@revision.id, forced.id) }
    assert_equal [ true, true ], drew, "a forced request draws again a revision that has a verdict"
  end

  test "a crash in the check is written as an error row, and the job raises" do
    queued = ItemRender.create!(item_revision: @revision, status: "queued", harness_version: "x", result_json: "{}", shots_json: "[]")
    check = Object.new
    def check.call = raise("boom")
    recorded = []
    check.define_singleton_method(:record_error) { |e| recorded << e.message }
    Validation::ItemRenderCheck.stub(:new, ->(*) { check }) do
      assert_raises(RuntimeError) { RenderItemRevisionJob.perform_now(@revision.id, queued.id) }
    end
    assert_equal [ "boom" ], recorded
  end

  # ---- the render host (harness listener) ----

  def instance_with_secret!
    item = Item.create!(subject: @subject, key: "shots-host", kind: "diagnosis_item")
    body = { schema: "banco.item/1", schema_version: 1, kind: "diagnosis_item", subject: "math", skill: "math.number", component: "number", expected_seconds: 60,
             prompt: { stem_it: "Quanto fa?" }, hints_it: [ "Aiuto #{SECRET}" ] }
    revision = ItemRevision.create!(item: item, seq: 1, body_json: JSON.generate(body), file_sessions_json: "{}")
    ItemValidation.create!(item_revision: revision, seq: 1, status: "passed", codes_json: "[]")
    ItemInstance.create!(item_revision: revision, seed: 1, display_json: JSON.generate(stem_it: "$3+4$"), answer_json: JSON.generate(SECRET), errors_json: JSON.generate([ { code: "x", value: "wrong-#{SECRET}" } ]),
                         solution_json: JSON.generate(steps: [ { text_it: "Fa #{SECRET}" } ], final: SECRET), fingerprint: SecureRandom.hex(8))
    revision
  end

  test "the harness listener serves the host page of an instance, with the student's frame and no key, and nothing else answers it" do
    revision = instance_with_secret!
    token = Validation::Harness.issue("irev", revision.id)
    on(:harness, "/h/#{token}/item-render.html?n=1")
    assert_response :ok
    assert_equal "text/html", response.media_type
    assert_equal "no-store", response.headers["Cache-Control"]
    csp = response.headers["Content-Security-Policy"]
    assert_match(/connect-src 'none'/, csp)
    assert_match(/default-src 'none'/, csp)
    assert_match(/'sha256-[A-Za-z0-9+\/=]+'/, csp, "the inline importmap is allowed by its hash")
    assert_includes response.body, "Quanto fa?"
    assert_includes response.body, "data-theme=\"cream\""
    assert_equal [ "Invia", "Non lo so" ], css_select(".sitting-card .actions button").map { |b| b.text.strip }
    assert_includes response.body, "items/render_host"
    [ SECRET, "wrong-", "Aiuto" ].each { |secret| refute_includes response.body, secret }
    on(:harness, "/h/#{token}/item-render.html?n=1&theme=dark")
    assert_includes response.body, "data-theme=\"dark\""
    on(:harness, "/h/#{token}/item-render.html?n=2")
    assert_response :not_found
    on(:harness, "/h/#{token}/item-render.html?n=0")
    assert_response :not_found
    on(:harness, "/h/#{token}/item-render.html")
    assert_response :not_found
    on(:harness, "/h/#{Validation::Harness.issue('lrev', revision.id)}/item-render.html?n=1")
    assert_response :not_found
    on(:harness, "/h/#{Validation::Harness.issue('irev', revision.id, now: 1000)}/item-render.html?n=1")
    assert_response :not_found
    on(:harness, "/h/#{token}x/item-render.html?n=1")
    assert_response :not_found
    on(:web, "/h/#{token}/item-render.html?n=1")
    assert_response :not_found
    on(:api, "/h/#{token}/item-render.html?n=1")
    assert_response :not_found
    # the item token opens no file of the revision
    on(:harness, "/h/#{token}/generator.mjs")
    assert_response :not_found
  end

  test "a practice item is drawn in the practice page's frame, with its hint button and no hint" do
    revision = instance_with_secret!
    body = JSON.parse(revision.body_json).merge("kind" => "practice_item")
    practice = ItemRevision.create!(item: revision.item, seq: 2, body_json: JSON.generate(body), file_sessions_json: "{}")
    ItemInstance.create!(item_revision: practice, seed: 1, display_json: JSON.generate(stem_it: "$3+4$"), answer_json: JSON.generate(SECRET), fingerprint: SecureRandom.hex(8))
    on(:harness, "/h/#{Validation::Harness.issue('irev', practice.id)}/item-render.html?n=1")
    assert_response :ok
    assert_select "main.practice .exercise-card button#check", text: "Controlla"
    assert_select "button#hint-button", text: "Mostra un aiuto (1 di 1)"
    assert_select "button#solution-button"
    refute_includes response.body, SECRET
  end

  test "the item's figure is served on the harness listener by its digest, as the web listener serves it to a student" do
    svg = '<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 10 10"><path d="M0 0L10 10"/></svg>'
    sha = Digest::SHA256.hexdigest(svg)
    Dir.mktmpdir do |dir|
      Rails.application.config.x.item_assets_dir = dir
      File.write(File.join(dir, "#{sha}.svg"), svg)
      on(:harness, "/assets/items/#{sha}.svg")
      assert_response :ok
      assert_equal "image/svg+xml", response.media_type
      assert_equal svg, response.body
      assert_match(/sandbox/, response.headers["Content-Security-Policy"])
      on(:harness, "/assets/items/#{'0' * 64}.svg")
      assert_response :not_found
    ensure
      Rails.application.config.x.item_assets_dir = nil
    end
  end

  # ---- the purge ----

  test "the purge knows the item shots: a file only old, unpinned, superseded renders name goes; the latest, a young or a pinned revision's stays" do
    old_revision = make_revision("shots-old", "math.number", instances: 1, component: "choice")
    ItemRevision.create!(item: old_revision.item, seq: 2, body_json: old_revision.body_json, file_sessions_json: "{}") # the newer revision of the item
    keep_latest = verdict!(revision: @revision, at: 60.days.ago, instances: 1)
    dropped = verdict!(revision: old_revision, at: 60.days.ago, instances: 1, tag: " of the old revision")
    shared_bytes = webp("shared")
    shared = LessonShots.put(shared_bytes)
    ItemRender.create!(item_revision: old_revision, status: "passed", harness_version: "x", result_json: "{}", created_at: 60.days.ago,
                       shots_json: JSON.generate([ { "instance" => 2, "sha256" => shared } ]))
    ItemRender.create!(item_revision: @revision, status: "passed", harness_version: "x", result_json: "{}", created_at: 1.day.ago,
                       shots_json: JSON.generate([ { "instance" => 3, "sha256" => shared } ]))
    kept_file = keep_latest.shots.first["sha256"]
    gone_file = dropped.shots.first["sha256"]
    dry = LessonShots.purge(dry_run: true)
    assert_equal [ gone_file ], dry[:deleted]
    assert File.exist?(LessonShots.path(gone_file)), "a dry run deletes nothing"
    result = LessonShots.purge
    assert_equal [ gone_file ], result[:deleted]
    refute File.exist?(LessonShots.path(gone_file))
    assert File.exist?(LessonShots.path(kept_file))
    assert File.exist?(LessonShots.path(shared)), "a file that a kept render also names stays"
    assert_equal 4, ItemRender.where(item_revision_id: [ @revision.id, old_revision.id ]).count, "the rows stay"
  end
end
