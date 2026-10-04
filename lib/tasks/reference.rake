namespace :banco do
  namespace :reference do
    # The operator imports a short public-domain excerpt with its source:
    # KEY=verga-rosso-malpelo TITLE="..." SOURCE_URL=https://... FILE=path|-
    # An existing key with other text is refused (the table is append-only).
    desc "Import a reference text: KEY=key TITLE=title SOURCE_URL=url FILE=path|-"
    task import: :environment do
      key = ENV["KEY"].presence or abort "KEY=key is required"
      abort "KEY must be lowercase letters, digits and hyphens" unless key.match?(/\A[a-z0-9][a-z0-9-]*\z/)
      title = ENV["TITLE"].presence or abort "TITLE is required"
      source_url = ENV["SOURCE_URL"].presence or abort "SOURCE_URL is required (provenance)"
      file = ENV["FILE"].presence or abort "FILE=path|- is required"
      body = (file == "-" ? $stdin.binmode.read : File.binread(file)).force_encoding("UTF-8")
      abort "the text is not valid UTF-8" unless body.valid_encoding?
      sha = Digest::SHA256.hexdigest(body)
      existing = ReferenceText.find_by(key: key)
      if existing
        abort "#{key} exists with other text (sha256 #{existing.sha256}); use a new key" unless existing.sha256 == sha
        puts "#{key} already imported"
      else
        ReferenceText.create!(key: key, title: title, source_url: source_url, sha256: sha, body: body)
        puts "imported #{key} (#{body.split.size} words, sha256 #{sha})"
      end
    end
  end
end
