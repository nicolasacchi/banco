# The operator's console path to a correction of a session's model (D-316): bin/rails banco:correct_session, never over
# HTTP, never over the API, never from the CLI (an agent does not correct a session, not even its own).
#
# A session declares its model and nobody can prove it. When the operator learns that a declaration was false, the
# ledger stays append-only (firm rule 4) and the correction is a new row of agent_session_corrections: the true model
# of a session is the model of its latest correction, else the declared one (AgentSession#model). Independence is
# derived at read time from the true models (Providers.independent?), so a correction moves every gate at once.
#
# A dry run (the default) runs the whole recording inside a savepoint that is rolled back: it measures the state of
# the reviews, blind solves, gates and minor outcomes before and after, and prints the difference without writing.
# confirm: true keeps the rows, one per session.
#
#   AgentSessionCorrector.call(session_ids: [ 772, 773 ], model: "claude-opus-5-5", reason: "...", confirm: true)
class AgentSessionCorrector
  REASON_RANGE = (3..1000)
  Result = Struct.new(:ok, :recorded, :errors, :sessions, :changes, :lines, keyword_init: true)
  SessionPlan = Struct.new(:session, :role, :declared, :current, :new_model, keyword_init: true)

  def self.call(**args) = new(**args).call

  def initialize(session_ids:, model:, reason:, confirm: false, os_user: Etc.getpwuid(Process.euid)&.name.to_s)
    @ids = Array(session_ids).map { |i| i.to_s.strip }.reject(&:empty?)
    @model = model.to_s.strip
    @reason = reason.to_s.strip
    @confirm = confirm
    @os_user = os_user.to_s.gsub(/[^A-Za-z0-9_.-]/, "").first(40)
  end

  def call
    errors = problems
    return fail_with(errors) if errors.any?

    sessions = AgentSession.where(id: @ids).includes(:corrections).order(:id).to_a
    plans = sessions.map { |s| SessionPlan.new(session: s, role: s.role, declared: s.declared_model, current: s.model, new_model: @model) }
    before = Snapshot.take
    request_id = SecureRandom.uuid
    after = nil
    AgentSessionCorrection.transaction(requires_new: true) do
      sessions.each do |s|
        AgentSessionCorrection.create!(agent_session: s, model: @model, reason: @reason, os_user: @os_user, groups: "console", remote_addr: "console",
                                       user_agent: "banco:correct_session #{@os_user}".strip, request_path: "rake banco:correct_session", request_id: "#{request_id}/#{s.id}")
      end
      after = Snapshot.take
      raise ActiveRecord::Rollback unless @confirm
    end
    changes = Snapshot.diff(before, after)
    Result.new(ok: true, recorded: @confirm, errors: [], sessions: plans, changes: changes, lines: report(plans, changes))
  end

  private

  def problems
    out = []
    out << "SESSION= needs one or more agent session ids (comma separated)" if @ids.empty?
    out << "SESSION holds a value that is not an agent session id" unless @ids.all? { |i| i.match?(AgentSession::ID) }
    out << "MODEL= is required (the true model, for example claude-opus-5-5)" if @model.empty?
    out << "MODEL is longer than 100 characters" if @model.length > 100
    out << "REASON= is required (3..1000 characters: what the operator learned and how)" unless REASON_RANGE.cover?(@reason.length)
    return out if out.any?

    found = AgentSession.where(id: @ids).includes(:corrections).index_by { |s| s.id.to_s }
    @ids.each { |i| out << "no agent session #{i}" unless found[i] }
    @ids.group_by(&:itself).each { |i, list| out << "session #{i} is named twice" if list.size > 1 }
    found.each_value do |s|
      out << "session #{s.id} already runs on #{s.model.inspect} (true model): nothing to correct" if Providers.model_key(s.model) == Providers.model_key(@model)
    end
    out
  end

  def fail_with(errors) = Result.new(ok: false, recorded: false, errors: errors, sessions: [], changes: {}, lines: [])

  def report(plans, changes)
    lines = plans.map do |p|
      "session #{p.session.id} (#{p.role}, #{p.session.agent}): declared #{p.declared.inspect}, true now #{p.current.inspect}, new #{p.new_model.inspect}"
    end
    lines << "reviews, blind solves and lesson or page reviews that stop counting: #{changes[:stop_counting].size}#{detail(changes[:stop_counting])}"
    lines << "ones that start counting: #{changes[:start_counting].size}#{detail(changes[:start_counting])}"
    lines << "gates that close (approvable before, not after): #{changes[:gates_closed].size}#{detail(changes[:gates_closed])}"
    lines << "gates that open: #{changes[:gates_opened].size}#{detail(changes[:gates_opened])}"
    lines << "minor findings whose outcome reopens (back to the teacher): #{changes[:minors_reopened].size}#{detail(changes[:minors_reopened])}"
    lines << "minor findings whose outcome changes otherwise: #{changes[:minors_changed].size}#{detail(changes[:minors_changed])}"
    lines
  end

  def detail(list) = list.empty? ? "" : " (#{list.first(30).join(', ')}#{list.size > 30 ? ', ...' : ''})"

  # The state the corrections can move, measured the same way before and after.
  module Snapshot
    module_function

    def take
      { rows: rows, gates: gates, minors: minors }
    end

    # {"ItemReview 3" => [independent, session_id], ...}
    def rows
      [ ItemReview, BlindSolve, LessonReview, PageReview ].each_with_object({}) do |model, out|
        model.includes(:agent_session).find_each { |r| out["#{model.name} #{r.id}"] = [ r.independent?, r.agent_session_id ] }
      end
    end

    # {"item key rN" => approvable, "topic key (rN)" => ..., "blueprint subject rN" => ...}
    def gates
      out = {}
      item_ids = ItemReview.distinct.pluck(:item_revision_id) | BlindSolve.distinct.pluck(:item_revision_id)
      ItemRevision.where(id: item_ids).includes(:item).find_each { |r| out["item #{r.item.key} r#{r.seq}"] = Review::Gate.check(r).approvable }
      Lesson.includes(:subject).find_each do |lesson|
        latest = TopicRevision.where(lesson_id: lesson.id).order(:id).last or next
        out["topic #{lesson.key} r#{latest.id}"] = Approval::TopicGate.mechanical(latest).approvable
      end
      Subject.find_each do |subject|
        latest = BlueprintRevision.where(subject_id: subject.id).order(:seq).last or next
        out["blueprint #{subject.key} r#{latest.seq}"] = Approval::BlueprintGate.check(latest).approvable
      end
      out
    end

    # {finding id => :closed, :to_fix or nil} for the minor findings that have an assessment.
    def minors
      ids = FindingAssessment.select(:review_finding_id)
      ReviewFinding.where(severity: "minor", id: ids).find_each.to_h { |f| [ f.id, f.opinion.minor_outcome ] }
    end

    def diff(before, after)
      moved = ->(a, b) { (a.keys & b.keys).select { |k| a[k].first != b[k].first } }
      stop = moved.call(before[:rows], after[:rows]).select { |k| before[:rows][k].first && !after[:rows][k].first }
      start = moved.call(before[:rows], after[:rows]).select { |k| !before[:rows][k].first && after[:rows][k].first }
      gate_keys = before[:gates].keys & after[:gates].keys
      minor_keys = before[:minors].keys & after[:minors].keys
      reopened = minor_keys.select { |k| before[:minors][k] && after[:minors][k].nil? }
      { stop_counting: stop, start_counting: start,
        gates_closed: gate_keys.select { |k| before[:gates][k] && !after[:gates][k] },
        gates_opened: gate_keys.select { |k| !before[:gates][k] && after[:gates][k] },
        minors_reopened: reopened.map { |id| "finding #{id}" },
        minors_changed: (minor_keys.select { |k| before[:minors][k] != after[:minors][k] } - reopened).map { |id| "finding #{id}" } }
    end
  end
end
