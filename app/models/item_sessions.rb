# Who touched an item, by role (A-04). Reads the file_sessions of every revision,
# the reviews and the blind solves. The rule is that the sessions of the four roles
# are disjoint on one item (E-SESSION-NOT-INDEPENDENT); it guards against mistakes.
class ItemSessions
  AUTHORED = %w[item.json generator.mjs].freeze

  # The session book of an item or of a lesson (Phase 1b).
  def self.for(thing) = thing.is_a?(Lesson) ? LessonSessions.new(thing) : new(thing)

  def initialize(item)
    @item = item
  end

  # AgentSession rows that hold +role+ on the item: author, verifier, reviewer, solver.
  def sessions(role)
    AgentSession.where(id: ids(role.to_s)).order(:id).to_a
  end

  def ids(role)
    case role
    when "author" then from_files { |name| name == "item.json" || name == "generator.mjs" || name.start_with?("assets/") }
    when "verifier" then from_files { |name| name == "verify.mjs" }
    when "reviewer" then ItemReview.where(item_revision_id: revision_ids).distinct.pluck(:agent_session_id)
    when "solver" then BlindSolve.where(item_revision_id: revision_ids).distinct.pluck(:agent_session_id)
    else []
    end
  end

  # The roles other than +role+ that the session already holds on the item.
  def conflicts(session_id, role)
    (%w[author verifier reviewer solver] - [ role.to_s ]).select { |r| ids(r).include?(session_id) }
  end

  private

  def revision_ids = @revision_ids ||= ItemRevision.where(item_id: @item.id).pluck(:id)

  def from_files
    ItemRevision.where(item_id: @item.id).flat_map do |rev|
      map = rev.file_sessions
      ids = map.select { |name, _| yield(name) }.values
      ids << rev.author_session_id if rev.author_session_id && yield("item.json")
      ids
    end.compact.map(&:to_i).uniq
  end
end
