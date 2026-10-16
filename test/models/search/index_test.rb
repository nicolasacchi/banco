require "test_helper"
require "rake"
require_relative "../../support/search_world"

# The index is derived and disposable: two builds give the same rows, a lost file is rebuilt to the same index, a change writes only
# what changed, a removed thing leaves the index.
class SearchIndexTest < ActiveSupport::TestCase
  include SearchWorld

  setup do
    build_search_world
    add_answers!(@official, ANSWER_WORD, refused: REFUSED_WORD)
  end

  def rows = Search::Record.connection.select_rows("SELECT doc_key, grp, kind, audience, revision_id, status, title, body, anchor, digest FROM search_documents ORDER BY doc_key")

  def fts_rows = Search::Record.connection.select_rows("SELECT rowid, title, body, stems FROM search_fts ORDER BY rowid")

  test "a build from the fixtures fills every group" do
    counts = rebuild_search!
    assert_equal Search::Builders::GROUPS.sort, counts.keys.sort
    assert_operator Search::Index.count, :>, 20
    kinds = Search::Record.connection.select_values("SELECT DISTINCT kind FROM search_documents")
    assert_equal %w[course glossary_term item lesson_card practice_item reference_article skill student_answer syllabus_line topic].sort - %w[glossary_term], (kinds - %w[item_instance]).sort
    assert_equal Search::Index.count, Search::Record.connection.select_value("SELECT COUNT(*) FROM search_fts")
    assert_equal Search::Index.count, Search::Record.connection.select_value("SELECT COUNT(*) FROM search_trigram")
  end

  test "two builds leave the same rows, and the second writes nothing" do
    rebuild_search!
    before = rows
    ids = Search::Record.connection.select_rows("SELECT id, doc_key FROM search_documents ORDER BY id")
    fts = fts_rows
    again = rebuild_search!
    assert_equal before, rows
    assert_equal ids, Search::Record.connection.select_rows("SELECT id, doc_key FROM search_documents ORDER BY id")
    assert_equal fts, fts_rows
    assert(again.values.all? { |c| c[:added].zero? && c[:changed].zero? && c[:removed].zero? }, again.inspect)
  end

  test "deleting the file and rebuilding gives the same index" do
    rebuild_search!
    before = rows
    Search::Schema.reset!
    assert_equal 0, Search::Index.count
    rebuild_search!
    assert_equal before, rows
  end

  test "a change writes the changed unit alone and a removed unit leaves the index" do
    rebuild_search!
    ReferenceText.create!(key: "nuovo-test", title: "Nuovo", source_url: "https://example.org/n", sha256: "6" * 64, body: "Un testo nuovo.")
    counts = Search::Indexer.reindex(%w[references])
    assert_equal 1, counts["references"][:added]
    assert_equal 1, Search::Record.connection.select_value("SELECT COUNT(*) FROM search_documents WHERE key = 'nuovo-test'")
    assert_equal 1, Search::Record.connection.select_value("SELECT COUNT(*) FROM search_fts WHERE search_fts MATCH 'nuovo'")
    # a unit that is no longer built is removed from every table
    doc = Search::Doc.build(kind: "reference_article", key: "gone", title: "g", body: "zzgonezz", status: "imported")
    Search::Index.replace_group("references", Search::Builders::References.call + [ doc ])
    assert_equal 1, Search::Record.connection.select_value("SELECT COUNT(*) FROM search_fts WHERE search_fts MATCH 'zzgonezz'")
    counts = Search::Index.replace_group("references", Search::Builders::References.call)
    assert_equal 1, counts[:removed]
    assert_equal 0, Search::Record.connection.select_value("SELECT COUNT(*) FROM search_fts WHERE search_fts MATCH 'zzgonezz'")
    assert_equal 0, Search::Record.connection.select_value("SELECT COUNT(*) FROM search_trigram WHERE search_trigram MATCH 'zzg'")
  end

  test "a revision that changes text is a changed row, not a new one" do
    rebuild_search!
    doc = Search::Doc.build(kind: "syllabus_line", key: "k:1", title: "t", body: "zzprimazz versione", anchor: 1)
    Search::Index.replace_group("syllabus", [ doc ])
    id = Search::Record.connection.select_value("SELECT id FROM search_documents WHERE key = 'k:1'")
    changed = Search::Doc.build(kind: "syllabus_line", key: "k:1", title: "t", body: "zzsecondazz versione", anchor: 1)
    assert_equal 1, Search::Index.replace_group("syllabus", [ changed ])[:changed]
    assert_equal id, Search::Record.connection.select_value("SELECT id FROM search_documents WHERE key = 'k:1'")
    assert_equal 0, Search::Record.connection.select_value("SELECT COUNT(*) FROM search_fts WHERE search_fts MATCH 'zzprimazz'")
    assert_equal 1, Search::Record.connection.select_value("SELECT COUNT(*) FROM search_fts WHERE search_fts MATCH 'zzsecondazz'")
  end

  test "a schema of another version is dropped and made again" do
    rebuild_search!
    Search::Record.connection.execute("PRAGMA user_version = 0")
    Search::Schema.ensure!
    assert_equal 0, Search::Index.count
    assert_equal Search::Schema::VERSION, Search::Record.connection.select_value("PRAGMA user_version").to_i
  end

  test "the primary database is untouched: no table of the index is in it" do
    names = ActiveRecord::Base.connection.select_values("SELECT name FROM sqlite_master WHERE type = 'table'")
    assert_empty names.grep(/\Asearch_/)
    assert_not_equal ActiveRecord::Base.connection_pool.db_config.database, Search::Record.connection_pool.db_config.database
  end

  test "the nightly task is in the recurring schedule and the rake task rebuilds" do
    schedule = YAML.safe_load_file(Rails.root.join("config/recurring.yml"))
    assert_equal "SearchIndexJob", schedule.dig("production", "search_rebuild", "class")
    Rails.application.load_tasks unless Rake::Task.task_defined?("banco:search:rebuild")
    Rake::Task["banco:search:rebuild"].reenable
    out, = capture_io { Rake::Task["banco:search:rebuild"].invoke }
    assert_match(/documents in/, out)
    assert_equal Search::Index.count, out[/(\d+) documents/, 1].to_i
  end
end
