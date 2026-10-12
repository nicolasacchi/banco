# The kit (B6): lib/pages_kit/MAJOR.MINOR/, ours, in git. Released directories never change: a fix is a new directory.
# lib/pages_kit/LOCK lists the sha256 of every file of every released directory; a test fails when a released file
# differs or disappears, or when a directory is not listed (bin/pages-kit-lock writes the lock for a new one).
module Pages
  module Kit
    ROOT = Rails.root.join("lib/pages_kit")
    LOCK = ROOT.join("LOCK")
    VERSION = /\A\d+\.\d+\z/
    FILE = %r{\A[A-Za-z0-9_.-]+(?:/[A-Za-z0-9_.-]+)?\z}
    DEFAULT = "1.0"

    module_function

    def versions = Dir.children(ROOT).select { |d| d.match?(VERSION) && File.directory?(ROOT.join(d)) }.sort_by { |v| v.split(".").map(&:to_i) }

    def released?(version) = version.to_s.match?(VERSION) && versions.include?(version.to_s)

    # The files of a kit directory, relative ("bridge.mjs", "fonts/x.woff2"), sorted: the lookup list (never a path join).
    def files(version)
      return [] unless released?(version)

      dir = ROOT.join(version.to_s)
      Dir.glob("**/*", base: dir.to_s).select { |f| File.file?(dir.join(f)) }.sort
    end

    # The bytes of a file by lookup in the listing.
    def read(version, file)
      return nil unless file.to_s.match?(FILE) && files(version).include?(file)

      File.binread(ROOT.join(version.to_s, file))
    end

    def lock_lines
      versions.flat_map do |v|
        files(v).map { |f| "#{Digest::SHA256.file(ROOT.join(v, f)).hexdigest}  #{v}/#{f}" }
      end
    end

    # What differs between the lock and the directories: [] when every released file is as locked.
    def lock_problems
      locked = File.exist?(LOCK) ? File.readlines(LOCK, chomp: true).reject(&:blank?) : []
      current = lock_lines
      (locked - current).map { |l| "changed or gone: #{l.split('  ', 2).last}" } +
        (current - locked).map { |l| "not in the lock: #{l.split('  ', 2).last}" }
    end

    def write_lock! = File.write(LOCK, "#{lock_lines.join("\n")}\n")
  end
end
