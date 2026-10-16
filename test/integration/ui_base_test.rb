require "test_helper"

# D-306: the shared components' helpers and the designed refusal pages.
class UiBaseTest < ActionDispatch::IntegrationTest
  include ActionView::Helpers::TagHelper
  include ActionView::Helpers::CaptureHelper
  include ActionView::Helpers::UrlHelper

  test "an unknown path is a designed 404 that says the same to everyone" do
    on(:web, "/nessuna-pagina")
    assert_response :not_found
    assert_select "main#error-page[data-status=not_found] h1", "Questa pagina non c'è"
    assert_select "a.button[href='/']"
  end

  test "a wrong listener gets the same designed 404" do
    on(:api, "/diagnosis")
    assert_response :not_found
    assert_select "main#error-page"
  end

  test "ui_time writes an Italian date in Rome time and never an ISO string" do
    helper = Object.new.extend(UiHelper)
    assert_equal "2 nov 2026, 09:00", helper.ui_time("2026-11-02T09:00:00+01:00")
    assert_equal "2 nov 2026", helper.ui_time("2026-11-02T09:00:00+01:00", time: false)
    assert_equal "", helper.ui_time(nil)
  end

  test "the icons the helpers name are in the sprite" do
    sprite = Rails.root.join("public/vendor/lucide@1.54.0/banco-sprite.svg").read
    (UiHelper::NOTICE_ICONS.values + %w[back empty loading locked not-found]).each { |name| assert_includes sprite, %(id="#{name}") }
  end

  test "the stylesheets use the tokens and no light theme" do
    css = Rails.root.join("app/assets/stylesheets/components.css").read
    %w[--tap --radius-m --shadow-1 --tone-error --focus-ring --dur-1].each { |token| assert_includes css, "var(#{token})" }
    refute_match(/font-size:\s*0?\.[0-8]\d*rem/, css, "no size under 0.9 rem")
  end
end
