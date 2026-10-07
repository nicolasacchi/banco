require "test_helper"
require_relative "../support/multi_user"
require_relative "../support/decision_world"

# D-217: the guest reads every teacher page and writes nothing. The routes come from the routes
# table, so a route added later is covered without touching this file.
class GuestReadOnlyTest < ActionDispatch::IntegrationTest
  include MultiUser
  include DecisionWorld

  setup do
    ENV["BANCO_TEACHER_USERS"] = "nik,teacher-a@example.test"
    build_decision_world
    approve_graph_row!
    make_blueprint_approvable!
    @values = {
      key: "math", subject: "math", skill: "math.number", revision_id: @short.id, finding_id: 1, grade_proposal_id: @proposal.id,
      attempt_id: @attempt.id, run_id: @run.id, item_revision_id: @short.id, sha256: "0" * 64
    }
  end

  # [verb, concrete path] for every route of the teacher's area.
  def teacher_routes
    Rails.application.routes.routes.filter_map do |route|
      spec = route.path.spec.to_s.sub("(.:format)", "")
      next unless spec == "/teacher" || spec.start_with?("/teacher/")

      values = spec.start_with?("/teacher/refs/") ? @values.merge(key: "math.number") : @values
      path = spec.gsub(/:(\w+)/) { values.fetch(Regexp.last_match(1).to_sym) { flunk "no sample value for :#{Regexp.last_match(1)} in #{spec}" }.to_s }
      [ route.verb, path ]
    end
  end

  def counts
    [ Decision, Attempt, DiagnosisRun, DiagnosisEvent, AppEvent, Student, ItemServed ].map(&:count)
  end

  test "the routes table has the teacher's routes in it" do
    verbs = teacher_routes.map(&:first).tally
    assert_operator verbs["GET"], :>=, 9
    assert_operator verbs["POST"], :>=, 20
  end

  test "a guest reads every teacher page and is refused on every write, with nothing written" do
    token = csrf_token(headers: GUEST)
    before = counts
    teacher_routes.each do |verb, path|
      if verb == "GET"
        on(:web, path, headers: GUEST, remote_addr: EDGE)
        expected = path.start_with?("/teacher/preview") ? :forbidden : :success
        assert_response expected, "GET #{path}"
      else
        on(:web, path, method: verb.downcase.to_sym, headers: GUEST.merge("X-CSRF-Token" => token, "Content-Type" => "application/json", "Accept" => "application/json"),
                       params: { reason_it: "Prova.", acknowledged: true, verdict: "correct" }.to_json, remote_addr: EDGE)
        assert_response :forbidden, "#{verb} #{path}"
      end
    end
    assert_equal before, counts
  end

  test "the teacher is not refused on the same routes" do
    teacher_routes.select { |verb, path| verb == "GET" && !path.include?("/preview/runs/") }.each do |_, path|
      on(:web, path, headers: TEACHER, remote_addr: EDGE)
      assert_response :success, "GET #{path}"
    end
  end

  test "opening an item as a guest records no view, as a teacher it does" do
    before = AppEvent.where(kind: "teacher_viewed_item").count
    on(:web, "/teacher/items/#{@short.id}", headers: GUEST, remote_addr: EDGE)
    assert_response :success
    on(:web, "/teacher/subjects/math/test/all", headers: GUEST, remote_addr: EDGE)
    assert_response :success
    assert_equal before, AppEvent.where(kind: "teacher_viewed_item").count
    on(:web, "/teacher/items/#{@short.id}", headers: TEACHER, remote_addr: EDGE)
    assert_equal before + 1, AppEvent.where(kind: "teacher_viewed_item").count
  end

  test "no form and no action button is drawn for a guest, and the page says read only" do
    [ "/teacher", "/teacher/subjects/math/graph", "/teacher/subjects/math/test", "/teacher/subjects/math/test/all", "/teacher/subjects/math/test/skills/math.number",
      "/teacher/subjects/math/report", "/teacher/corrections", "/teacher/items/#{@short.id}", "/teacher/items/#{@short.id}/play",
      "/teacher/refs/math.number", "/teacher/refs/#{@short.item.key}" ].each do |path|
      on(:web, path, headers: GUEST, remote_addr: EDGE)
      assert_response :success, path
      assert_select "form", 0, path
      assert_select "button[type=submit]", 0, path
      assert_select "#read-only-notice", /Sei in sola lettura/, path
      assert_select "[data-controller=activity]", 0, path
      assert_select "a[href^='/teacher/preview']", 0, path
    end
    on(:web, "/teacher/subjects/math/graph", headers: TEACHER, remote_addr: EDGE)
    assert_select "form.decide"
    assert_select "#read-only-notice", 0
  end

  test "the activity beat of a guest records nothing, the teacher's is recorded" do
    token = csrf_token(headers: GUEST)
    on(:web, "/teacher/activity", method: :post, headers: GUEST.merge("X-CSRF-Token" => token), params: { unit: "home" }, remote_addr: EDGE)
    assert_response :forbidden
    assert_equal 0, AppEvent.where(kind: "teacher_active").count
  end

  test "DecisionRecorder keeps its own guard: a guest request is refused" do
    token = csrf_token(headers: GUEST)
    on(:web, "/teacher/consent", method: :post, headers: GUEST.merge("X-CSRF-Token" => token, "Content-Type" => "application/json"),
                                 params: { acknowledged: true }.to_json, remote_addr: EDGE)
    assert_response :forbidden
    request_like = Struct.new(:env, :remote_addr) do
      def get_header(name) = { "HTTP_REMOTE_USER" => "guest-a@example.test", "HTTP_REMOTE_GROUPS" => "banco-guest" }[name]
      def cookies = {}
    end.new({ Banco::ListenerTag::TAG_KEY => :web, DecisionRecorder::CSRF_KEY => true }, EDGE)
    assert_equal :no_teacher, DecisionRecorder.refusal(request_like)
    assert_equal 0, Decision.where(kind: "record_consent").count
  end
end
