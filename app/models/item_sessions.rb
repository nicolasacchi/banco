# Who touched an item, by role (A-04). Reads the file_sessions of every revision,
# the reviews, the blind solves and the assessments of findings. The rule is that the sessions of the five roles
# are disjoint on one item (E-SESSION-NOT-INDEPENDENT); it guards against mistakes.
#
# Two questions, kept apart, as on a lesson (LessonSessions, D-374). WHO may review or solve (a session identity: ids/conflicts) is
# every author of the item. WHICH MODELS a review or a solve must differ from (model_authors, D-391) is narrower: the authors
# of the revisions after the last approved base that was itself reviewed and solved independently. Providers.refusal (the
# write-time refusal) and Providers.counting (the read-time counting) both ask model_authors, so the two cannot disagree.
class ItemSessions
  AUTHORED = %w[item.json generator.mjs].freeze

  # The session book of an item or of a lesson (Phase 1b).
  def self.for(thing)
    return LessonSessions.new(thing) if thing.is_a?(Lesson)
    return PageSessions.new(thing) if thing.is_a?(Page)

    new(thing)
  end

  def initialize(item)
    @item = item
  end

  # AgentSession rows that hold +role+ on the item: author, verifier, reviewer, solver, arbiter.
  def sessions(role)
    AgentSession.where(id: ids(role.to_s)).order(:id).to_a
  end

  def ids(role)
    case role
    when "author" then from_files { |name| author_file?(name) }
    when "verifier" then from_files { |name| name == "verify.mjs" }
    when "reviewer" then ItemReview.where(item_revision_id: revision_ids).distinct.pluck(:agent_session_id)
    when "solver" then BlindSolve.where(item_revision_id: revision_ids).distinct.pluck(:agent_session_id)
    when "arbiter" then FindingAssessment.joins(:review_finding).where(review_findings: { item_revision_id: revision_ids }).distinct.pluck(:agent_session_id)
    else []
    end
  end

  # The roles other than +role+ that the session already holds on the item.
  def conflicts(session_id, role)
    (%w[author verifier reviewer solver arbiter] - [ role.to_s ]).select { |r| ids(r).include?(session_id) }
  end

  # The AgentSession rows whose models a reviewer or a blind solver of +revision+ must differ from (D-391).
  #
  # The base of +revision+ is the newest revision of the item before it that the teacher approved (an approve_topic decision
  # pins it, or an approve_blueprint one) and that has, on record, a review and a blind solve both independent of what its own
  # authors were then. With a base, only the authors of the revisions after it, up to +revision+, count: the base was judged by
  # an independent reviewer and an independent solver, so whoever reads the change cannot share a model with the author of
  # the change. Without a base: every author of the item, as before.
  def model_authors(revision)
    base = base_of(revision)
    return sessions("author") unless base

    authors_between(base.seq, revision.seq)
  end

  # The newest approved revision of the item before +revision+, when it has a review and a blind solve on record that were
  # independent of the authors they faced (the delta since its own base, else every author up to it); nil otherwise (no
  # fallback to an older approval: the last approved revision is the one that was read). Review::Gate asks both a review and
  # a blind solve of every item revision, so a base needs both.
  def base_of(revision)
    approved = approved_revisions.select { |r| r.seq < revision.seq }.max_by(&:seq)
    approved if approved && independently_worked?(approved)
  end

  private

  def author_file?(name) = name == "item.json" || name == "generator.mjs" || name.start_with?("assets/")

  def independently_worked?(revision)
    base = base_of(revision)
    authors = authors_between(base ? base.seq : 0, revision.seq)
    [ ItemReview, BlindSolve ].all? do |klass|
      klass.where(item_revision_id: revision.id).includes(agent_session: :corrections).any? { |row| Providers.independent?(row.agent_session, authors) }
    end
  end

  # The AgentSession rows that wrote something in the revisions with seq in (after_seq, upto_seq]: the author sessions of the
  # files each revision changed against the one before it (file_sessions also carries over the writers of unchanged files).
  def authors_between(after_seq, upto_seq)
    ids = [ nil, *revisions ].each_cons(2).flat_map { |prev, rev| rev.seq > after_seq && rev.seq <= upto_seq ? wrote(prev, rev) : [] }
    AgentSession.where(id: ids.compact.map(&:to_i).uniq).order(:id).to_a
  end

  # The session ids of the author files that +rev+ added or changed against +prev+ (nil for the first revision: all of them).
  def wrote(prev, rev)
    map = rev.file_sessions
    files = rev.files
    ids = map.filter_map { |name, id| id if author_file?(name) && (prev.nil? || prev.files[name] != files[name] || prev.file_sessions[name] != id) }
    ids << rev.author_session_id if rev.author_session_id && (prev.nil? || prev.body_json != rev.body_json || prev.author_session_id != rev.author_session_id)
    ids
  end

  # The revisions of the item that an approve_topic or an approve_blueprint decision pinned, whenever it was recorded.
  def approved_revisions
    @approved_revisions ||= ItemRevision.where(item_id: @item.id, id: Course::Decisions.approved_item_revision_ids(@item)).to_a
  end

  def revisions = @revisions ||= ItemRevision.where(item_id: @item.id).order(:seq).to_a

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
