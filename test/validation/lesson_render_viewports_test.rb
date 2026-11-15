require "test_helper"
require "net/http"
require_relative "../support/validation_servers"
require_relative "../support/chrome_helper"
require_relative "../support/lesson_render_world"

# D-335: a lesson render that failed with `timeout: the render of the revision passed 90 s` at card 0 of 1280x800-dark (lesson revisions 1201, 1203,
# 1223, 1245, spanish and english: a hero figure, `[[es:..]]` spans, a dialogue) did not hang at the dark theme. Every card of every viewport took
# well under a second; what took the seconds was the load of the page (and its readiness) three times over, in a Chrome context of its own each time:
# 176 requests to the harness listener, whose five Puma threads are shared with the API, so that a busy API put each load in a queue and the dark
# viewport, the last, met the budget. Now the viewports share one browser context (its HTTP cache serves the second and third load), the host page
# preloads no module it does not import, and what the host waits for before its first card is bounded and named.
class LessonRenderViewportsTest < ActiveSupport::TestCase
  include ChromeHelper
  include LessonRenderWorld

  MD = <<~MD
    ---
    schema: banco.lesson/2
    key: ripasso.spanish.render-viewports
    kind: ripasso
    subject: spanish
    title_it: "I generi letterari"
    goals_it:
      - "**Conoscere** i generi letterari"
    skills: [spanish.render-viewports]
    refs:
      - {source: gallery-2026, line: 1, fragment: "generi", role: taught_in}
    scope: studied
    minutes: 20
    calculator: false
    why_it: "Per parlare di un libro in spagnolo. Il contenuto è inventato."
    hero:
      type: concept_map
      alt_it: "Il libro e i tre generi letterari: narrativa, poesia e teatro."
      root: r
      nodes:
        - {id: r, text_it: "[[es:Géneros literarios]]"}
        - {id: a, text_it: "[[es:Narrativa]]"}
        - {id: b, text_it: "[[es:Poesía]]"}
        - {id: c, text_it: "[[es:Teatro]]"}
      edges:
        - {from: r, to: a}
        - {from: r, to: b}
        - {from: r, to: c}
    ---

    ## I libri hanno tre generi {idea short="I generi" icon=book-open}

    La [[es:novela]] è un racconto lungo. Il [[es:cuento]] è un racconto breve. Il [[es:poema]] usa i versi.

    ::: schema concept_map
    alt_it: "I tre generi letterari. Narrativa: novela, cuento. Poesía: poema. Teatro: comedia."
    root: r
    nodes:
      - {id: r, text_it: "[[es:Géneros literarios]]"}
      - {id: a, text_it: "[[es:Narrativa]]"}
      - {id: b, text_it: "[[es:Poesía]]"}
      - {id: c, text_it: "[[es:Teatro]]"}
      - {id: a1, text_it: "[[es:la novela]]"}
      - {id: a2, text_it: "[[es:el cuento]]"}
      - {id: b1, text_it: "[[es:el poema]]"}
      - {id: c1, text_it: "[[es:la comedia]]"}
    edges:
      - {from: r, to: a}
      - {from: r, to: b}
      - {from: r, to: c}
      - {from: a, to: a1}
      - {from: a, to: a2}
      - {from: b, to: b1}
      - {from: c, to: c1}
    :::

    ## Due amici parlano di un libro {idea short="Dialogo" icon=message-square}

    ::: dialogue
    title_it: "Ascolta Ana e Luis"
    speakers:
      - {id: a, name: "Ana", voice: 1}
      - {id: l, name: "Luis", voice: 2}
    transcript: shown
    lines:
      - {speaker: a, text_es: "¿Es una novela o un cuento?", gloss_it: "È un romanzo o un racconto?"}
      - {speaker: l, text_es: "Es un cuento, es muy corto.", gloss_it: "È un racconto, è molto breve."}
      - {speaker: a, text_es: "Gracias. ¿Y el poema?", gloss_it: "Grazie. E il poema?"}
    :::

    La [[es:obra de teatro]] si recita: [[es:la comedia]] ha un finale lieto.
  MD

  def revision!
    findings = Validation::Findings.new
    body = Lessons::Parser2.call(MD, findings, allow_reserved: true).body
    assert_empty findings.errors.map(&:to_h)
    store_lesson2!(body)
  end

  test "a lesson with a hero figure, language spans and a dialogue renders through 1280x800-dark inside the budget, the page loaded once for its files" do
    require_chrome!
    shots = Dir.mktmpdir("lesson-shots")
    ENV["BANCO_LESSON_SHOTS_DIR"] = shots
    revision = revision!
    Validation::LessonRenderCheck.new(revision).call
    row = LessonRender.where(lesson_revision_id: revision.id).order(:id).last
    assert_equal "passed", row.status, row.result["errors"].map { |e| "#{e['code']} card #{e['card']} #{e['viewport']}: #{e['message']}" }.join("\n")
    assert_equal %w[390x844-cream 1280x800-cream 1280x800-dark], row.result["viewports"]
    assert_equal row.result["viewports"], row.shots.map { |s| s["viewport"] }.uniq, "a picture at every viewport, the dark one too"
    # the cover carries the hero figure: pictured at every viewport, the phone first, its file in the store (D-335)
    covers = row.shots.select { |s| s["card"] == 0 }
    assert_equal row.result["viewports"], covers.map { |s| s["viewport"] }, "the cover pictured at every viewport"
    assert_equal [ "cover" ], covers.map { |s| s["level"] }.uniq
    phone = covers.find { |s| s["viewport"] == "390x844-cream" }
    assert_equal 390, phone["width"]
    assert File.exist?(LessonShots.path(phone["sha256"])), "the phone cover's image is stored"
    assert_equal "WEBP", LessonShots.read(phone["sha256"])[8, 4]
    budget = Validation::Rules.get(:lesson2, :render, :budget_seconds)
    assert_operator row.result["elapsed_seconds"], :<, budget / 3.0, "the render took #{row.result['elapsed_seconds']} s"
    # where the seconds before the first card went is in the result, per viewport (open: the page's load; ready: the host's own wait)
    loads = row.result["loads"]
    assert_equal row.result["viewports"], loads.map { |l| l["viewport"] }
    loads.each { |l| assert_operator l["open"] + l["ready"], :<, 10, "the load of #{l['viewport']}: #{l.inspect}" }
  ensure
    ENV.delete("BANCO_LESSON_SHOTS_DIR")
    FileUtils.rm_rf(shots) if shots
  end

  test "the host page preloads no module and the pages of one render share a browser context's cache" do
    require_chrome!
    revision = revision!
    token = Validation::Harness.issue("lrev", revision.id)
    html = Net::HTTP.get(URI(Validation::Harness.lesson_page_url(token, theme: "dark")))
    assert_includes html, 'type="importmap"'
    assert_includes html, 'import "lesson/render_host"'
    assert_no_match(/modulepreload/, html, "a preload of the student's whole importmap is a request per Stimulus controller and item template")
    fetched = Validation::ChromeRunner.session do |session|
      session.context do |ctx|
        %w[cream dark].map do |theme|
          page = ctx.create_page
          page.go_to(Validation::Harness.lesson_page_url(token, theme: theme))
          assert page.evaluate_async("window.bancoLessonRender.ready.then((r) => arguments[0](r.ok))", 30)
          count = page.evaluate("performance.getEntriesByType('resource').filter((r) => r.transferSize > 0).length")
          page.close
          count
        end
      end
    end
    assert_operator fetched.first, :>, 10, "the first page fetches its files"
    assert_equal 0, fetched.last, "the second page of the same context asks the listener for none of them"
  end

  test "a wait of the host that never ends answers by name instead of leaving the page unanswered" do
    require_chrome!
    revision = revision!
    token = Validation::Harness.issue("lrev", revision.id)
    answer = Validation::ChromeRunner.session do |session|
      session.context do |ctx|
        page = ctx.create_page
        # every font file is asked for and never delivered (the listener is busy): the host must give up on its own
        page.network.intercept(pattern: "*.woff2")
        page.on(:request) do |request, _done|
          if request.url.include?(".woff2")
            Thread.new { sleep 30; request.abort rescue nil }
          else
            request.continue
          end
        end
        page.go_to("#{Validation::Harness.lesson_page_url(token)}&ready_ms=2000")
        page.evaluate_async("window.bancoLessonRender.ready.then(arguments[0])", 20)
      end
    end
    assert_equal false, answer["ok"]
    assert_match(/waited more than 2 s for the fonts/, answer["error"])
  end

  test "the runner draws its three viewports in one browser context" do
    require_chrome!
    shots = Dir.mktmpdir("lesson-shots")
    ENV["BANCO_LESSON_SHOTS_DIR"] = shots
    revision = revision!
    contexts = 0
    result = Validation::ChromeRunner.session do |session|
      session.define_singleton_method(:context) { |&block| contexts += 1; super(&block) }
      Validation::LessonRenderRunner.new(session, body: revision.body, token: Validation::Harness.issue("lrev", revision.id)).call
    end
    assert_equal 1, contexts
    assert_equal 3, result.loads.size
  ensure
    ENV.delete("BANCO_LESSON_SHOTS_DIR")
    FileUtils.rm_rf(shots) if shots
  end
end
