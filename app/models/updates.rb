# What a self-updating bot reads to stay current (D-330): the server's commit, the CLI's release build that ships in the
# image (dist/, bin/build-cli-dist), the digests of the two docs the bot lives by and the rows of the decisions index, and
# the whole text of one decision (D-333). Everything comes from files of the image. Nothing from a request names a file:
# the docs come from DOCS, the binaries from the names listed in dist/SHA256SUMS, a decision from its number.
module Updates
  DOCS = { "bot" => "docs/bot.md", "api" => "docs/api.md" }.freeze
  DECISIONS = "docs/decisions.md".freeze
  SINCE = /\AD-(\d{3,})\z/
  # | D-NNN | date | title | status |: the title may hold a | inside backticks, the status never does.
  INDEX_ROW = /\A\| D-(\d{3,}) \| (\d{4}-\d\d-\d\d) \| (.+) \| ([^|]+?) \|\s*\z/
  # A decision's section: `## D-NNN · date · title`, up to the next line that starts another `## D-` section or the end.
  HEADING = /\A## D-(\d{3,}) · (\d{4}-\d\d-\d\d) · (.+)\z/
  SECTION_START = /\A## D-\d/
  # What names a decision in a request: D-332 or 332.
  DECISION_NUMBER = /\A(?:D-)?(\d{1,6})\z/
  # A line of SHA256SUMS (sha256sum's text or binary mode) that names one of bin/build-cli-dist's six binaries.
  SUMS_LINE = /\A(\h{64}) [ *](banco-(linux|darwin|windows)-(amd64|arm64)(?:\.exe)?)\z/

  # Guards the memoized parse of the decisions file and the docs (see cached).
  CACHE_LOCK = Mutex.new

  # A file of the release build: name (the allowlisted file name), os, arch, sha256, size.
  CliFile = Data.define(:name, :os, :arch, :sha256, :size)

  # The directory of the release build; tests point it elsewhere. nil: Rails.root/dist.
  mattr_accessor :dist_dir

  module_function

  def dist = Pathname(dist_dir || Rails.root.join("dist"))

  # The answer of GET /api/v1/updates. since: nil or a number (the changes after D-<since>).
  def summary(since: nil)
    build = build_info
    {
      server: { commit: Grading.git_sha, built_at: build["built_at"] },
      contract_digest: Contract.digest,
      cli: { version: build["version"], files: cli_files.map(&:to_h) },
      docs: DOCS.keys.map { |name| { name: name, sha256: doc(name).fetch(:sha256) } },
      changes: changes(since: since)
    }
  end

  # The number of a D-NNN, or nil when the text is not one.
  def since_number(text) = text.to_s[SINCE, 1]&.to_i

  # The rows of the decisions index after D-<since> (all when nil), oldest first: {number, date, title, status}.
  def changes(since: nil)
    rows = decisions_file.fetch(:rows)
    since ? rows.reject { |row| row[:number].delete_prefix("D-").to_i <= since } : rows.dup
  end

  # {number, date, title, status, text} of one decision (D-332 or 332): the index row and the whole markdown section from
  # its `## D-NNN · …` heading to the next `## D-` heading or the end of the file; nil when there is no such section.
  def decision(number)
    wanted = number.to_s[DECISION_NUMBER, 1]&.to_i or return nil
    file = decisions_file
    section = file.fetch(:sections)[wanted] or return nil
    row = file.fetch(:rows_by_number)[wanted]
    { number: section[:number], date: row&.fetch(:date) || section[:date], title: row&.fetch(:title) || section[:title],
      status: row&.fetch(:status), text: section[:text] }
  end

  # {number, date, title, status} of a line of the decisions index, or nil for any other line.
  def index_row(line)
    m = INDEX_ROW.match(line.chomp) or return nil

    { number: "D-#{m[1]}", date: m[2], title: m[3], status: m[4].strip }
  end

  # {name, sha256, text} of an allowlisted doc, or nil for any other name.
  def doc(name)
    path = DOCS[name.to_s] or return nil
    file = cached(Rails.root.join(path)) do |text|
      { name: name.to_s, sha256: Digest::SHA256.hexdigest(text), text: text }
    end
    file.dup
  end

  # What the decisions file holds, parsed once per version of the file: rows (the index, oldest first), rows_by_number
  # (the first index row of each number) and sections (the first `## D-NNN` section of each number).
  def decisions_file
    cached(Rails.root.join(DECISIONS)) { |text| parse_decisions(text) }
  end

  def parse_decisions(text)
    lines = text.lines
    listed = lines.filter_map { |line| index_row(line) }
    starts = lines.each_index.select { |i| SECTION_START.match?(lines[i]) }
    sections = {}
    starts.each_with_index do |start, k|
      heading = HEADING.match(lines[start].chomp) or next
      sections[heading[1].to_i] ||= { number: "D-#{heading[1]}", date: heading[2], title: heading[3],
                                      text: lines[start...(starts[k + 1] || lines.size)].join.rstrip }.freeze
    end
    rows_by_number = {}
    listed.each { |row| rows_by_number[row[:number].delete_prefix("D-").to_i] ||= row }
    rows = listed.sort_by { |row| row[:number].delete_prefix("D-").to_i }
    { rows: rows.each(&:freeze).freeze, rows_by_number: rows_by_number.freeze, sections: sections.freeze }.freeze
  end

  # The value computed from a file's text by the block, kept until the file's mtime or size changes: a request costs a
  # hash lookup, not a read and a parse. The block runs under the lock, so concurrent requests parse once.
  def cached(path)
    stat = path.stat
    key = [ stat.mtime, stat.size ]
    CACHE_LOCK.synchronize do
      hit = (@cache ||= {})[path.to_s]
      return hit[:value] if hit && hit[:key] == key

      value = yield(path.read).freeze
      @cache[path.to_s] = { key: key, value: value }
      value
    end
  end

  # The binaries of the release build: the lines of dist/SHA256SUMS whose file is a regular file (not a symlink) right
  # inside dist/; empty without dist/ (development).
  def cli_files
    sums = dist.join("SHA256SUMS")
    return [] unless sums.file?

    root = dist.realpath
    sums.each_line.filter_map do |line|
      m = SUMS_LINE.match(line.chomp) or next
      path = dist.join(m[2])
      next unless regular_inside?(path, root)

      CliFile.new(name: m[2], os: m[3], arch: m[4], sha256: m[1].downcase, size: path.size)
    end
  end

  # A regular file, not a symlink, whose real path is directly inside root.
  def regular_inside?(path, root)
    path.lstat.file? && path.realpath.dirname == root
  rescue SystemCallError
    false
  end

  # [file, path] of a listed binary, or nil. The path is built from the listed name only.
  def cli_file(name)
    file = cli_files.find { |f| f.name == name.to_s } or return nil
    path = dist.join(file.name)
    regular_inside?(path, dist.realpath) ? [ file, path ] : nil
  end

  # dist/build.json written by bin/build-cli-dist: {version, built_at}; {} when absent or unreadable.
  def build_info
    path = dist.join("build.json")
    return {} unless path.file?

    info = JSON.parse(path.read)
    info.is_a?(Hash) ? info.slice("version", "built_at") : {}
  rescue JSON::ParserError
    {}
  end
end
