# frozen_string_literal: true

require "base64"

module Validation
  # The shots of an item revision in the server's Chrome (D-336), as the student's phone shows it. It opens the harness listener's item render host
  # (Harness.item_page_url, token kind irev) once for each stored instance of the revision, in one browser context (the pages share its HTTP cache:
  # the CSS, the fonts, the modules), at the phone's viewport of item_render.viewport (390 x 844, cream, device scale 1: a shot is 390 CSS px wide),
  # waits for the page to draw the unanswered instance and to measure itself (items/render_host.js: overflow, exceptions and console errors, a KaTeX
  # error, markup printed as text, a figure that did not draw), and takes a WebP shot of the WHOLE instance: the window is made as tall as the page for
  # the picture, so nothing is cut and the sticky action bar sits under the item as it does when the student has scrolled to the end. The bytes go to
  # the shots store (LessonShots, by content). Each shot says its instance, the seed of its shuffle and the shown order of its choices (stored ids in the
  # order drawn), so the solver can map a position to a stored id. A bilingual item (D-402) is pictured a second time for its first
  # item_render.translation_instances instances (every instance up to max_instances since D-408) with the Italian translation open (`?tr=1`): that shot says
  # `state: "tr"`, the others no state. An instance whose passage has an Italian text (it is withheld until the answer) is pictured a third time as the student
  # sees it after the answer, with the passage's Italian added and the translation open (`?tr=1&answered=1`, `state: "answered"`, D-408).
  #
  # The caller holds the ChromeRunner session. Nothing here judges: the findings are an aid for the reviewer and never a gate; nothing writes the database.
  # Time: a budget per revision and per instance (E-ITEM-RENDER "timeout:"); infrastructure trouble (Chrome gone, the host not answering) is raised.
  class ItemRenderRunner
    Result = Struct.new(:status, :errors, :shots, :instances, :total, :viewport, :elapsed, :chrome_version, :timings, keyword_init: true) do
      def passed? = status == "passed"

      # Failed only because time ran out: the same item can be drawn when Chrome is less busy, so ItemRenderCheck draws it once more.
      def timeout_only?
        status == "failed" && errors.any? && errors.all? { |e| e["code"] == "E-ITEM-RENDER" && e["message"].to_s.start_with?("timeout:") }
      end
    end

    DEFINED_WAIT = LessonRenderRunner::DEFINED_WAIT
    LOAD_ATTEMPTS = LessonRenderRunner::LOAD_ATTEMPTS

    def initialize(session, revision:, token:, store: LessonShots, clock: -> { Process.clock_gettime(Process::CLOCK_MONOTONIC) })
      @session = session
      @revision = revision
      @token = token
      @store = store
      @clock = clock
      @width, @height, @theme = Rules.get(:item_render, :viewport)
      @max = Rules.get(:item_render, :max_instances)
      @budget = Rules.get(:item_render, :budget_seconds)
      @per_instance = Rules.get(:item_render, :instance_seconds)
      @max_shot_height = Rules.get(:item_render, :max_shot_height)
      @translation_instances = Rules.get(:item_render, :translation_instances).to_i
    end

    def viewport = "#{@width}x#{@height}-#{@theme}"

    def call
      @started = @clock.call
      @errors = []
      @shots = []
      @timings = []
      total = Items::ShotPresentation.instances(@revision).count
      rows = Items::ShotPresentation.instances(@revision).limit(@max).to_a
      @translation = Items::ShotPresentation.translation?(@revision)
      add(nil, "the item has #{total} instances: the first #{rows.size} are pictured", "instances", code: "E-ITEM-RENDER", level: "note") if total > rows.size
      @session.context do |ctx|
        page = ctx.create_page
        begin
          page.command("Emulation.setDeviceMetricsOverride", width: @width, height: @height, deviceScaleFactor: 1, mobile: false)
          rows.each_with_index do |row, i|
            number = i + 1
            if over_budget?
              add(number, "timeout: the render of the revision passed #{@budget} s before this instance", viewport)
              break
            end
            draw(page, row, number)
            draw(page, row, number, translation: true) if @translation && number <= @translation_instances
            draw(page, row, number, translation: true, answered: true) if @translation && number <= @translation_instances && passage_italian?(row)
          end
        ensure
          (page.close rescue nil)
        end
      end
      Result.new(status: @errors.reject { |e| e["level"] == "note" }.empty? ? "passed" : "failed", errors: @errors, shots: @shots, instances: rows.size, total: total, viewport: viewport,
                 elapsed: (@clock.call - @started).round(1), chrome_version: @session.version, timings: @timings)
    end

    private

    def over_budget? = (@clock.call - @started) > @budget

    # Does the instance's passage have an Italian text (a bilingual reading text: the student reads it only after the answer)?
    def passage_italian?(row) = Practice::Payload.passage(row).key?(:passage_it)

    # One picture of one instance: as drawn, or (translation: true) the same instance again with the Italian translation open, which the host
    # measures too (overflow with the translation shown, a text with no translation unit: the same findings, each said once), or (answered: true, with
    # the translation open) as it is after the answer, with the passage's Italian under the passage.
    def draw(page, row, number, translation: false, answered: false)
      started = @clock.call
      url = Harness.item_page_url(@token, number, theme: @theme, translation: translation, answered: answered)
      LOAD_ATTEMPTS.times do |attempt|
        page.go_to(url)
        break if defined_in?(page)

        raise ChromeRunner::Unavailable, "the item render host did not define bancoItemRender: #{self.class.describe(page)}" if attempt == LOAD_ATTEMPTS - 1
      end
      loaded = @clock.call
      answer = begin
        page.evaluate_async("window.bancoItemRender.ready.then(arguments[0])", @per_instance)
      rescue Ferrum::ScriptTimeoutError, Ferrum::TimeoutError
        add(number, "timeout: the instance took more than #{@per_instance} s to draw#{answered ? ' as answered' : (' with the translation open' if translation)}", viewport)
        return
      end
      add(number, "the item did not draw: #{answer['error']}", viewport) unless answer["ok"]
      Array(answer["exceptions"]).each { |m| add(number, "exception: #{m}", viewport) }
      Array(answer["findings"]).each { |f| add(number, f["message"], f["where"], code: f["code"]) }
      state = answered ? Items::ShotPresentation::ANSWERED_STATE : (Items::ShotPresentation::TRANSLATION_STATE if translation)
      shoot(page, row, number, answer["height"].to_i, state: state)
      @timings << { "instance" => number, "draw" => (loaded - started).round(2), "ready" => (@clock.call - loaded).round(2) }.tap { |t| t["state"] = state if state }
    end

    def defined_in?(page) = self.class.wait_defined(page, DEFINED_WAIT, @clock)

    # Waits (the module script of the host runs after the load event when its files are slow) until the host's global exists.
    def self.wait_defined(page, seconds, clock = -> { Process.clock_gettime(Process::CLOCK_MONOTONIC) })
      deadline = clock.call + seconds
      loop do
        return true if page.evaluate("typeof window.bancoItemRender !== 'undefined'")
        return false if clock.call >= deadline

        sleep 0.25
      end
    end

    # What the page showed, for the error of a host that never defined its global: the address, the title, the start of the text, the scripts it
    # holds and the errors its console and its loads gave (the host's own listeners are not there yet, so the page is asked for what it has).
    def self.describe(page)
      info = page.evaluate(<<~JS)
        JSON.stringify({ url: location.href.replace(/\\/h\\/[^/]+\\//, "/h/TOKEN/"), title: document.title, text: (document.body?.innerText || "").slice(0, 120),
                         scripts: [...document.scripts].map((s) => s.src || "inline").slice(0, 5),
                         failed: performance.getEntriesByType("resource").filter((e) => e.responseStatus >= 400 || (e.transferSize === 0 && e.decodedBodySize === 0 && e.duration > 0 && e.initiatorType === "script")).map((e) => e.name).slice(0, 5) })
      JS
      info.to_s.first(600)
    rescue StandardError => e
      "(the page could not be asked: #{e.class})"
    end

    # The whole instance, WebP quality 80 at device scale 1 (width = CSS px). The window is made as tall as the page; a layout that moves with the
    # window's height (a viewport unit) is measured again once, so the picture is of the page as it stands in that window.
    def shoot(page, row, number, height, state: nil)
      height = measured(page, height)
      page.command("Emulation.setDeviceMetricsOverride", width: @width, height: height.clamp(200, @max_shot_height), deviceScaleFactor: 1, mobile: false)
      settled = page.evaluate("window.bancoItemRender.measure()").to_i
      if settled != height && settled.positive?
        height = settled
        page.command("Emulation.setDeviceMetricsOverride", width: @width, height: height.clamp(200, @max_shot_height), deviceScaleFactor: 1, mobile: false)
      end
      if height > @max_shot_height
        add(number, "the instance is #{height} px tall; the picture is cut at #{@max_shot_height} px", viewport, level: "note")
        height = @max_shot_height
      end
      height = height.clamp(200, @max_shot_height)
      data = page.command("Page.captureScreenshot", format: "webp", quality: 80, clip: { x: 0, y: 0, width: @width, height: height, scale: 1 })["data"]
      bytes = Base64.decode64(data)
      meta = Items::ShotPresentation.meta(Items::ShotPresentation.call(@revision, row, number), state: state)
      @shots << meta.merge("viewport" => viewport, "width" => @width, "height" => height, "scale" => 1, "sha256" => @store.put(bytes), "bytes" => bytes.bytesize)
      # back to the phone's window for the next instance
      page.command("Emulation.setDeviceMetricsOverride", width: @width, height: @height, deviceScaleFactor: 1, mobile: false)
    end

    def measured(page, height) = height.positive? ? height : page.evaluate("window.bancoItemRender.measure()").to_i

    # One finding, once per instance. A note (level "note") says something the reviewer should know and is no finding.
    def add(number, message, where = nil, code: "E-ITEM-RENDER", level: nil)
      message = message.to_s.first(300)
      return false if @errors.any? { |e| e["code"] == code && e["instance"] == number && e["message"] == message && e["where"] == where }

      @errors << { "code" => code, "instance" => number, "level" => level, "message" => message, "where" => where }.compact
      true
    end
  end
end
