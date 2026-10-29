require "test_helper"
require_relative "../support/multi_user"
require_relative "../support/student_course_world"
require_relative "../support/student_ui_rows"

# D-321: the student's pages show an item's figure (an asset of the revision) as an image from /assets/items/<sha256>.svg.
class ItemFiguresPagesTest < ActionDispatch::IntegrationTest
  include MultiUser
  include StudentCourseWorld
  include StudentUiRows

  SVG = '<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 10 10"><path d="M0 0L10 10"/></svg>'.freeze
  JSON_HEADERS = { "Content-Type" => "application/json", "Accept" => "application/json" }.freeze

  setup do
    @dir = Dir.mktmpdir
    Rails.application.config.x.item_assets_dir = @dir
    @sha = Digest::SHA256.hexdigest(SVG)
  end

  teardown do
    Rails.application.config.x.item_assets_dir = nil
    FileUtils.rm_rf(@dir)
  end

  def post_json(headers, path, body = {})
    on(:web, "/today", headers: headers, remote_addr: EDGE)
    token = css_select("meta[name=csrf-token]").first&.[]("content")
    on(:web, path, method: :post, headers: headers.merge(JSON_HEADERS, "X-CSRF-Token" => token.to_s), params: body.to_json, remote_addr: EDGE)
    response.parsed_body
  end

  test "the practice page is told the figure, and the image is then served" do
    build_student_world(figure_svg: SVG)
    item = post_json(OFFICIAL, "/practice/serves", { topic: TOPIC, skill: SKILL })["item"]
    assert_equal "/assets/items/#{@sha}.svg", item.dig("figure", "src")
    assert_match(/\AUn triangolo/, item.dig("figure", "alt_it"))
    on(:web, item.dig("figure", "src"), headers: OFFICIAL, remote_addr: EDGE)
    assert_response :success
    assert_equal "image/svg+xml", response.media_type
    assert_equal "nosniff", response.headers["X-Content-Type-Options"]
    assert_equal SVG, response.body
    # the page's shell asks for the item through script: nothing of the figure is inline
    on(:web, "/topics/#{TOPIC}/practice/#{SKILL}", headers: OFFICIAL, remote_addr: EDGE)
    assert_no_match(/#{@sha}/, response.body)
  end

  test "a practice item without a figure is told none" do
    build_student_world
    item = post_json(OFFICIAL, "/practice/serves", { topic: TOPIC, skill: SKILL })["item"]
    assert_not item.key?("figure")
    assert_empty Dir.children(@dir)
  end

  test "the sitting is told the figure of a diagnosis item" do
    rows = build_ui_subject(components: %w[choice], figure_svg: SVG)
    run = DiagnosisRun.create!(student: rows[:student], subject: rows[:subject], blueprint_revision: rows[:blueprint], sequence: 1,
                               seed_salt: "fig", rules_version: Diagnosis::Rules::V1::RULES_VERSION, engine_version: Diagnosis::Engine::VERSION)
    conductor = Diagnosis::Conductor.new(run)
    step = conductor.step!
    payload = JSON.parse(conductor.presentation(step.event, student: rows[:student]).to_json)
    assert_equal "/assets/items/#{@sha}.svg", payload.dig("item", "figure", "src")
    assert_match(/\AUn triangolo con i lati \d\.\z/, payload.dig("item", "figure", "alt_it"))
    assert_equal [ "#{@sha}.svg" ], Dir.children(@dir)
  end
end
