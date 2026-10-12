# The bundle of a page revision (SPEC B2): the manifest, the files, and the hash that names them. bundle_sha256 is the
# sha256 of the canonical manifest JSON extended with each file's path, sha256 and size, so the shell's URL names
# everything that runs except the vendored libraries (pinned by version in `libs`, immutable by directory).
module Pages
  module Bundle
    FileInfo = Struct.new(:path, :sha256, :bytes, :media_type, :content, keyword_init: true)

    module_function

    def deep_sort(value)
      case value
      when Hash then value.sort.to_h { |k, v| [ k, deep_sort(v) ] }
      when Array then value.map { |v| deep_sort(v) }
      else value
      end
    end

    def canonical_manifest(manifest) = JSON.generate(deep_sort(manifest))

    # files: { "main.mjs" => bytes, ... } without page.json. Returns the FileInfo list sorted by path.
    def infos(files)
      files.sort.map do |path, content|
        FileInfo.new(path: path, sha256: Digest::SHA256.hexdigest(content), bytes: content.bytesize, media_type: Pages.media_type(path) || "application/octet-stream", content: content)
      end
    end

    def sha256(manifest, infos)
      listing = infos.map { |f| [ f.path, f.sha256, f.bytes ] }.sort
      Digest::SHA256.hexdigest(JSON.generate("manifest" => deep_sort(manifest), "files" => listing))
    end
  end
end
