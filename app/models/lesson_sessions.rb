# Who touched a lesson, by role (A5): the authors are the sessions that wrote a revision, the reviewers the
# sessions that filed a review. Same interface as ItemSessions, so Providers and the independence checks
# work on both. A session that authored any revision of the lesson cannot review it.
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

  private

  def revision_ids = LessonRevision.where(lesson_id: @lesson.id).pluck(:id)
end
