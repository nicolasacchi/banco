require "test_helper"
require "support/chrome_helper"
require "support/validation_servers"
require "support/page_world"

# The validation of a page revision in a real Chrome (D-290, SPEC B7): the sample passes on every seed; each kind of misbehaviour
# gets its code. Skipped without BROWSER_PATH.
class PageRunnerTest < ActiveSupport::TestCase
  include ChromeHelper
  include PageWorld

  setup do
    require_chrome!
    ENV["BANCO_PAGE_SHOTS_DIR"] = Dir.mktmpdir
  end

  teardown do
    FileUtils.rm_rf(ENV.delete("BANCO_PAGE_SHOTS_DIR").to_s)
  end

  # seeds: nil runs all eight; a test of one misbehaviour runs seed 0 (it takes the whole list of steps)
  def run_page(files, scan: true, seeds: [ 0 ])
    revision = store_page!(files, scan: scan)
    Validation::ChromeRunner.session(wait: 900) { |session| Validation::PageRunner.new(session, revision: revision, kit: "1.0", seeds: seeds).call }
  end

  def codes(result) = result.errors.map { |e| e["code"] }.uniq

  test "the sample page passes on all eight seeds with the screenshots and the poster" do
    result = run_page(page_files, seeds: nil)
    assert_equal [], result.errors, "no error"
    assert_equal "passed", result.status
    assert_equal 8, result.seeds.size
    ready = result.shots.select { |s| s["kind"] == "ready" && s["width"] == 1280 }
    assert_equal 8, ready.size
    assert_equal [ 0, 1 ], result.shots.select { |s| s["kind"] == "ready" && s["width"] == 390 }.map { |s| s["seed_index"] }.sort
    session = result.shots.select { |s| s["kind"] == "session" }.group_by { |s| s["seed_index"] }
    assert_equal({ 0 => [ 20, 40, 60 ], 1 => [ 20, 40, 60 ] }, session.transform_values { |list| list.map { |s| s["action"] } })
    assert(result.shots.any? { |s| s["kind"] == "reduced" })
    assert(result.shots.all? { |s| PageShots.exist?(s["sha256"]) })
    assert_equal 8, ready.map { |s| s["seed_index"] }.uniq.size
  end

  test "a page that never calls init is E-PAGE-READY" do
    result = run_page(page_files { |f| f["main.mjs"] = "const x = 1\n" })
    assert_includes codes(result), "E-PAGE-READY"
  end

  test "an uncaught error and a console error are E-PAGE-ERROR" do
    result = run_page(page_files { |f| f["main.mjs"] = %(import { banco } from "banco"\nawait banco.init()\nconsole.error("boom")\nthrow new Error("later")) })
    assert_includes codes(result), "E-PAGE-ERROR"
  end

  test "a network attempt is a CSP violation, E-PAGE-NETWORK" do
    result = run_page(page_files { |f| f["main.mjs"] = %(import { banco } from "banco"\nawait banco.init()\nconst i = document.createElement("canvas")\nwindow.setTimeout?.(1)\nawait Promise.resolve()\ndocument.body.appendChild(i)\nbanco.ready()\n) + %(const img = document.createElement("img")\nimg.setAttribute("src", "http://127.0.0.1:1/x.png")\ndocument.body.appendChild(img)\n) }, scan: false)
    assert_includes codes(result), "E-PAGE-NETWORK"
  end

  test "a stubbed API called is E-PAGE-API" do
    result = run_page(page_files { |f| f["main.mjs"] = %(import { banco } from "banco"\nawait banco.init()\ntry { new RTCPeerConnection() } catch (e) {}\nbanco.ready()\n) }, scan: false)
    assert_includes codes(result), "E-PAGE-API"
  end

  test "a page that navigates its frame is E-PAGE-NAVIGATION" do
    result = run_page(page_files { |f| f["main.mjs"] = %(import { banco } from "banco"\nawait banco.init()\nbanco.ready()\nsetTimeout(() => { document.location = "about:blank#x" }, 100)\n) }, scan: false)
    assert_includes codes(result), "E-PAGE-NAVIGATION"
  end

  test "a slider without a name and a canvas without an alternative are E-PAGE-A11Y" do
    result = run_page(page_files { |f| f["main.mjs"] = %(import { banco } from "banco"\nawait banco.init()\nconst root = document.getElementById("app")\nconst c = document.createElement("canvas")\nconst s = document.createElement("input")\ns.type = "range"\nroot.append(c, s)\nbanco.ready()\n) })
    assert_includes codes(result), "E-PAGE-A11Y"
  end

  test "motion under reduced motion is E-PAGE-MOTION" do
    main = <<~JS
      import { banco } from "banco"
      await banco.init()
      const root = document.getElementById("app")
      const box = document.createElement("div")
      box.setAttribute("role", "img")
      box.setAttribute("aria-label", "Un quadrato che si muove sempre")
      box.style.cssText = "width:40px;height:40px;background:#000;position:relative"
      root.append(box)
      banco.ready()
      const tick = () => { box.style.left = `${(performance.now() / 4) % 300}px`; requestAnimationFrame(tick) }
      tick()
    JS
    result = run_page(page_files { |f| f["main.mjs"] = main }, scan: false)
    assert_includes codes(result), "E-PAGE-MOTION"
    assert(result.warnings.any? { |w| w["code"] == "W-PAGE-IDLE-LOOP" })
  end

  # The frame is sized by a message the page sends when its body changes; on a loaded host the message can come after the first screenshot.
  # A frame that grows once, late, is layout settling (found on a loaded CI runner as a false E-PAGE-MOTION); pixels that change at a
  # steady size stay motion (the test above).
  LATE_GROWTH = <<~JS
    import { banco } from "banco"
    await banco.init()
    const root = document.getElementById("app")
    const note = document.createElement("p")
    note.textContent = "Una pagina ferma che si allunga una volta, in ritardo."
    root.append(note)
    banco.ready()
    window.setTimeout(() => {
      const more = document.createElement("p")
      more.style.cssText = "height:400px;margin:0"
      more.textContent = "Altro testo"
      root.append(more)
      banco.resize()
    }, 1700)
  JS

  test "a frame that grows once, late, is not motion" do
    result = run_page(page_files { |f| f["main.mjs"] = LATE_GROWTH }, scan: false)
    assert_not_includes codes(result), "E-PAGE-MOTION"
  end
end
