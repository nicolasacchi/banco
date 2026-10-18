# The findings of the lesson reviews as named things (D-313). A lesson review keeps its findings inline
# (lesson_reviews.findings_json) and the row is append-only, so the n-th finding of review R (from 1) is always
# the same finding: its id is "L<R>-<n>", which no item finding id (a bare number) can be. The author answers
# one with banco findings respond (LessonFindingResponse); the answer never disposes of it. What the teacher
# does about a lesson's findings is a decision on the lesson or the topic: send_back_lesson, or approve_topic
# (with a reason when the latest review has a blocker or major finding, Approval::TopicGate). Read-only.
module LessonFindings
  ID = /\AL([1-9]\d{0,17})-([1-9]\d?)\z/
  SEVERE = %w[blocker major].freeze

  # One finding: its id, the review, its position, the finding as the reviewer wrote it, and the author's
  # latest response (or nil).
  Entry = Data.define(:id, :review, :n, :finding, :response) do
    def severity = finding["severity"]
    def severe? = SEVERE.include?(severity)
    def card = finding["card"]
    def block = finding["block"]
    def section = finding["section"]
    def exercise = finding["exercise"]
  end

  module_function

  def id_for(review_id, n) = "L#{review_id}-#{n}"

  # The entry of an id such as "L12-3", or nil.
  def find(id)
    match = ID.match(id.to_s) or return nil
    review = LessonReview.find_by(id: match[1].to_i) or return nil
    n = match[2].to_i
    finding = review.findings[n - 1] or return nil
    fid = id_for(review.id, n)
    Entry.new(fid, review, n, finding, LessonFindingResponse.latest_for([ review.id ])[fid])
  end

  # The entries of the given reviews, review by review in id order, each with its latest response.
  def entries(reviews)
    reviews = reviews.to_a.sort_by(&:id)
    responses = LessonFindingResponse.latest_for(reviews.map(&:id))
    reviews.flat_map do |review|
      review.findings.each_with_index.map do |finding, i|
        fid = id_for(review.id, i + 1)
        Entry.new(fid, review, i + 1, finding, responses[fid])
      end
    end
  end

  # The findings of one review as the agent API shows them inside the review: the id first, the reviewer's
  # members, then the author's latest response.
  def api_findings(review, list = nil)
    (list || entries([ review ])).map { |e| { "id" => e.id }.merge(e.finding).merge("response" => e.response&.to_h).compact }
  end

  # What the teacher did about the lesson revision's findings: "sent_back" (send_back_lesson), "topic_approved"
  # (the topic's latest approval pins this lesson revision), or nil. Never set by a response.
  def decision(revision, sent_back: nil, approved: nil)
    sent_back = Course::Decisions.lesson_sent_back?(revision) if sent_back.nil?
    return "sent_back" if sent_back

    approved = approved_lesson_revision_ids([ revision.lesson.key ]) if approved.nil?
    approved.include?(revision.id) ? "topic_approved" : nil
  end

  # The lesson revision ids pinned by the latest approve_topic of each of +keys+.
  def approved_lesson_revision_ids(keys)
    latest = {}
    Decision.where(kind: "approve_topic").order(:id).each do |d|
      payload = JSON.parse(d.payload_json)
      latest[payload["topic"]] = payload["topic_revision_id"] if keys.include?(payload["topic"])
    end
    TopicRevision.where(id: latest.values).pluck(:lesson_revision_id).to_set
  end

  # The rows of the findings list (GET /api/v1/subjects/:subject/findings): the blocker and major findings of
  # every lesson review of the subject (all: minor ones too), oldest review first. keys: only these lessons.
  # current: the revision is the newest of its lesson; pinned: the latest topic revision pins it.
  def rows(subject, keys: nil, all: false)
    lessons = Lesson.where(subject: subject)
    lessons = lessons.where(key: keys) if keys
    lessons = lessons.includes(:revisions, :topic_revisions).to_a
    return [] if lessons.empty?

    revisions = lessons.flat_map(&:revisions).index_by(&:id)
    latest = lessons.to_h { |l| [ l.id, l.revisions.max_by(&:seq)&.id ] }
    pinned = lessons.filter_map { |l| l.topic_revisions.max_by(&:seq)&.lesson_revision_id }.to_set
    sent_back = Course::Decisions.lesson_send_backs(revisions.keys).keys.to_set
    approved = approved_lesson_revision_ids(lessons.map(&:key))
    keys_by_id = lessons.to_h { |l| [ l.id, l.key ] }
    reviews = LessonReview.where(lesson_revision_id: revisions.keys)
    entries(reviews).filter_map do |e|
      next unless all || e.severe?

      rev = revisions[e.review.lesson_revision_id]
      { finding_id: e.id, kind: "lesson", lesson: keys_by_id[rev.lesson_id], review_id: e.review.id, revision_id: rev.id, seq: rev.seq,
        current: latest[rev.lesson_id] == rev.id, pinned: pinned.include?(rev.id), severity: e.severity, card: e.card, block: e.block,
        section: e.section, exercise: e.exercise, quote: e.finding["quote"], problem_it: e.finding["problem_it"], fix_it: e.finding["fix_it"],
        decision: decision(rev, sent_back: sent_back.include?(rev.id), approved: approved), response: e.response&.to_h }.compact
    end
  end
end
