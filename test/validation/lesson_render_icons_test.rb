require "test_helper"
require_relative "../support/validation_servers"
require_relative "../support/chrome_helper"
require_relative "../support/lesson_render_world"

# D-335: the render host shoots a page whose icons are drawn. An icon is a <use> of an external sprite that Chrome fetches
# when the icon is first drawn; a shot taken before it arrived showed empty squares at the first viewport (390 px).
class LessonRenderIconsTest < ActiveSupport::TestCase
  include ChromeHelper
  include LessonRenderWorld

  setup { require_chrome! }

  test "at 390 px every icon of the card shown, header and diagram, has drawn its symbol when the host answers ready" do
    body = served("equations")
    revision = store_lesson2!(body)
    token = Validation::Harness.issue("lrev", revision.id)
    script = <<~JS
      (() => {
        const uses = [...document.querySelectorAll("svg use")].filter((u) => u.getClientRects().length > 0 || u.ownerSVGElement.getClientRects().length > 0)
        return JSON.stringify({ total: uses.length, blank: uses.filter((u) => { const b = u.getBBox(); return !(b.width > 0 && b.height > 0) }).map((u) => u.getAttribute("href")) })
      })()
    JS
    found = Validation::ChromeRunner.session do |session|
      session.context do |ctx|
        page = ctx.create_page
        # a sprite that arrives late (a busy machine, a cold disk): every request for a sprite is held back for a second
        page.network.intercept(pattern: "*banco-sprite*")
        page.on(:request) { |request, done| request.url.include?("banco-sprite") ? (sleep 1.2; request.continue) : request.continue }
        page.command("Emulation.setDeviceMetricsOverride", width: 390, height: 844, deviceScaleFactor: 1, mobile: false)
        open_lesson_host(page, Validation::Harness.lesson_page_url(token))
        answer = page.evaluate_async("window.bancoLessonRender.ready.then(arguments[0])", 30)
        assert answer["ok"], answer.inspect
        JSON.parse(page.evaluate(script))
      end
    end
    assert_operator found["total"], :>, 0, "the card shows no icon at all"
    assert_empty found["blank"], "icons not drawn: #{found['blank'].inspect}"
  end
end
