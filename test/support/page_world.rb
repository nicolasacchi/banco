# Invented free pages for the tests (D-289): the folders of test/fixtures/pages, stored as page revisions without the API.
module PageWorld
  FIXTURES = Rails.root.join("test/fixtures/pages")

  def page_subject! = Subject.find_by(key: "math") || Subject.create!(key: "math", name_it: "Matematica", position: 1)

  # { "page.json" => bytes, "main.mjs" => bytes, ... } of a fixture folder; the block may change the hash.
  def page_files(name = "math.pages-sample")
    dir = FIXTURES.join(name)
    files = Dir.glob("**/*", base: dir.to_s).select { |f| File.file?(dir.join(f)) }.to_h { |f| [ f, File.binread(dir.join(f)) ] }
    yield files if block_given?
    files
  end

  def page_manifest(files) = JSON.parse(files.fetch("page.json"))

  def page_author! = AgentSession.create!(label: "t", role: "author", agent: "tester", model: "claude-sonnet-5-5")
  def page_reviewer! = AgentSession.create!(label: "t", role: "reviewer", agent: "tester", model: "gpt-5")

  # Stores a revision as the API does (Pages::Store, rows) after the static checks; raises when the checks refuse it.
  def store_page!(files = page_files, key: nil, scan: true)
    manifest = JSON.parse(files.fetch("page.json"))
    key ||= manifest.fetch("key")
    outcome = Validation::PageChecks.call(files, key: key, subject: key.split(".", 2).first)
    raise "page checks refused: #{outcome.findings.errors.map(&:code).inspect} #{outcome.findings.errors.first&.message}" if scan && outcome.findings.any_error?

    sha = outcome.bundle_sha256 || Pages::Bundle.sha256(manifest, outcome.infos)
    outcome.infos.each { |f| Pages::Store.put(f.content) }
    page = Page.find_or_create_by!(key: key) { |p| p.subject = page_subject! }
    seq = (page.latest_revision&.seq || 0) + 1
    rev = PageRevision.create!(page: page, seq: seq, base_revision_id: page.latest_revision&.id, manifest_json: JSON.generate(manifest), bundle_sha256: sha, rules_version: Validation::Rules.version.to_s,
                               warnings_json: "[]", author_session: page_author!)
    outcome.infos.each { |f| PageFile.create!(page_revision: rev, path: f.path, sha256: f.sha256, bytes: f.bytes, media_type: f.media_type) }
    rev
  end

  def pass_page!(revision, kit: Pages::Kit::DEFAULT, shots: [])
    PageValidation.create!(page_revision: revision, kit_version: kit, status: "passed", harness_version: "test", chrome_version: "test", attempt: 1,
                           result_json: JSON.generate("errors" => [], "warnings" => []), shots_json: JSON.generate(shots))
  end
end
