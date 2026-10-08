# The only writer of decisions (firm rule 2, D-08). A decision row is created here
# and nowhere else, and only for a request that arrives alive on the web listener
# from the edge proxy with
#
#   - BANCO_DECISIONS_ENABLED=1 (set by the operator, in .env, after the proofs),
#   - a Remote-User on the teacher list (BANCO_TEACHER_USERS) with the group banco-teacher,
#   - a valid CSRF token (the controller verifies it and marks the request), and
#   - no banco_device cookie (the student's computer is read-only for /teacher).
#
# The row keeps who, from where, with what and when: decision kind, subject and
# student, teacher login, groups, request id, remote address, user agent, path,
# time and the payload. Rows are never updated (ledger triggers); the latest
# decision of a kind on a target counts.
#
#   DecisionRecorder.call(request: request, kind: "dispose_finding", params: {finding_id: 3, ...})
#
# Raises Refused (403: not allowed to decide), Missing (404: no such target) or
# Invalid (422: the decision is not possible now, with the reasons in Italian-free
# plain text for the page to word).
class DecisionRecorder
  KINDS = %w[approve_skill_graph approve_blueprint confirm_test_reviewed dispose_finding confirm_grade reject_grade resolve_attempt
             void_diagnosis_run void_revision_attempts extend_diagnosis_run close_diagnosis_run release_diagnosis
             record_consent kind_override send_back_item set_formula_sheet].freeze
  CSRF_KEY = "banco.csrf_valid".freeze
  DEVICE_COOKIE = "banco_device".freeze
  RESOLVE_VERDICTS = (Grading::VERDICTS - %w[invalid short_answer]).freeze
  OVERRIDE_KINDS = %w[recover learn].freeze

  class Refused < StandardError
    attr_reader :reason

    def initialize(reason)
      @reason = reason
      super("decision refused: #{reason}")
    end
  end

  class Missing < StandardError; end

  class Invalid < StandardError
    attr_reader :reasons

    def initialize(*reasons)
      @reasons = reasons.flatten
      super(@reasons.join("; "))
    end
  end

  Context = Struct.new(:login, :groups, keyword_init: true)

  class << self
    # request_id: a decision of its own inside a request that records several (the id of the request
    # is unique per decision row); the default is the request's id.
    def call(request:, kind:, params: {}, request_id: nil)
      new(request, kind.to_s, params.to_h.with_indifferent_access, request_id).call
    end

    # nil when the request may decide, otherwise the reason (a symbol).
    def refusal(request)
      return :disabled unless ENV["BANCO_DECISIONS_ENABLED"] == "1"
      return :wrong_listener unless request.env[Banco::ListenerTag::TAG_KEY] == :web
      return :untrusted_peer unless Banco::EdgeProxy.include?(request.remote_addr)

      login = request.get_header("HTTP_REMOTE_USER").to_s.strip
      groups = groups_of(request)
      return :no_teacher unless !login.empty? && !login.include?(",") && groups.include?(EdgeTrust::TEACHER_GROUP) && Banco::EdgeProxy.teacher_users.include?(login)
      return :student_device if request.cookies[DEVICE_COOKIE].present?
      return :csrf unless request.env[CSRF_KEY] == true

      nil
    end

    def groups_of(request) = request.get_header("HTTP_REMOTE_GROUPS").to_s.split(",").map(&:strip).reject(&:empty?)
  end

  def initialize(request, kind, params, request_id = nil)
    @request = request
    @kind = kind
    @params = params
    @request_id = request_id
  end

  def call
    raise Invalid, "unknown decision kind #{@kind.inspect}" unless KINDS.include?(@kind)
    reason = self.class.refusal(@request)
    raise Refused, reason if reason

    Decision.transaction do
      subject, student, payload = send(@kind)
      Decision.create!(
        kind: @kind, subject: subject, student: student, payload_json: JSON.generate(payload),
        request_id: @request_id.presence || @request.request_id.presence || SecureRandom.uuid,
        teacher_login: @request.get_header("HTTP_REMOTE_USER").to_s.strip,
        groups: self.class.groups_of(@request).join(","), remote_addr: @request.remote_addr,
        user_agent: @request.user_agent.to_s.first(300), request_path: @request.path.to_s.first(300)
      )
    end
  end

  private

  # Each handler returns [subject, student, payload] or raises Invalid / Missing.

  def approve_skill_graph
    revision = find(SkillGraphRevision, :revision_id)
    latest = SkillGraphRevision.where(subject: revision.subject).maximum(:seq)
    raise Invalid, "revision #{revision.id} is not the latest graph of #{revision.subject.key}: approve the latest" unless revision.seq == latest

    [ revision.subject, nil, { revision_id: revision.id, seq: revision.seq } ]
  end

  def approve_blueprint
    revision = find(BlueprintRevision, :revision_id)
    latest = BlueprintRevision.where(subject: revision.subject).maximum(:seq)
    raise Invalid, "revision #{revision.id} is not the latest entry test of #{revision.subject.key}: approve the latest" unless revision.seq == latest

    gate = Approval::BlueprintGate.check(revision)
    raise Invalid, gate.reasons unless gate.approvable

    [ revision.subject, nil, { revision_id: revision.id, seq: revision.seq, graph_revision_id: revision.skill_graph_revision_id } ]
  end

  # "Ho visto tutte le domande di questa prova": the teacher read every question of this very
  # revision on the page of all questions (the pinned items were opened there). It stands in the
  # approval gate for playing the whole test as the preview student (D-215).
  def confirm_test_reviewed
    revision = find(BlueprintRevision, :revision_id)
    latest = BlueprintRevision.where(subject: revision.subject).maximum(:seq)
    raise Invalid, "revision #{revision.id} is not the latest entry test of #{revision.subject.key}: confirm the latest" unless revision.seq == latest

    unseen = revision.pinned_item_revision_ids - Approval::BlueprintGate.viewed_ids.to_a
    raise Invalid, unseen.map { |id| "item revision #{id} was not opened in the preview" } if unseen.any?

    [ revision.subject, nil, { revision_id: revision.id, seq: revision.seq } ]
  end

  # "Rimanda": the item goes back to the content agent with a reason code and a comment.
  def send_back_item
    revision = find(ItemRevision, :item_revision_id)
    code = @params[:reason_code].to_s
    raise Invalid, "reason_code is one of #{Teacher::SendBacks::CODES.join(', ')}" unless Teacher::SendBacks::CODES.include?(code)

    comment = @params[:comment_it].to_s.strip
    raise Invalid, "a comment is required" if comment.length < 3

    [ revision.item.subject, nil, { item_revision_id: revision.id, item: revision.item.key, seq: revision.seq, reason_code: code, comment_it: comment.first(1000) } ]
  end

  def dispose_finding
    finding = find(ReviewFinding, :finding_id)
    disposition = @params[:disposition].to_s
    raise Invalid, "disposition is one of #{ReviewFinding::DISPOSITIONS.join(', ')}" unless ReviewFinding::DISPOSITIONS.include?(disposition)

    [ finding.item_revision.item.subject, nil, { finding_id: finding.id, disposition: disposition, reason_it: reason! } ]
  end

  def confirm_grade
    proposal = find(GradeProposal, :grade_proposal_id)
    raise Invalid, "proposal #{proposal.id} was already confirmed" if proposal.confirmed?

    run = student_run_of!(proposal.attempt)
    payload = { grade_proposal_id: proposal.id, attempt_id: proposal.attempt_id, edited: false }
    scores = @params[:scores]
    if scores.present?
      # The teacher's edit is the new grade: the scores replace the proposal's.
      weights = JSON.parse(proposal.attempt.item_instance.item_revision.body_json).dig("rubric", "points").to_h { |p| [ p["id"], p["weight"] ] }
      given = scores.to_h.transform_keys(&:to_s).transform_values { |v| Integer(v, exception: false) }
      raise Invalid, "give a score for each of #{weights.keys.join(', ')}" unless given.keys.sort == weights.keys.sort
      raise Invalid, "a score is a whole number from 0 to the weight of its point" unless given.all? { |id, v| v && v.between?(0, weights[id]) }

      total = given.values.sum
      payload.merge!(edited: true, scores: given, total: total, max_total: proposal.max_total, reason_it: reason!)
      payload[:passed] = total.to_f / proposal.max_total >= proposal.threshold
    else
      payload[:passed] = proposal.meets_threshold
    end
    [ run.subject, run.student, payload ]
  end

  def reject_grade
    proposal = find(GradeProposal, :grade_proposal_id)
    raise Invalid, "proposal #{proposal.id} was already confirmed" if proposal.confirmed?

    run = student_run_of!(proposal.attempt)
    [ run.subject, run.student, { grade_proposal_id: proposal.id, attempt_id: proposal.attempt_id, reason_it: reason! } ]
  end

  def resolve_attempt
    attempt = find(Attempt, :attempt_id)
    run = student_run_of!(attempt)
    verdict = @params[:verdict].to_s
    raise Invalid, "verdict is one of #{RESOLVE_VERDICTS.join(', ')}" unless RESOLVE_VERDICTS.include?(verdict)

    payload = { attempt_id: attempt.id, verdict: verdict, reason_it: reason! }
    payload[:error_code] = @params[:error_code].to_s if @params[:error_code].present?
    [ run.subject, run.student, payload ]
  end

  def void_diagnosis_run
    run = student_run!
    raise Invalid, "run #{run.id} is already voided" if Diagnosis::EventLoader.voided?(run)

    [ run.subject, run.student, { run_id: run.id, reason_it: reason! } ]
  end

  def extend_diagnosis_run
    run = student_run!
    raise Invalid, "run #{run.id} is voided" if Diagnosis::EventLoader.voided?(run)

    [ run.subject, run.student, { run_id: run.id, reason_it: reason! } ]
  end

  def close_diagnosis_run
    run = student_run!
    raise Invalid, "run #{run.id} is voided" if Diagnosis::EventLoader.voided?(run)

    [ run.subject, run.student, { run_id: run.id, reason_it: reason! } ]
  end

  def void_revision_attempts
    revision = find(ItemRevision, :item_revision_id)
    student = Student.find_by(key: "student") or raise Missing, "no student"
    [ revision.item.subject, student, { item_revision_id: revision.id, reason_it: reason! } ]
  end

  # All 11 subjects together (operator Q1): no subject may be left out.
  def release_diagnosis
    raise Invalid, "the diagnosis is already open" if Diagnosis::Release.open?

    reasons = []
    reasons << "the consent is not recorded" unless Decision.exists?(kind: "record_consent")
    student = Student.find_by(key: "student")
    reasons << "the warm-up is not completed" unless student && Diagnosis::Warmup.complete?(student)
    subjects = Subject.order(:position).to_a
    reasons << "there is no subject" if subjects.empty?
    subjects.each do |s|
      reasons << "#{s.key}: graph and entry test are not both approved" unless SubjectStage.approved_graph(s) && SubjectStage.approved_blueprint(s)
    end
    raise Invalid, reasons if reasons.any?

    [ nil, student, { subjects: subjects.map(&:key) } ]
  end

  def record_consent
    raise Invalid, "the consent is already recorded" if Decision.exists?(kind: "record_consent")
    raise Invalid, "the consent must be confirmed" unless ActiveModel::Type::Boolean.new.cast(@params[:acknowledged]) == true

    [ nil, nil, { acknowledged: true, statement_it: @params[:statement_it].to_s.first(500) } ]
  end

  def kind_override
    subject = Subject.find_by(key: @params[:subject].to_s) or raise Missing, "no subject #{@params[:subject].to_s.first(30).inspect}"
    skill = @params[:skill].to_s
    graph = SkillGraphRevision.where(subject: subject).order(:seq).last
    known = graph ? JSON.parse(graph.body_json)["skills"].map { |s| s["key"] } : []
    raise Invalid, "#{skill.inspect} is not a skill of the graph of #{subject.key}" unless known.include?(skill)

    kind = @params[:override_kind].to_s
    raise Invalid, "kind is one of #{OVERRIDE_KINDS.join(', ')}" unless OVERRIDE_KINDS.include?(kind)

    [ subject, nil, { skill: skill, kind: kind, reason_it: reason! } ]
  end

  # The formula sheet of a subject's entry test, on or off (D-216). Default off. It can be switched
  # on only when the approved entry test (else the latest draft) has a sheet. The latest decision counts;
  # the report marks every skill outcome that used attempts with the sheet available.
  def set_formula_sheet
    subject = Subject.find_by(key: @params[:subject].to_s) or raise Missing, "no subject #{@params[:subject].to_s.first(30).inspect}"
    enabled = case @params[:enabled].to_s
    when "true", "1" then true
    when "false", "0" then false
    else raise Invalid, "enabled is true or false"
    end
    blueprint = Diagnosis::FormulaSheet.target_blueprint(subject)
    raise Invalid, "the entry test of #{subject.key} has no formula sheet" if enabled && Diagnosis::FormulaSheet.text(blueprint).nil?

    [ subject, nil, { subject: subject.key, enabled: enabled, blueprint_revision_id: blueprint&.id } ]
  end

  # ---- helpers

  def find(model, key)
    id = Integer(@params[key].to_s, exception: false)
    (id && model.find_by(id: id)) or raise Missing, "no #{model.name} #{@params[key].to_s.first(20).inspect}"
  end

  # The reason is required, in the teacher's words.
  def reason!
    text = @params[:reason_it].to_s.strip
    raise Invalid, "a reason is required" if text.length < 3

    text.first(1000)
  end

  def student_run!
    run = find(DiagnosisRun, :run_id)
    raise Invalid, "run #{run.id} is a preview run" unless run.student.kind == "student"

    run
  end

  def student_run_of!(attempt)
    run = attempt.served_event&.diagnosis_run
    raise Invalid, "attempt #{attempt.id} is not an answer of a diagnosis run" unless run && attempt.context == "diagnosis" && run.student.kind == "student"

    run
  end
end
