# Who touched a free page, by role (D-290, SPEC B8): the authors are the sessions that wrote a revision, the reviewers the
# sessions that filed a review. Same interface as LessonSessions, so Providers and the independence checks work on both.
class PageSessions
  ROLES = %w[author reviewer].freeze

  def initialize(page)
    @page = page
  end

  def sessions(role) = AgentSession.where(id: ids(role.to_s)).order(:id).to_a

  def ids(role)
    case role
    when "author" then PageRevision.where(page_id: @page.id).where.not(author_session_id: nil).distinct.pluck(:author_session_id)
    when "reviewer" then PageReview.where(page_revision_id: revision_ids).distinct.pluck(:agent_session_id)
    else []
    end
  end

  def conflicts(session_id, role) = (ROLES - [ role.to_s ]).select { |r| ids(r).include?(session_id) }

  private

  def revision_ids = PageRevision.where(page_id: @page.id).pluck(:id)
end
