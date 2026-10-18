# frozen_string_literal: true

require "base64"

module Validation
  # The render check of a lesson/2 revision in the server's Chrome (A12.2, D-249). It opens the harness listener's
  # render host (Harness.lesson_page_url, token kind lrev) at each viewport of lesson2.render, asks the page to draw
  # every card (renderAll, then card by card with every "more", step and state shown) and reads what the page found
  # (lesson/render_host.js): exceptions and KaTeX errors (E-LESSON-RENDER), overflow (E-LESSON-OVERFLOW), labels that
  # overlap or sit outside their drawing and layouts that answered an error (E-DIAGRAM-LAYOUT), text under the
  # minimum (E-DIAGRAM-SMALL-TEXT). All errors: they depend on the author's data. Then it takes a WebP shot of each
  # card (core cards at every viewport, extra cards at the first only) and hands the bytes to LessonShots. A card has
  # further states (D-311): every other exercise of «Prova tu» shown in turn, and the card and each exercise with every
  # closed disclosure open; each is measured like the card, and pictured as `shoot?` says.
  #
  # The caller holds the ChromeRunner session. Nothing here judges beyond the findings and does not write the
  # database. Time: a budget per revision and per card-viewport (E-LESSON-RENDER "timeout"); infrastructure
  # trouble (Chrome gone, the host not answering) is raised, never a verdict.
  class LessonRenderRunner
    Result = Struct.new(:status, :errors, :shots, :cards, :viewports, :elapsed, :chrome_version, :exceptions, :timings, keyword_init: true) do
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
      @timings = []
      viewports = (@core + @extra).uniq
      viewports.each do |width, height, theme|
        if over_budget?
          add("E-LESSON-RENDER", nil, "#{width}x#{height}-#{theme}", "timeout: the render of the revision passed #{@budget} s before this viewport")
          break
        end

        run_viewport(width, height, theme.to_s)
      end
      Result.new(status: @errors.empty? ? "passed" : "failed", errors: @errors, shots: @shots, cards: @cards.size, viewports: viewports.map { |w, h, t| "#{w}x#{h}-#{t}" },
                 elapsed: (@clock.call - @started).round(1), chrome_version: @session.version, exceptions: @exceptions, timings: @timings)
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
        opened = []
        cards_for([ width, height, theme ]).each do |card|
          if over_budget?
            add("E-LESSON-RENDER", card["n"], viewport, "timeout: the render of the revision passed #{@budget} s")
            return
          end
          opened.concat(inspect_card(page, card, viewport, width))
        end
        # the opened states once every picture of the viewport is taken (D-311): a part that opens can make a short page scrollable for
        # a moment, and Chrome then paints the fixed bars (their backdrop blur) of the pictures that follow a little differently from
        # one run to the next, so an unchanged card would no longer cost nothing (D-255)
        opened.each do |card, state|
          if over_budget?
            add("E-LESSON-RENDER", card["n"], viewport, "timeout: the render of the revision passed #{@budget} s", nil, state)
            return
          end
          inspect_state(page, card, viewport, width, state)
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

        raise ChromeRunner::Unavailable, "the lesson render host did not define bancoLessonRender" if attempt == LOAD_ATTEMPTS - 1
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

    OPENED = /open\z/

    # A card at one viewport: the card as drawn, then each other exercise of «Prova tu» (D-311), each state with its own time limit.
    # Answers the card's opened states ([card, state]: the card and each exercise with every closed part open), looked at later.
    def inspect_card(page, card, viewport, width)
      answer = inspect_state(page, card, viewport, width, nil) or return []
      opened, shown = Array(answer["states"]).partition { |state| state.match?(OPENED) }
      shown.each do |state|
        if over_budget?
          add("E-LESSON-RENDER", card["n"], viewport, "timeout: the render of the revision passed #{@budget} s", nil, state)
          return []
        end
        inspect_state(page, card, viewport, width, state)
      end
      opened.map { |state| [ card, state ] }
    end

    def inspect_state(page, card, viewport, width, state)
      started = @clock.call
      answer =
        begin
          page.evaluate_async("window.bancoLessonRender.inspect(arguments[0], arguments[1]).then(arguments[2])", @per_card, card["n"], state)
        rescue Ferrum::ScriptTimeoutError, Ferrum::TimeoutError
          add("E-LESSON-RENDER", card["n"], viewport, "timeout: the card took more than #{@per_card} s", nil, state)
          recover(page)
          return nil
        end
      inspected = @clock.call
      fresh = answer["findings"].count { |f| add(f["code"], card["n"], viewport, f["message"], f["where"], state) }
      shot(page, card, viewport, width, answer["height"].to_i, state) if shoot?(card, viewport, state, fresh)
      @timings << timing(card, viewport, started, inspected, @clock.call, state)
      add("E-LESSON-RENDER", card["n"], viewport, "timeout: the card took more than #{@per_card} s", nil, state) if (@clock.call - started) > @per_card * 2
      answer
    end

    # Which states are pictured (the store stays bounded): the card as drawn at every viewport it is drawn at (the cover never);
    # another exercise of «Prova tu» at the first viewport the card is drawn at (the phone); any further state where it found
    # something new, so that what was found can be seen. Otherwise the disclosures opened all at once are measured, not pictured.
    def shoot?(card, viewport, state, fresh)
      return false if card["n"].zero?
      return true if state.nil? || fresh.positive?

      state.match?(/\Aex\d+\z/) && viewport == first_viewport_of(card)
    end

    def first_viewport_of(card)
      width, height, theme = (card["level"] == "core" ? @core : @extra).first
      "#{width}x#{height}-#{theme}"
    end

    # Where the seconds of a card went (the page's own stepping, then the picture): a slow card is told apart from a slow Chrome.
    def timing(card, viewport, started, inspected, finished, state = nil)
      { "card" => card["n"], "state" => state, "viewport" => viewport, "inspect" => (inspected - started).round(2), "shot" => (finished - inspected).round(2) }.compact
    end

    # The whole page as the student has it at that width (the card, the bars, the map), WebP quality 80.
    def shot(page, card, viewport, width, height, state = nil)
      height = height.clamp(200, MAX_SHOT_HEIGHT)
      # The window is made as tall as the page for the picture: the fixed bar of the cards view then sits under the
      # card, as it does when the student has scrolled to the end, and nothing is cut.
      page.command("Emulation.setDeviceMetricsOverride", width: width, height: height, deviceScaleFactor: 1, mobile: false)
      data = page.command("Page.captureScreenshot", format: "webp", quality: 80, clip: { x: 0, y: 0, width: width, height: height, scale: 1 })["data"]
      page.command("Emulation.setDeviceMetricsOverride", width: width, height: viewport_height(viewport), deviceScaleFactor: 1, mobile: false)
      bytes = Base64.decode64(data)
      @shots << { "card" => card["n"], "state" => state, "level" => card["level"], "viewport" => viewport, "sha256" => @store.put(bytes), "bytes" => bytes.bytesize,
                  "width" => width, "height" => height }.compact
    end

    def viewport_height(viewport) = viewport[/\A\d+x(\d+)-/, 1].to_i

    # One error, once: what a further state of the card repeats (the same message about the same thing) stays the first state's.
    # Answers whether the error was new.
    def add(code, card, viewport, message, where = nil, state = nil)
      message = message.to_s.first(300)
      return false if @errors.any? { |e| e["code"] == code && e["card"] == card && e["viewport"] == viewport && e["message"] == message && e["where"] == where }

      @errors << { "code" => code, "card" => card, "state" => state, "viewport" => viewport, "message" => message, "where" => where }.compact
      true
    end
  end
end
