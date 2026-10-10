# frozen_string_literal: true

require "base64"

module Validation
  # The render check of a lesson/2 revision in the server's Chrome (A12.2, D-249). It opens the harness listener's
  # render host (Harness.lesson_page_url, token kind lrev) at each viewport of lesson2.render, asks the page to draw
  # every card (renderAll, then card by card with every "more", step and state shown) and reads what the page found
  # (lesson/render_host.js): exceptions and KaTeX errors (E-LESSON-RENDER), overflow (E-LESSON-OVERFLOW), labels that
  # overlap or sit outside their drawing and layouts that answered an error (E-DIAGRAM-LAYOUT), text under the
  # minimum (E-DIAGRAM-SMALL-TEXT). All errors: they depend on the author's data. Then it takes a WebP shot of each
  # card (core cards at every viewport, extra cards at the first only) and hands the bytes to LessonShots.
  #
  # The caller holds the ChromeRunner session. Nothing here judges beyond the findings and does not write the
  # database. Time: a budget per revision and per card-viewport (E-LESSON-RENDER "timeout"); infrastructure
  # trouble (Chrome gone, the host not answering) is raised, never a verdict.
  class LessonRenderRunner
    Result = Struct.new(:status, :errors, :shots, :cards, :viewports, :elapsed, :chrome_version, :exceptions, keyword_init: true) do
      def passed? = status == "passed"
    end

    DEFINED_WAIT = 20
    LOAD_ATTEMPTS = 3
    READY_WAIT = 30
    MAX_SHOT_HEIGHT = 9000

    def initialize(session, body:, token:, store: LessonShots, clock: -> { Process.clock_gettime(Process::CLOCK_MONOTONIC) })
      @session = session
      @cards = body.fetch("cards")
      @token = token
      @store = store
      @clock = clock
      @core = Rules.get(:lesson2, :render, :core_viewports)
      @extra = Rules.get(:lesson2, :render, :extra_viewports)
      @budget = Rules.get(:lesson2, :render, :budget_seconds)
      @per_card = Rules.get(:lesson2, :render, :card_viewport_seconds)
    end

    def call
      @started = @clock.call
      @errors = []
      @shots = []
      @exceptions = []
      viewports = (@core + @extra).uniq
      viewports.each do |width, height, theme|
        if over_budget?
          add("E-LESSON-RENDER", nil, "#{width}x#{height}-#{theme}", "timeout: the render of the revision passed #{@budget} s before this viewport")
          break
        end

        run_viewport(width, height, theme.to_s)
      end
      Result.new(status: @errors.empty? ? "passed" : "failed", errors: @errors, shots: @shots, cards: @cards.size, viewports: viewports.map { |w, h, t| "#{w}x#{h}-#{t}" },
                 elapsed: (@clock.call - @started).round(1), chrome_version: @session.version, exceptions: @exceptions)
    end

    private

    def over_budget? = (@clock.call - @started) > @budget

    # The cards drawn at this viewport: the cover (looked at, not shot), the core cards, the extra cards when the
    # viewport is listed for them.
    def cards_for(viewport)
      extra = @extra.any? { |w, h, t| [ w, h, t.to_s ] == viewport }
      [ { "n" => 0, "level" => "cover" } ] + @cards.select { |c| c["level"] == "core" || extra }
    end

    def run_viewport(width, height, theme)
      viewport = "#{width}x#{height}-#{theme}"
      @session.context do |ctx|
        page = open(ctx, width, height, theme)
        ready = wait_ready(page)
        unless ready && ready["ok"]
          add("E-LESSON-RENDER", nil, viewport, "the lesson did not draw: #{ready ? ready['error'] : 'the page did not answer'}")
          return
        end
        ready["exceptions"].each { |m| add("E-LESSON-RENDER", nil, viewport, "exception: #{m}") }
        cards_for([ width, height, theme ]).each do |card|
          if over_budget?
            add("E-LESSON-RENDER", card["n"], viewport, "timeout: the render of the revision passed #{@budget} s")
            return
          end
          inspect_card(page, card, viewport, width)
        end
        check_print(page, viewport) if viewport == first_viewport
      end
    end

    def first_viewport
      width, height, theme = @core.first
      "#{width}x#{height}-#{theme}"
    end

    # "Stampa riassunto e schema" must fit one A4 page (A10): the summary card alone under print media, printed to a PDF
    # by Chrome, whose pages are counted. Print does not depend on the window, so it is done once.
    def check_print(page, viewport)
      page.command("Emulation.setEmulatedMedia", media: "print")
      state = page.evaluate_async("window.bancoLessonRender.printSummary().then(arguments[0])", @per_card)
      return if state.nil? || state["skipped"]

      pdf = page.command("Page.printToPDF", paperWidth: 8.27, paperHeight: 11.69, printBackground: true, marginTop: 0.4, marginBottom: 0.4, marginLeft: 0.4, marginRight: 0.4)["data"]
      pages = Base64.decode64(pdf).scan(%r{/Type\s*/Page(?![A-Za-z])}).size
      add("E-LESSON-RENDER", state["n"], viewport, "Stampa riassunto e schema takes #{pages} pages: the summary card and its schema must fit one A4 page", "print") if pages > 1
    rescue Ferrum::ScriptTimeoutError, Ferrum::TimeoutError
      add("E-LESSON-RENDER", nil, viewport, "timeout: the print check took more than #{@per_card} s", "print")
    ensure
      page.command("Emulation.setEmulatedMedia", media: "") rescue nil
    end

    def open(ctx, width, height, theme)
      page = ctx.create_page
      page.command("Emulation.setDeviceMetricsOverride", width: width, height: height, deviceScaleFactor: 1, mobile: false)
      url = @page_url = Harness.lesson_page_url(@token, theme: theme)
      LOAD_ATTEMPTS.times do |attempt|
        page.go_to(url)
        break if defined_in?(page)

        raise ChromeRunner::Unavailable, "the lesson render host did not define bancoLessonRender" if attempt == ChromeRunner::LOAD_ATTEMPTS - 1
      end
      page
    end

    # A card that never answered leaves the page busy: load it again so the next card has a clean one.
    def recover(page)
      page.go_to(@page_url)
      wait_ready(page)
    rescue Ferrum::Error
      nil
    end

    def defined_in?(page)
      deadline = @clock.call + DEFINED_WAIT
      loop do
        return true if page.evaluate("typeof window.bancoLessonRender !== 'undefined'")
        return false if @clock.call >= deadline

        sleep 0.25
      end
    end

    def wait_ready(page)
      page.evaluate_async("window.bancoLessonRender.ready.then(arguments[0])", READY_WAIT)
    rescue Ferrum::ScriptTimeoutError, Ferrum::TimeoutError
      nil
    end

    def inspect_card(page, card, viewport, width)
      started = @clock.call
      answer =
        begin
          page.evaluate_async("window.bancoLessonRender.inspect(arguments[0]).then(arguments[1])", @per_card, card["n"])
        rescue Ferrum::ScriptTimeoutError, Ferrum::TimeoutError
          add("E-LESSON-RENDER", card["n"], viewport, "timeout: the card took more than #{@per_card} s")
          recover(page)
          return
        end
      answer["findings"].each { |f| add(f["code"], card["n"], viewport, f["message"], f["where"]) }
      return if card["n"].zero?

      shot(page, card, viewport, width, answer["height"].to_i)
      add("E-LESSON-RENDER", card["n"], viewport, "timeout: the card took more than #{@per_card} s") if (@clock.call - started) > @per_card * 2
    end

    # The whole page as the student has it at that width (the card, the bars, the map), WebP quality 80.
    def shot(page, card, viewport, width, height)
      height = height.clamp(200, MAX_SHOT_HEIGHT)
      # The window is made as tall as the page for the picture: the fixed bar of the cards view then sits under the
      # card, as it does when the student has scrolled to the end, and nothing is cut.
      page.command("Emulation.setDeviceMetricsOverride", width: width, height: height, deviceScaleFactor: 1, mobile: false)
      data = page.command("Page.captureScreenshot", format: "webp", quality: 80, clip: { x: 0, y: 0, width: width, height: height, scale: 1 })["data"]
      page.command("Emulation.setDeviceMetricsOverride", width: width, height: viewport_height(viewport), deviceScaleFactor: 1, mobile: false)
      bytes = Base64.decode64(data)
      @shots << { "card" => card["n"], "level" => card["level"], "viewport" => viewport, "sha256" => @store.put(bytes), "bytes" => bytes.bytesize,
                  "width" => width, "height" => height }
    end

    def viewport_height(viewport) = viewport[/\A\d+x(\d+)-/, 1].to_i

    def add(code, card, viewport, message, where = nil)
      return if @errors.any? { |e| e["code"] == code && e["card"] == card && e["viewport"] == viewport && e["message"] == message }

      @errors << { "code" => code, "card" => card, "viewport" => viewport, "message" => message.to_s.first(300), "where" => where }.compact
    end
  end
end
