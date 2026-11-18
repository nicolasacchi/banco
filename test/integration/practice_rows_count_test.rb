require "test_helper"
require_relative "../support/multi_user"
require_relative "../support/student_course_world"

# D-363: after a try that is not right on an item with rows (a matching, an ordering) the feedback adds «Giuste: N su M.» (English: «Right: N of M.»),
# from the grading, never which rows; a right answer has no count and nothing else about the reply changes.
class PracticeRowsCountTest < ActionDispatch::IntegrationTest
  include MultiUser
  include StudentCourseWorld

  JSON_HEADERS = { "Content-Type" => "application/json", "Accept" => "application/json" }.freeze
  MATCH = "rows-matching".freeze
  ORDER = "rows-ordering".freeze
  LEFT = (1..6).to_h { |n| [ "l#{n}", "r#{n}" ] }.freeze

  setup do
    build_student_world
    @row = Student.find_by!(key: "student")
    @matching = make_rows_item(MATCH, "matching",
                               display: { left: (1..6).map { |n| { id: "l#{n}", text: "Sinistra #{n}" } }, right: (1..6).map { |n| { id: "r#{n}", text: "Destra #{n}" } } },
                               answer: LEFT)
    @ordering = make_rows_item(ORDER, "ordering", display: { elements: (1..4).map { |n| { id: "e#{n}", text: "Passo #{n}" } } }, answer: %w[e1 e2 e3 e4])
    topic = make_topic(@lesson_revision, { SKILL => [ @matching, @ordering ] }, course: @course)
    approve_topic!(topic)
  end

  def make_rows_item(key, component, display:, answer:)
    item = Item.create!(subject: @subject, key: key, kind: "practice_item")
    body = { schema: "banco.item/1", schema_version: 1, kind: "practice_item", subject: @subject.key, skill: SKILL, component: component, level: 1,
             expected_seconds: 60, hints_it: [], error_catalogue: [] }
    revision = ItemRevision.create!(item: item, seq: 1, body_json: JSON.generate(body), file_sessions_json: "{}")
    ItemValidation.create!(item_revision: revision, seq: 1, status: "passed", codes_json: "[]")
    6.times do |i|
      ItemInstance.create!(item_revision: revision, seed: i + 1, display_json: JSON.generate(display), answer_json: JSON.generate(answer), errors_json: "[]",
                           hints_json: "[]", solution_json: JSON.generate(steps: [ { text_it: "Passo." } ], final: "x"), fingerprint: Digest::SHA256.hexdigest("#{key}-#{i}"))
    end
    revision
  end

  def english! = Diagnosis::Preferences.record(@row, language: "en")

  def post_json(path, body = {})
    on(:web, "/today", headers: OFFICIAL, remote_addr: EDGE)
    token = css_select("meta[name=csrf-token]").first&.[]("content")
    on(:web, path, method: :post, headers: OFFICIAL.merge(JSON_HEADERS, "X-CSRF-Token" => token.to_s), params: body.to_json, remote_addr: EDGE)
    response.parsed_body
  end

  def serve_for(key) = post_json("/practice/serves", { topic: TOPIC, skill: SKILL, item: key })

  # The answer is given with the ids the page showed: each stored id goes back through the serve's shuffle.
  def answer_for(serve, chosen)
    map = JSON.parse(PracticeServe.find(serve["serve_id"]).id_map_json.presence || "{}")
    shown = ->(stored) { map.key(stored) || stored }
    raw = chosen.is_a?(Hash) ? chosen.to_h { |l, r| [ shown.(l), shown.(r) ] } : chosen.map { |id| shown.(id) }
    post_json("/practice/answers", { serve_id: serve["serve_id"], client_attempt_id: SecureRandom.uuid, raw: JSON.generate(raw), source: "button" })
  end

  def four_of_six = LEFT.merge("l5" => "r6", "l6" => "r5")

  test "a matching of six rows with four right says «Giuste: 4 su 6.» and nothing about which rows" do
    reply = answer_for(serve_for(MATCH), four_of_six)
    assert_equal [ "graded", "unrecognised", "Giuste: 4 su 6." ], [ reply["status"], reply["outcome"], reply["count_it"] ]
    assert reply["message_it"].present?, "the existing message stays"
    assert_not_includes reply["message_it"], "Giuste"
    assert_no_match(/\b[lre]\d\b|Sinistra|Destra/, reply.to_json, "no row id or text in the reply")
  end

  test "the second wrong try, the one that opens the solution, also has the count" do
    serve = serve_for(MATCH)
    first = answer_for(serve, four_of_six)
    second = answer_for(serve, LEFT.merge("l1" => "r2", "l2" => "r1", "l3" => "r4", "l4" => "r3"))
    assert_equal "Giuste: 4 su 6.", first["count_it"]
    assert_equal "Giuste: 2 su 6.", second["count_it"]
    assert second["solution"], "the solution comes with the second try"
    assert_equal I18n.t("practice.second_wrong", locale: :it), second["message_it"]
  end

  test "a right answer has no count" do
    reply = answer_for(serve_for(MATCH), LEFT)
    assert_equal "correct", reply["outcome"]
    assert_nil reply["count_it"]
  end

  test "a replayed answer says the same count" do
    serve = serve_for(MATCH)
    map = JSON.parse(PracticeServe.find(serve["serve_id"]).id_map_json.presence || "{}")
    raw = JSON.generate(four_of_six.to_h { |l, r| [ map.key(l) || l, map.key(r) || r ] })
    body = { serve_id: serve["serve_id"], client_attempt_id: SecureRandom.uuid, raw: raw, source: "button" }
    first = post_json("/practice/answers", body)
    again = post_json("/practice/answers", body)
    assert_equal [ "Giuste: 4 su 6.", "Giuste: 4 su 6." ], [ first["count_it"], again["count_it"] ]
  end

  test "an English page says «Right: 4 of 6.»" do
    english!
    reply = answer_for(serve_for(MATCH), four_of_six)
    assert_equal "Right: 4 of 6.", reply["count_it"]
    assert_includes [ I18n.t("practice.unrecognised", locale: :en), I18n.t("practice.unrecognised_no_hint", locale: :en) ], reply["message_it"]
  end

  test "an ordering counts the items in their place" do
    reply = answer_for(serve_for(ORDER), %w[e2 e1 e3 e4])
    assert_equal "Giuste: 2 su 4.", reply["count_it"]
    assert_nil answer_for(serve_for(ORDER), %w[e1 e2 e3 e4])["count_it"]
  end

  test "the engine reads the count from the grading for every kind of try" do
    spec = Grading::Spec.new(component: "matching", subject: "math", answer: LEFT, display: {})
    assert_equal [ 4, 6 ], Practice::Instances.rows_count(spec, { "pairs" => {}, "correct_pairs" => 4 }.to_json)
    assert_nil Practice::Instances.rows_count(spec, "not json")
    assert_nil Practice::Instances.rows_count(Grading::Spec.new(component: "number", subject: "math", answer: "3"), { "correct_pairs" => 1 }.to_json)
    assert_nil Practice::Messages.rows_line(:correct, [ 4, 6 ])
    assert_nil Practice::Messages.rows_line(:contested, [ 4, 6 ])
    assert_nil Practice::Messages.rows_line(:unrecognised, nil)
    assert_equal "Giuste: 0 su 3.", Practice::Messages.rows_line(:unrecognised, [ 0, 3 ])
  end
end
