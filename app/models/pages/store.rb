# The bytes of page files, by content: storage/pages/<sha256>, written once, never rewritten (B9).
# These bytes are the source of truth of a page (the rows only name them), so in production they live beside the databases
# (BANCO_DATA_DIR/pages, the bind-mounted volume), not in the container's ephemeral storage/. BANCO_PAGES_DIR overrides (tests).
module Pages
  module Store
    SHA = /\A[0-9a-f]{64}\z/

    module_function

    def dir
      path = ENV["BANCO_PAGES_DIR"].presence || (ENV["BANCO_DATA_DIR"].presence && File.join(ENV["BANCO_DATA_DIR"], "pages")) || Rails.root.join("storage/pages").to_s
      FileUtils.mkdir_p(path)
      path
    end

    def path(sha) = File.join(dir, sha)

    def put(bytes)
      sha = Digest::SHA256.hexdigest(bytes)
      file = path(sha)
      return sha if File.exist?(file)

      tmp = "#{file}.#{Process.pid}.#{SecureRandom.hex(4)}.tmp"
      File.binwrite(tmp, bytes)
      File.rename(tmp, file)
      sha
    end

    def read(sha)
      return nil unless sha.to_s.match?(SHA)

      File.binread(path(sha))
    rescue Errno::ENOENT
      nil
    end

    def exist?(sha) = sha.to_s.match?(SHA) && File.exist?(path(sha))
  end
end
