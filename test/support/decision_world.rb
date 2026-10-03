require_relative "student_ui_rows"

# What the teacher's decision routes need: the web environment (edge proxy, teacher
# list, decisions switched on, CSRF protection really on), a synthetic subject with
# every component, one student run with a short answer and its proposal, and the
# helpers that post a decision the way the browser does.
module DecisionWorld
  include StudentUiRows

  EDGE = ListenerHelpers::EDGE_IP
  TEACHER = { "Remote-User" => "nik", "Remote-Groups" => "banco-teacher" }.freeze

  def self.included(base)
    base.setup do
      @saved_env = ENV.to_h.slice("BANCO_EDGE_PROXY", "BANCO_TEACHER_USERS", "BANCO_DECISIONS_ENABLED")
      ENV["BANCO_EDGE_PROXY"] = "#{EDGE}/32"
      ENV["BANCO_TEACHER_USERS"] = "nik"
      ENV["BANCO_DECISIONS_ENABLED"] = "1"
      @saved_forgery = ActionController::Base.allow_forgery_protection
      ActionController::Base.allow_forgery_protection = true
    end
    base.teardown do
      %w[BANCO_EDGE_PROXY BANCO_TEACHER_USERS BANCO_DECISIONS_ENABLED].each { |k| @saved_env.key?(k) ? ENV[k] = @saved_env[k] : ENV.delete(k) }
      ActionController::Base.allow_forgery_protection = @saved_forgery
    end
  end

  # The CSRF token of a teacher session (the page's meta tag).
  def csrf_token(headers: TEACHER)
    on(:web, "/teacher", headers: headers, remote_addr: EDGE)
    css_select("meta[name=csrf-token]").first&.[]("content")
  end

  # POST a decision as the browser would. csrf: false sends no token.
  def decide(path, params = {}, listener: :web, headers: TEACHER, csrf: true, remote_addr: EDGE, token: nil)
    token ||= csrf_token if csrf
    sent = headers.merge("Content-Type" => "application/json", "Accept" => "application/json")
    sent["X-CSRF-Token"] = token if token
    on(listener, path, method: :post, headers: sent, params: params.to_json, remote_addr: remote_addr)
  end

  def json = response.parsed_body

  # A synthetic subject (not approved), a student run with one short answer that has
  # a grade proposal, and its parts in @world.
  def build_decision_world
    @world = build_ui_subject(approve: false)
    @subject = @world[:subject]
    @student = @world[:student]
    @graph = SkillGraphRevision.where(subject: @subject).order(:seq).last
    @blueprint = @world[:blueprint]
    @session = AgentSession.create!(label: "rev", role: "reviewer", agent: "omp", model: "gpt-5.2")
    @run = DiagnosisRun.create!(student: @student, subject: @subject, blueprint_revision: @blueprint, sequence: 1, seed_salt: "s",
                                rules_version: "v1", engine_version: "e1")
    @short = @world[:revisions]["short_answer"]
    instance = @short.instances.order(:id).first
    event = DiagnosisEvent.create!(diagnosis_run: @run, seq: 1, kind: "item_served", at: Time.current)
    ItemServed.create!(diagnosis_event: event, item_instance: instance, skill_key: skill_key("math", "short_answer"))
    @attempt = Attempt.create!(student: @student, context: "diagnosis", served_event: event, client_attempt_id: "c-1", item_instance: instance,
                               raw: "Una risposta.", source: "text", answered_at: Time.current)
    AttemptGrading.create!(attempt: @attempt, seq: 1, verdict: "short_answer", grader: "closed", grader_version: "t", source: "sync")
    @proposal = GradeProposal.create!(attempt: @attempt, agent_session: @session, points_json: [ { point_id: "a", score: 1 }, { point_id: "b", score: 0 } ].to_json,
                                      total: 1, max_total: 2, threshold: 0.6, meets_threshold: false)
  end

  # Everything approve_blueprint asks, except the approved graph.
  def make_blueprint_approvable!(blueprint = @blueprint)
    blueprint.pinned_item_revision_ids.each do |id|
      revision = ItemRevision.find(id)
      ItemReview.create!(item_revision: revision, agent_session: @session, checklist_json: "[]")
      BlindSolve.create!(item_revision: revision, agent_session: @session, answers_json: "[]", results_json: "[]")
      AppEvent.create!(kind: "teacher_viewed_item", payload_json: { item_revision_id: id }.to_json)
    end
    play_preview!(blueprint)
  end

  # The teacher's whole test as the preview student: a closed run in the context teacher_preview.
  def play_preview!(blueprint = @blueprint)
    preview = Student.find_or_create_by!(key: "preview") { |s| s.kind = "preview" }
    run = DiagnosisRun.create!(student: preview, subject: blueprint.subject, blueprint_revision: blueprint, sequence: DiagnosisRun.where(student: preview).count + 1,
                               seed_salt: "p", rules_version: "v1", engine_version: "e1")
    DiagnosisEvent.create!(diagnosis_run: run, seq: 1, kind: "run_closed", payload_json: { reason: "all_resolved" }.to_json, at: Time.current)
    run
  end

  def approve_graph_row!(subject = @subject, revision = @graph)
    Decision.create!(kind: "approve_skill_graph", subject: subject, payload_json: { revision_id: revision.id }.to_json, request_id: SecureRandom.uuid,
                     teacher_login: "nik", groups: "banco-teacher", remote_addr: EDGE)
  end
end
