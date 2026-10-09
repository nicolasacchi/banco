require "digest"

# Versioned authoring briefs for the content agents (C-03). They live in git
# (briefs/<name>.md, front matter with name and version) and are served by
# GET /api/v1/briefs/:name. Every revision records the brief_sha256 it was built under.
class Brief
  DIR = Rails.root.join("briefs")
  NAME = /\A[a-z][a-z0-9-]*\z/
  FRONT_MATTER = /\A---\n(.*?)\n---\n/m

  attr_reader :name, :version, :sha256, :body

  def self.names
    Dir[DIR.join("*.md")].map { |f| File.basename(f, ".md") }.sort
  end

  # nil when there is no such brief; the name is checked before any path is built.
  def self.find(name)
    return nil unless name.to_s.match?(NAME) && names.include?(name)

    new(name, File.binread(DIR.join("#{name}.md")).force_encoding("UTF-8"))
  end

  def initialize(name, text)
    @name = name
    @sha256 = Digest::SHA256.hexdigest(text)
    meta = text[FRONT_MATTER, 1] or raise ArgumentError, "brief #{name} has no front matter"
    fields = meta.lines.to_h { |l| l.chomp.split(": ", 2) }
    raise ArgumentError, "brief #{name}: name mismatch" unless fields["name"] == name

    @version = Integer(fields.fetch("version"))
    @body = text.sub(FRONT_MATTER, "")
  end

  def as_json(*)
    { name: name, version: version, sha256: sha256, body: body }
  end
end
