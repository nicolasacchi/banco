# The operator's console path to a teacher decision (D-260): bin/rails banco:decide, never over HTTP.
# It builds a DecisionRecorder::Console origin and hands the kind and its parameters to DecisionRecorder,
# the only writer, so every business guard of the kind holds exactly as on the web. A dry run (the default)
# runs the whole recorder inside a savepoint that is rolled back, so it shows the payload and the gate
# result without writing; confirm: true keeps the row.
#
#   DecisionConsole.call(kind: "approve_skill_graph", teacher: "nik", subject: "history", reason: "...", confirm: true)
class DecisionConsole
  Result = Struct.new(:ok, :recorded, :decision, :payload, :errors, keyword_init: true)

  APPROVALS = { "approve_skill_graph" => [ SkillGraphRevision, :approved_graph ],
                "approve_blueprint" => [ BlueprintRevision, :approved_blueprint ] }.freeze
  SUBJECT_KINDS = %w[kind_override set_formula_sheet release_course].freeze

  def self.call(**args) = new(**args).call

  # params: any other parameter of the kind (finding_id, disposition, ...), as the web form would send it.
  def initialize(kind:, teacher:, subject: nil, revision: nil, reason: nil, params: {}, confirm: false, os_user: ENV["USER"].to_s)
    @kind = kind.to_s
    @teacher = teacher
    @subject_key = subject.presence
    @revision = revision.presence
    @reason = reason.presence
    @params = params.to_h.with_indifferent_access
    @confirm = confirm
    @os_user = os_user
  end

  def call
    origin = DecisionRecorder::Console.new(login: @teacher, os_user: @os_user)
    refusal = DecisionRecorder.refusal(origin)
    raise DecisionRecorder::Refused, refusal if refusal
    params = build_params
    already_approved!(params)
    decision = nil
    Decision.transaction(requires_new: true) do
      decision = DecisionRecorder.call(request: origin, kind: @kind, params: params)
      raise ActiveRecord::Rollback unless @confirm
    end
    Result.new(ok: true, recorded: @confirm, decision: decision, payload: JSON.parse(decision.payload_json), errors: [])
  rescue DecisionRecorder::Refused => e
    fail_with("refused: #{e.reason}")
  rescue DecisionRecorder::Missing => e
    fail_with(e.message)
  rescue DecisionRecorder::Invalid => e
    fail_with(*e.reasons)
  rescue ActiveRecord::RecordNotUnique
    fail_with("this request was already recorded")
  end

  private

  def fail_with(*errors) = Result.new(ok: false, recorded: false, errors: errors)

  def build_params
    params = @params.dup
    params[:reason_it] = @reason if @reason
    if @subject_key
      params[:subject] ||= @subject_key
      params[:revision_id] ||= latest_revision_id if APPROVALS.key?(@kind) || @kind == "confirm_test_reviewed"
    end
    params[:revision_id] = @revision if @revision
    params
  end

  # The latest revision of the subject for the kinds that approve one.
  def latest_revision_id
    subject = Subject.find_by(key: @subject_key) or raise DecisionRecorder::Missing, "no subject #{@subject_key.to_s.first(30).inspect}"
    model = @kind == "approve_skill_graph" ? SkillGraphRevision : BlueprintRevision
    model.where(subject: subject).order(:seq).last&.id or raise DecisionRecorder::Missing, "#{subject.key} has no #{model.name.underscore.humanize.downcase}"
  end

  def already_approved!(params)
    model, reader = APPROVALS[@kind]
    return unless model

    revision = model.find_by(id: Integer(params[:revision_id].to_s, exception: false))
    return unless revision

    approved = SubjectStage.public_send(reader, revision.subject)
    raise DecisionRecorder::Invalid, "revision #{revision.id} of #{revision.subject.key} is already approved" if approved&.id == revision.id
  end
end
