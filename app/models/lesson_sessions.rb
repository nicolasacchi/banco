# Who touched a lesson, by role (A5): the authors are the sessions that wrote a revision, the reviewers the
# sessions that filed a review. Same interface as ItemSessions, so Providers and the independence checks
# work on both. A session that authored any revision of the lesson cannot review it.
#
# Two questions, kept apart. WHO may review (a session identity: ids/conflicts) is every author of the lesson. WHICH
# MODELS a review must differ from (model_authors, D-374) is narrower: the authors of the revisions after the last
# approved base that was itself reviewed independently. Providers.refusal (the write-time refusal) and Providers.counting
# (the read-time counting) both ask model_authors, so the two cannot disagree.
class LessonSessions
  ROLES = %w[author reviewer].freeze

  def initialize(lesson)
    @lesson = lesson
  end

  def sessions(role) = AgentSession.where(id: ids(role.to_s)).order(:id).to_a

  def ids(role)
    case role
    when "author" then LessonRevision.where(lesson_id: @lesson.id).where.not(author_session_id: nil).distinct.pluck(:author_session_id)
    when "reviewer" then LessonReview.where(lesson_revision_id: revision_ids).distinct.pluck(:agent_session_id)
    else []
    end
  end

  # The roles other than +role+ that the session already holds on the lesson.
  def conflicts(session_id, role) = (ROLES - [ role.to_s ]).select { |r| ids(r).include?(session_id) }

  # The AgentSession rows whose models a review of +revision+ must differ from (D-374).
  #
  # The base of +revision+ is the newest revision of the lesson before it that the teacher approved (an approve_topic
  # decision pins it) and that has a review independent of what its own authors were then. With a base, only the
  # authors of the revisions after it, up to +revision+, count: the base was judged by an independent reviewer, so
  # whoever reads the change cannot share a model with the author of the change. Without a base: every author of the
  # lesson, as before.
  def model_authors(revision)
    base = base_of(revision)
    return AgentSession.where(id: ids("author")).order(:id).to_a unless base

    authors_between(base.seq, revision.seq)
  end

  # The newest approved revision of the lesson before +revision+, when it has a review on record that was independent
  # of the authors it faced (the delta since its own base, else every author up to it); nil otherwise (no fallback to an
  # older approval: the last approved revision is the one that was read).
  def base_of(revision)
    approved = approved_revisions.select { |r| r.seq < revision.seq }.max_by(&:seq)
    approved if approved && independently_reviewed?(approved)
  end

  private

  def independently_reviewed?(revision)
    base = base_of(revision)
    authors = base ? authors_between(base.seq, revision.seq) : authors_between(0, revision.seq)
    LessonReview.where(lesson_revision_id: revision.id).includes(:agent_session).any? { |review| Providers.independent?(review.agent_session, authors) }
  end

  def authors_between(after_seq, upto_seq)
    ids = LessonRevision.where(lesson_id: @lesson.id, seq: (after_seq + 1)..upto_seq).where.not(author_session_id: nil).distinct.pluck(:author_session_id)
    AgentSession.where(id: ids).order(:id).to_a
  end

  # The revisions of the lesson that an approve_topic decision pinned, whenever it was recorded.
  def approved_revisions
    @approved_revisions ||= begin
      ids = Course::Decisions.approved_lesson_revision_ids(@lesson)
      LessonRevision.where(lesson_id: @lesson.id, id: ids).to_a
    end
  end

  def revision_ids = LessonRevision.where(lesson_id: @lesson.id).pluck(:id)
end
