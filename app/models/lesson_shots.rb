# The screenshots of the lesson render check (D-249, A12): WebP files stored by content, so an unchanged card in a
# new revision costs nothing. storage/lesson_shots/<sha256>.webp (BANCO_LESSON_SHOTS_DIR overrides, for tests).
# bin/purge-lesson-shots deletes the files of renders that nobody needs any more; the lesson_renders rows stay.
module LessonShots
  KEEP_DAYS = 30
  SHA = /\A[0-9a-f]{64}\z/

  module_function

  def dir
    path = ENV["BANCO_LESSON_SHOTS_DIR"].presence || Rails.root.join("storage/lesson_shots").to_s
    FileUtils.mkdir_p(path)
    path
  end

  def path(sha) = File.join(dir, "#{sha}.webp")

  # Stores the bytes (once) and returns the sha256 they are named by.
  def put(bytes)
    sha = Digest::SHA256.hexdigest(bytes)
    file = path(sha)
    return sha if File.exist?(file)

    tmp = "#{file}.#{Process.pid}.#{SecureRandom.hex(4)}.tmp"
    File.binwrite(tmp, bytes)
    File.rename(tmp, file)
    sha
  end

  # The bytes, or nil when the name is not a sha256 or the file was purged.
  def read(sha)
    return nil unless sha.to_s.match?(SHA)

    File.binread(path(sha))
  rescue Errno::ENOENT
    nil
  end

  def exist?(sha) = sha.to_s.match?(SHA) && File.exist?(path(sha))

  # Which files the purge may delete: those named only by renders of a revision that no topic revision pins, that is
  # not the latest of its lesson, and that are older than +days+. A file also named by a render that is kept stays.
  # Returns { deleted: [sha...], kept: n, bytes: n }; dry_run deletes nothing.
  def purge(days: KEEP_DAYS, now: Time.current, dry_run: false)
    pinned = TopicRevision.distinct.pluck(:lesson_revision_id).to_set
    latest = LessonRevision.where(id: LessonRevision.group(:lesson_id).select("MAX(id)")).pluck(:id).to_set
    keep = Set.new
    drop = Set.new
    LessonRender.find_each do |render|
      protected_row = pinned.include?(render.lesson_revision_id) || latest.include?(render.lesson_revision_id) || render.created_at > now - days.days
      (protected_row ? keep : drop).merge(render.shots.map { |s| s["sha256"] })
    end
    deleted = []
    bytes = 0
    (drop - keep).each do |sha|
      file = path(sha)
      next unless File.exist?(file)

      bytes += File.size(file)
      File.delete(file) unless dry_run
      deleted << sha
    end
    { deleted: deleted, kept: keep.size, bytes: bytes, dry_run: dry_run }
  end
end
