# The CLI contract (contract/commands.json), the one file shared by the Rails
# API and the Go CLI (embedded there with go:embed).
module Contract
  PATH = Rails.root.join("contract/commands.json")

  module_function

  def raw
    File.read(PATH)
  end

  def digest
    Digest::SHA256.file(PATH).hexdigest
  end

  def parsed
    JSON.parse(raw)
  end
end
