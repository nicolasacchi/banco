# What a self-updating bot reads to stay current (D-330): the server's commit, the CLI's release build that ships in the
# image (dist/, bin/build-cli-dist), the digests of the two docs the bot lives by and the rows of the decisions index.
# Everything comes from files of the image. Nothing from a request names a file: the docs come from DOCS, the binaries
# from the names listed in dist/SHA256SUMS.
module Updates
  DOCS = { "bot" => "docs/bot.md", "api" => "docs/api.md" }.freeze
  DECISIONS = "docs/decisions.md".freeze
  SINCE = /\AD-(\d{3,})\z/
  # | D-NNN | date | title | status |: the title may hold a | inside backticks, the status never does.
  INDEX_ROW = /\A\| D-(\d{3,}) \| (\d{4}-\d\d-\d\d) \| (.+) \| ([^|]+?) \|\s*\z/
  # A line of SHA256SUMS (sha256sum's text or binary mode) that names one of bin/build-cli-dist's six binaries.
  SUMS_LINE = /\A(\h{64}) [ *](banco-(linux|darwin|windows)-(amd64|arm64)(?:\.exe)?)\z/

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
    rows = Rails.root.join(DECISIONS).each_line.filter_map do |line|
      m = INDEX_ROW.match(line.chomp) or next
      next if since && m[1].to_i <= since

      { number: "D-#{m[1]}", date: m[2], title: m[3], status: m[4].strip }
    end
    rows.sort_by { |row| row[:number].delete_prefix("D-").to_i }
  end

  # {name, sha256, text} of an allowlisted doc, or nil for any other name.
  def doc(name)
    path = DOCS[name.to_s] or return nil
    text = Rails.root.join(path).read
    { name: name.to_s, sha256: Digest::SHA256.hexdigest(text), text: text }
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
