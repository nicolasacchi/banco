require "test_helper"
require_relative "../support/student_ui_rows"

# X-01: what the browser is told. Over 50 seeds the served JSON carries no key
# field and no outcome, and ordering and matching are never shown in key order.
class DiagnosisPayloadTest < ActionDispatch::IntegrationTest
  include StudentUiRows

  EDGE = ListenerHelpers::EDGE_IP
  STUDENT = { "Remote-User" => "student", "Remote-Groups" => "banco-student", "Content-Type" => "application/json" }.freeze

  # Names that belong to the key, the grading or the shuffle, wherever they are.
  FORBIDDEN_KEYS = %w[answer answers errors error_catalogue solution steps final id_map shown_order verdict correct outcome
                      result score expected fingerprint rubric model_answer_it message_it grading evidence].freeze

  setup do
    @saved = ENV.to_h.slice("BANCO_EDGE_PROXY")
    ENV["BANCO_EDGE_PROXY"] = "#{EDGE}/32"
    @rows = build_ui_subject
    release_diagnosis!
  end

  teardown { @saved.key?("BANCO_EDGE_PROXY") ? ENV["BANCO_EDGE_PROXY"] = @saved["BANCO_EDGE_PROXY"] : ENV.delete("BANCO_EDGE_PROXY") }

  def post_json(path, body = {})
    on(:web, path, method: :post, headers: STUDENT, params: body.to_json, remote_addr: EDGE)
    response.parsed_body
  end

  def make_run(n)
    DiagnosisRun.create!(student: @rows[:student], subject: @rows[:subject], blueprint_revision: @rows[:blueprint], sequence: n,
                         seed_salt: "payload-#{n}", rules_version: Diagnosis::Rules::V1::RULES_VERSION,
                         engine_version: Diagnosis::Engine::VERSION)
  end

  def keys_of(value, found = [])
    case value
    when Hash then value.each { |k, v| found << k.to_s; keys_of(v, found) }
    when Array then value.each { |v| keys_of(v, found) }
    end
    found
  end

  # The payloads of 50 seeds, played once per process (the rows are rolled back, the
  # JSON is kept).
  class << self
    attr_accessor :sweep_cache
  end

  def sweep = (self.class.sweep_cache ||= (0...50).map { |n| play_direct(n) { |_payload| } })

  # What step answers for an item, built without HTTP: the sweep over 50 seeds gives
  # every seed a student of its own, because a student never sees an instance twice.
  def play_direct(n)
    student = Student.create!(key: "sweep-#{n}", kind: "student")
    run = DiagnosisRun.create!(student: student, subject: @rows[:subject], blueprint_revision: @rows[:blueprint], sequence: 1,
                               seed_salt: "payload-#{n}", rules_version: Diagnosis::Rules::V1::RULES_VERSION,
                               engine_version: Diagnosis::Engine::VERSION)
    conductor = Diagnosis::Conductor.new(run)
    recorder = Diagnosis::AnswerRecorder.new(student: student, context: "diagnosis")
    served = []
    60.times do
      step = conductor.step!
      break unless step.type == :item

      payload = JSON.parse({ type: "item" }.merge(conductor.presentation(step.event, student: student)).to_json)
      served << payload
      yield payload
      reply = recorder.call(served_event_id: step.event.id, client_attempt_id: SecureRandom.uuid, raw: Grading::DONT_KNOW_RAW, source: "button")
      assert_equal "recorded", reply.status
    end
    served
  end

  # Plays a run over HTTP to its end, answering "Non lo so"; yields each served payload.
  def play(run)
    items = []
    60.times do
      step = post_json("/diagnosis/runs/#{run.id}/step")
      break if step["type"] == "final"

      case step["type"]
      when "item"
        items << step
        yield step
        reply = post_json("/diagnosis/answers", served_event_id: step["served_event_id"], client_attempt_id: SecureRandom.uuid,
                                                 raw: Grading::DONT_KNOW_RAW, source: "button")
        assert_equal "recorded", reply["status"]
      when "sitting_over", "wait" then break
      else flunk "unexpected step #{step.inspect}"
      end
    end
    items
  end

  test "over 50 seeds no key field and no outcome appear in the served JSON" do
    components = Set.new
    sweep.each_with_index do |served, n|
      served.each do |step|
        assert_equal %w[item not_studied_button number served_event_id subject type].sort, step.keys.sort, "step keys"
        bad = keys_of(step) & FORBIDDEN_KEYS
        assert_empty bad, "seed #{n}: key or outcome fields in the payload: #{bad}"
        refute_match(/Si fa il conto|dont_know|odd_pick|adds_wrong/, step.to_json, "seed #{n}")
        components << step["item"]["component"]
      end
    end
    assert_equal COMPONENTS.to_set, components, "every component was served"
  end

  test "over 50 seeds ordering and matching are never shown in key order" do
    seen = Hash.new(0)
    sweep.each_with_index do |served, n|
      served.each do |step|
        item = step["item"]
        case item["component"]
        when "ordering"
          values = item["elements"].map { |e| e["text"].to_i }
          refute_equal values.sort, values, "seed #{n}: ordering shown in key order"
          refute_equal values.sort.reverse, values, "seed #{n}: ordering shown in reverse key order"
          assert_equal %w[e1 e2 e3 e4], item["elements"].map { |e| e["id"] }
          seen["ordering"] += 1
        when "matching"
          left = item["left"].map { |e| e["text"].to_i }
          refute_equal left.sort, left, "seed #{n}: matching left column in stored order"
          words = item["right"].map { |e| e["text"] }
          refute_equal %w[uno due tre quattro cinque], words.map { |w| w.sub(/\d+\z/, "") }, "seed #{n}: right column in stored order"
          assert_equal %w[l1 l2 l3 l4], item["left"].map { |e| e["id"] }
          assert_equal %w[r1 r2 r3 r4 r5], item["right"].map { |e| e["id"] }
          seen["matching"] += 1
        when "choice"
          assert_equal %w[o1 o2 o3 o4], item["options"].map { |e| e["id"] }
          seen["choice"] += 1
        when "testlet"
          item["sub_items"].each { |s| assert_equal %w[o1 o2 o3 o4], s["options"].map { |e| e["id"] } }
        end
      end
    end
    assert_operator seen["ordering"], :>=, 50
    assert_operator seen["matching"], :>=, 50
  end

  test "the shuffle and its id map are logged with the serve and never sent" do
    checked = 0
    play(make_run(1)) do |step|
      next unless %w[choice ordering matching].include?(step["item"]["component"])

      served = ItemServed.find_by!(diagnosis_event_id: step["served_event_id"])
      map = JSON.parse(served.id_map_json)
      order = JSON.parse(served.shown_order_json)
      refute_empty map
      refute_empty order
      assert_equal map.values.sort, order.values.flatten.sort
      refute_includes step.to_json, served.id_map_json
      checked += 1
    end
    assert_operator checked, :>=, 3
  end

  test "asking again for the open item shows the same shuffle" do
    run = make_run(1)
    first = post_json("/diagnosis/runs/#{run.id}/step")
    again = post_json("/diagnosis/runs/#{run.id}/step")
    assert_equal first, again
  end

  test "a retried answer is recorded once" do
    run = make_run(1)
    step = post_json("/diagnosis/runs/#{run.id}/step")
    body = { served_event_id: step["served_event_id"], client_attempt_id: "client-attempt-1", raw: Grading::DONT_KNOW_RAW, source: "button" }
    2.times { assert_equal({ "status" => "recorded" }, post_json("/diagnosis/answers", body)) }
    assert_equal 1, Attempt.where(client_attempt_id: "client-attempt-1").count
    assert_equal 1, AttemptGrading.count
  end

  test "the reply to an answer is only a status, never a verdict" do
    run = make_run(1)
    step = post_json("/diagnosis/runs/#{run.id}/step")
    reply = post_json("/diagnosis/answers", served_event_id: step["served_event_id"], client_attempt_id: "client-attempt-2", raw: "7", source: "text")
    assert_equal %w[status], reply.keys
    reply = post_json("/diagnosis/answers", served_event_id: step["served_event_id"], client_attempt_id: "client-attempt-3", raw: "  ", source: "text")
    assert_equal %w[message_it status], reply.keys.sort
    assert_equal "invalid", reply["status"]
  end
end
