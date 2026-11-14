# The CLI contract (contract/commands.json), the one file shared by the Rails
# API and the Go CLI (embedded there with go:embed).
module Contract
  PATH = Rails.root.join("contract/commands.json")

  module_function

  def raw
    File.read(PATH)
  end

  # The sha256 of the file, kept until the file changes (it is read and hashed once, not on every request).
  def digest
    stamp = File.stat(PATH).then { |s| [ s.mtime, s.size ] }
    return @digest if @digest && @stamp == stamp

    @stamp = stamp
    @digest = Digest::SHA256.file(PATH).hexdigest
  end

  def parsed
    JSON.parse(raw)
  end
end
