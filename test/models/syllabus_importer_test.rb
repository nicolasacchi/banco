require "test_helper"

class SyllabusImporterTest < ActiveSupport::TestCase
  def fixture(name) = Rails.root.join("test/fixtures/syllabus", name).read

  test "imports every physical line and verifies the sha256" do
    text = fixture("transcribed.md")
    Syllabus::Importer.import("synthetic-a", text)
    source = SyllabusSource.find_by!(key: "synthetic-a")
    assert_equal text.count("\n"), source.line_count
    assert_equal (1..source.line_count).to_a, source.lines.pluck(:number)
    assert_equal text, source.reconstructed_text
    stats = Syllabus::Importer.verify("synthetic-a", text)
    assert_equal [ source.line_count, 1, source.line_count, Digest::SHA256.hexdigest(text) ],
                 [ stats.count, stats.min, stats.max, stats.sha256 ]
  end

  test "tags transcriber lines and content lines" do
    Syllabus::Importer.import("synthetic-a", fixture("transcribed.md"))
    origin = SyllabusSource.find_by!(key: "synthetic-a").lines.index_by(&:number).transform_values(&:origin)
    assert_equal "transcript", origin[1], "title of the preamble"
    assert_equal "transcript", origin[5], "preamble divider"
    assert_equal "transcript", origin[7], "level-2 heading"
    assert_equal "transcript", origin[9], "italic subtitle"
    assert_equal "transcript", origin[11], "page marker"
    assert_equal "transcript", origin[12], "blank line"
    assert_equal "pdf", origin[13], "level-3 heading belongs to the document"
    assert_equal "pdf", origin[15]
    assert_equal "transcript", origin[22], "figure placeholder"
    assert_equal "transcript", origin[26], "page marker"
    assert_equal "pdf", origin[28]
    refute SyllabusLine.find_by!(number: 7).citable?
    assert SyllabusLine.find_by!(number: 15).citable?
  end

  test "a file without a transcriber preamble has only content and blank lines" do
    Syllabus::Importer.import("synthetic-b", fixture("marked.md"))
    lines = SyllabusSource.find_by!(key: "synthetic-b").lines.index_by(&:number)
    assert_equal "transcript", lines[3].origin
    assert_equal "pdf", lines[1].origin
    assert_equal [ nil, nil, nil, nil, nil, "★", "☆", "★☆" ], (1..8).map { |n| lines[n].marker }
  end

  test "sub-line addresses cover table cells and bullets" do
    Syllabus::Importer.import("synthetic-a", fixture("transcribed.md"))
    lines = SyllabusSource.find_by!(key: "synthetic-a").lines.index_by(&:number)
    assert_equal({ "A1" => "Competenza uno", "A2" => "Abilità uno", "A3" => "Conoscenza uno" }, lines[20].parts)
    assert_equal [ "Elenco:", "alfa", "beta", "gamma" ], lines[24].parts.values
    assert_empty lines[15].parts
  end

  test "importing the same text again is a no-op and a different text is refused" do
    text = fixture("marked.md")
    Syllabus::Importer.import("synthetic-b", text)
    assert_no_difference -> { SyllabusLine.count } do
      Syllabus::Importer.import("synthetic-b", text)
    end
    assert_raises(Syllabus::Error) { Syllabus::Importer.import("synthetic-b", text + "extra\n") }
  end

  test "verify fails on a different file and on a missing source" do
    Syllabus::Importer.import("synthetic-b", fixture("marked.md"))
    assert_raises(Syllabus::Error) { Syllabus::Importer.verify("synthetic-b", fixture("transcribed.md")) }
    assert_raises(Syllabus::Error) { Syllabus::Importer.verify("absent", fixture("marked.md")) }
  end

  test "a text without a final newline or with invalid UTF-8 is refused" do
    assert_raises(Syllabus::Error) { Syllabus::Importer.import("bad", "no newline") }
    assert_raises(Syllabus::Error) { Syllabus::Importer.import("bad", "ok\n\xFF\n".b) }
    assert_raises(Syllabus::Error) { Syllabus::Importer.import("bad", "") }
    assert_equal 0, SyllabusSource.count
  end

  test "an import that fails midway leaves nothing behind" do
    SyllabusLine.stub(:insert_all!, ->(*) { raise "boom" }) do
      assert_raises(RuntimeError) { Syllabus::Importer.import("synthetic-b", fixture("marked.md")) }
    end
    assert_equal 0, SyllabusSource.count
  end

  test "the rake tasks import and verify through a file" do
    require "rake"
    Rails.application.load_tasks unless Rake::Task.task_defined?("banco:syllabus:import")
    path = Rails.root.join("test/fixtures/syllabus/marked.md").to_s
    with_env("SOURCE" => "synthetic-b", "FILE" => path) do
      out, = capture_io { Rake::Task["banco:syllabus:import"].execute }
      assert_match(/imported synthetic-b count=8 min=1 max=8 sha256=\h{64}/, out)
      out, = capture_io { Rake::Task["banco:syllabus:verify"].execute }
      assert_match(/count=8 min=1 max=8 sha256=\h{64} ok\n\z/, out)
    end
  end

  test "the real programmes verify when their files are present locally" do
    {
      "seconda-2025-26" => "prep/programma-seconda.md",
      "prima-2025-26" => "prep/programma-prima.md"
    }.each do |key, relative|
      path = Rails.root.join(relative)
      skip "#{relative} is not in this checkout (public CI); run banco:syllabus:verify locally" unless path.exist?
      text = path.read
      Syllabus::Importer.import(key, text)
      assert_equal Digest::SHA256.hexdigest(text), Syllabus::Importer.verify(key, text).sha256
    end
  end
end
