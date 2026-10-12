# The screenshots of a page validation (D-281, SPEC B7): WebP files stored by content, storage/page_shots/<sha256>.webp
# (BANCO_PAGE_SHOTS_DIR overrides, for tests; in production beside the databases, BANCO_DATA_DIR/page_shots, because the poster is what a
# student sees before the click and must survive a redeploy). The seed-0 1280 ready screenshot is the poster. The purge follows the rule of
# lesson shots (bin/purge-lesson-shots): files of validations of revisions nobody pins and that are not the latest.
module PageShots
  SHA = /\A[0-9a-f]{64}\z/
  KEEP_DAYS = 30

  module_function

  def dir
    path = ENV["BANCO_PAGE_SHOTS_DIR"].presence || (ENV["BANCO_DATA_DIR"].presence && File.join(ENV["BANCO_DATA_DIR"], "page_shots")) || Rails.root.join("storage/page_shots").to_s
    FileUtils.mkdir_p(path)
    path
  end

  def path(sha) = File.join(dir, "#{sha}.webp")

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

  # The poster of a revision: the seed-0 ready shot at 1280 of its latest passed validation, or nil.
  def poster_sha(revision)
    validation = revision.passed_validation or return nil
    validation.shots.find { |s| s["kind"] == "ready" && s["seed_index"] == 0 && s["width"] == 1280 }&.fetch("sha256")
  end

  # Which files the purge may delete (same rules as LessonShots.purge).
  def purge(days: KEEP_DAYS, now: Time.current, dry_run: false)
    pinned = pinned_revision_ids
    latest = PageRevision.where(id: PageRevision.group(:page_id).select("MAX(id)")).pluck(:id).to_set
    keep = Set.new
    drop = Set.new
    PageValidation.find_each do |validation|
      protected_row = pinned.include?(validation.page_revision_id) || latest.include?(validation.page_revision_id) || validation.created_at > now - days.days
      (protected_row ? keep : drop).merge(validation.shots.map { |s| s["sha256"] })
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

  # Page revisions that a lesson revision pinned by a topic embeds.
  def pinned_revision_ids
    ids = Set.new
    LessonRevision.where(id: TopicRevision.distinct.select(:lesson_revision_id)).find_each do |lr|
      Pages::Embeds.revision_ids(lr.body).each { |id| ids << id }
    end
    ids
  end
end
