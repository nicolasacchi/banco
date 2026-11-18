require "test_helper"
require "rake"
require "tmpdir"
require_relative "../support/multi_user"
require_relative "../support/student_export_world"
require_relative "../support/zip_reader"

# D-360: «Scarica i miei dati» (GET /privacy/data), the teacher's copy (GET /teacher/students/:key/data) and the console task
# banco:student:export. One zip of the student's own rows; the preview, a guest, the teacher on the student's route and another
# student are refused; the only thing written is the app event data_export.
class StudentDataExportTest < ActionDispatch::IntegrationTest
  include MultiUser
  include StudentExportWorld

  setup { build_export_world }

  def get_zip(headers, path = "/privacy/data")
    on(:web, path, headers: headers, remote_addr: EDGE)
    response.status == 200 ? ZipReader.read(response.body) : nil
  end

  def events = AppEvent.where(kind: "data_export").order(:id).map { |event| JSON.parse(event.payload_json).merge("student_id" => event.student_id) }

  # ---- the student -----------------------------------------------------------------------------------

  test "the student downloads one zip with his rows and none of another student's" do
    files = get_zip(OFFICIAL)
    assert_response :success
    assert_equal "application/zip", response.media_type
    assert_match(/\Aattachment; filename="banco-dati-student-\d{4}-\d{2}-\d{2}\.zip"/, response.headers["Content-Disposition"])
    assert_includes response.headers["Cache-Control"], "no-store"
    assert_includes files.keys, "README.txt"
    assert_includes files.keys, "riepilogo.html"
    assert_equal "student", JSON.parse(files.fetch("student.json")).sole["key"]
    assert_equal "42", JSON.parse(files.fetch("attempts.json")).sole["raw"]
    assert_equal [ "Non ho capito." ], JSON.parse(files.fetch("student_questions.json")).map { |q| q["text_it"] }
    files.each { |name, content| assert_not_includes content, OTHER_MARKER, name }
    files.each { |name, content| assert_not_includes content, TEACHER_ADDR, name }
  end

  test "nothing names the student: a key or an id in the address is ignored, he gets his own file" do
    files = get_zip(OFFICIAL, "/privacy/data?student=prova-2&key=prova-2&id=#{other.id}&student_id=#{other.id}")
    assert_equal "student", JSON.parse(files.fetch("student.json")).sole["key"]
    assert_equal [ { "by" => "student", "student_id" => student.id } ], events
  end

  test "the only thing a download writes is the app event, with who and when; the next one is another event" do
    tables = ActiveRecord::Base.connection.tables - %w[sqlite_sequence app_events]
    counts = -> { tables.to_h { |t| [ t, ActiveRecord::Base.connection.select_value("SELECT COUNT(*) FROM #{t}") ] } }
    before = counts.call
    started = Time.current
    get_zip(OFFICIAL)
    assert_equal before, counts.call
    assert_equal [ { "by" => "student", "student_id" => student.id } ], events
    assert_operator AppEvent.where(kind: "data_export").sole.created_at, :>=, started.change(usec: 0)
    first = get_zip(OFFICIAL)
    assert_equal 2, events.size
    assert_equal 1, JSON.parse(first.fetch("app_events.json")).count { |e| e["kind"] == "data_export" }, "the second file lists the first download"
  end

  test "a trial student gets his own file, with nothing of the official student" do
    files = get_zip(TRIAL)
    assert_response :success
    assert_equal "prova-1", JSON.parse(files.fetch("student.json")).sole["key"]
    assert_equal [], JSON.parse(files.fetch("attempts.json"))
    assert_equal [], JSON.parse(files.fetch("comments.json"))
    assert_not_includes files.values.join, "Non ho capito."
    assert_match(/banco-dati-prova-1-/, response.headers["Content-Disposition"])
  end

  test "another student reads only his own rows" do
    files = get_zip(TRIAL_B)
    assert_equal "prova-2", JSON.parse(files.fetch("student.json")).sole["key"]
    assert_includes files.fetch("attempts.json"), OTHER_MARKER
    assert_not_includes files.values.join, "\"42\""
  end

  # ---- who is refused ----------------------------------------------------------------------------------

  test "the teacher, a guest, nobody and an unconfigured login are refused on the student's route, and nothing is written" do
    [ TEACHER, GUEST, UNMAPPED, {} ].each do |who|
      assert_no_difference -> { AppEvent.count } do
        assert_nil get_zip(who)
      end
      assert_response :forbidden, who.inspect
      assert_not_includes response.media_type.to_s, "zip"
    end
  end

  test "the preview has no data route, and the route exists on the web listener only" do
    assert_nil get_zip(TEACHER, "/teacher/preview/privacy/data")
    assert_response :not_found
    assert_nil get_zip(OFFICIAL, "/teacher/preview/privacy/data")
    assert_response :not_found
    [ "/privacy/data", "/teacher/students/student/data" ].each do |path|
      %i[api harness view].each do |listener|
        on(listener, path, headers: TEACHER, remote_addr: EDGE)
        assert_response :not_found, "#{listener} #{path}"
      end
    end
    assert_equal 0, AppEvent.where(kind: "data_export").count
  end

  # ---- the page ------------------------------------------------------------------------------------------

  test "the privacy page offers the download to a student, in his language, and not to a teacher or a guest" do
    Diagnosis::Preferences.record(student, language: "it") # the world leaves him on English
    on(:web, "/privacy", headers: OFFICIAL, remote_addr: EDGE)
    assert_select "p#privacy-data-download", /Puoi scaricare i tuoi dati/
    assert_select "p#privacy-data-download a#data-download-link[href='/privacy/data']", "Scarica i miei dati"
    assert_select "section.info-section", 11
    Diagnosis::Preferences.record(student, language: "en")
    on(:web, "/privacy", headers: OFFICIAL, remote_addr: EDGE)
    assert_select "p#privacy-data-download", /You can download your data/
    assert_select "p#privacy-data-download a[href='/privacy/data']", "Download my data"
    [ TEACHER, GUEST ].each do |who|
      on(:web, "/privacy", headers: who, remote_addr: EDGE)
      assert_response :success
      assert_select "#privacy-data-download", 0
    end
  end

  # ---- the teacher ---------------------------------------------------------------------------------------

  test "the teacher downloads the same file of a student, and the app event says it was the teacher" do
    files = get_zip(TEACHER, "/teacher/students/student/data")
    assert_response :success
    assert_equal "application/zip", response.media_type
    assert_match(/filename="banco-dati-student-/, response.headers["Content-Disposition"])
    assert_equal Privacy::StudentExport::TABLES.map(&:path).sort, (files.keys.grep(/\.json\z/) - [ "preferences.json" ]).sort
    assert_equal "42", JSON.parse(files.fetch("attempts.json")).sole["raw"]
    files.each { |name, content| assert_not_includes content, OTHER_MARKER, name }
    assert_equal [ { "by" => "teacher", "login" => "nik", "student_id" => student.id } ], events

    trial = get_zip(TEACHER, "/teacher/students/prova-2/data")
    assert_equal "prova-2", JSON.parse(trial.fetch("student.json")).sole["key"]
    assert_equal({ "by" => "teacher", "login" => "nik", "student_id" => other.id }, events.last)
  end

  test "a guest and a student are refused on the teacher's route, an unknown key and the preview student are a 404" do
    [ GUEST, OFFICIAL, TRIAL, UNMAPPED, {} ].each do |who|
      assert_nil get_zip(who, "/teacher/students/student/data")
      assert_response :forbidden, who.inspect
    end
    Student.create!(key: "preview", kind: "preview")
    %w[nobody preview].each do |key|
      assert_nil get_zip(TEACHER, "/teacher/students/#{key}/data")
      assert_response :not_found, key
    end
    assert_equal 0, AppEvent.where(kind: "data_export").count
  end

  test "the students page links the download for the teacher and not for a guest" do
    on(:web, "/teacher/students", headers: TEACHER, remote_addr: EDGE)
    assert_select "section[data-student=student] a[href='/teacher/students/student/data']", "Scarica i dati"
    assert_select "section[data-student=prova-2] a[href='/teacher/students/prova-2/data']"
    on(:web, "/teacher/students", headers: GUEST, remote_addr: EDGE)
    assert_response :success
    assert_select "a[href$='/data']", 0
  end

  # ---- the console ---------------------------------------------------------------------------------------

  def export_task(env)
    saved = ENV.to_h.slice("STUDENT", "OUT")
    %w[STUDENT OUT].each { |k| ENV.delete(k) }
    env.each { |k, v| ENV[k] = v }
    Rake::Task["banco:student:export"].reenable
    capture_io { Rake::Task["banco:student:export"].invoke }.first
  ensure
    %w[STUDENT OUT].each { |k| saved.key?(k) ? ENV[k] = saved[k] : ENV.delete(k) }
  end

  test "the console task: without OUT a dry run with the counts that writes nothing, with OUT the zip and one console event" do
    Rake::Task.clear
    Rails.application.load_tasks
    assert_no_difference -> { AppEvent.count } do
      out = export_task("STUDENT" => "student")
      assert_match(/dry run, student student/, out)
      assert_match(/^\s+attempts\s+1$/, out)
      assert_match(/^\s+comment_events\s+4$/, out)
      Privacy::StudentExport.table_names.each { |table| assert_includes out, table }
    end

    Dir.mktmpdir do |dir|
      path = File.join(dir, "mine.zip")
      out = export_task("STUDENT" => "student", "OUT" => path)
      assert_includes out, "wrote #{path}"
      files = ZipReader.read(File.binread(path))
      assert_equal "42", JSON.parse(files.fetch("attempts.json")).sole["raw"]
      files.each { |name, content| assert_not_includes content, OTHER_MARKER, name }
      event = events.sole
      assert_equal [ "console", student.id ], event.values_at("by", "student_id")
      assert event["login"].present?

      assert_raises(SystemExit, "never overwrites") { export_task("STUDENT" => "student", "OUT" => path) }
      export_task("STUDENT" => "prova-2", "OUT" => dir)
      assert_equal 1, Dir.children(dir).grep(/\Abanco-dati-prova-2-/).size
    end
    assert_raises(SystemExit) { export_task("STUDENT" => "nobody") }
  end
end
