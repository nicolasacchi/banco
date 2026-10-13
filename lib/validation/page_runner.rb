# frozen_string_literal: true

require "base64"

module Validation
  # The validation of a page revision in the server's Chrome (D-290, SPEC B7). The host page (lib/harness/page_host.mjs, token
  # kind prev) embeds the page's shell from the validation mount of the pages app (Host: banco-pages-internal) with the production
  # iframe attributes and plays the parent side of the bridge. Every one of the eight seeds is loaded: ready, errors, network and
  # the ready screenshots; seeds 0 and 1 (page.validate.full_seeds) run the whole list: narrow shot, determinism, axe and the
  # controls, reduced motion, no WebGL, and a scripted session of 60 actions with a visibility cycle and a resize.
  #
  # The caller holds the ChromeRunner session. Nothing here judges beyond the findings and nothing writes the database.
  # Infrastructure trouble (Chrome gone, the host not answering) is raised, never a verdict.
  class PageRunner
    Result = Struct.new(:status, :errors, :warnings, :shots, :seeds, :elapsed, :chrome_version, :resources, keyword_init: true) do
      def passed? = status == "passed"
    end

    DEFINED_WAIT = 20
    LOAD_ATTEMPTS = 3
    KEYS = {
      "Tab" => { key: "Tab", code: "Tab", vk: 9 }, "Enter" => { key: "Enter", code: "Enter", vk: 13, text: "\r" }, "Space" => { key: " ", code: "Space", vk: 32, text: " " },
      "Home" => { key: "Home", code: "Home", vk: 36 }, "End" => { key: "End", code: "End", vk: 35 },
      "ArrowRight" => { key: "ArrowRight", code: "ArrowRight", vk: 39 }, "ArrowLeft" => { key: "ArrowLeft", code: "ArrowLeft", vk: 37 }
    }.freeze
    SHELL_PATH = ->(sha, kit) { "/p/#{sha}/k#{kit}/" }

    # seeds: the indices of Pages::SEEDS to run (all eight in production; a test of one misbehaviour runs seed 0)
    def initialize(session, revision:, kit:, seeds: nil, store: PageShots, clock: -> { Process.clock_gettime(Process::CLOCK_MONOTONIC) })
      @session = session
      @revision = revision
      @manifest = revision.manifest
      @kit = kit
      @store = store
      @clock = clock
      @indices = seeds || (0...Pages::SEEDS.size).to_a
      @rule = Rules.get(:page, :validate)
      @errors = []
      @warnings = []
      @shots = []
      @seed_log = []
      @resources = []
    end

    def call
      @started = @clock.call
      @indices.each do |index|
        seed = Pages::SEEDS.fetch(index)
        if over_budget?
          add("E-PAGE-READY", index, "timeout", "the validation of the revision passed #{@rule['budget_seconds']} s before this seed")
          break
        end
        run_seed(index, seed, full: @rule["full_seeds"].include?(index))
      end
      Result.new(status: @errors.empty? ? "passed" : "failed", errors: @errors, warnings: @warnings, shots: @shots, seeds: @seed_log, elapsed: (@clock.call - @started).round(1),
                 chrome_version: @session.version, resources: @resources.uniq.first(60))
    end

    private

    def over_budget? = (@clock.call - @started) > @rule["budget_seconds"]
    def wide = @rule.dig("viewports", "wide")
    def narrow = @rule.dig("viewports", "narrow")

    # ---- one seed ---------------------------------------------------------------------------------------------------------
    def run_seed(index, seed, full:)
      @session.context do |ctx|
        page = open(ctx, seed, wide)
        ready = wait_ready(page, index, "ready")
        @seed_log << { "seed_index" => index, "seed" => seed, "ready_ms" => ready&.fetch("ms", nil) }
        return unless ready

        settle(page)
        first_png = png(page)
        shot(page, "ready", index, wide.first)
        collect(page, index, "ready")
        check_resources(page, index)
        next unless full

        full_run(ctx, page, index, seed, first_png)
      end
    end

    def full_run(ctx, page, index, seed, first_png)
      narrow_shot(page, index)
      determinism(ctx, index, seed, first_png)
      a11y(page, index)
      reduced_motion(ctx, index, seed)
      no_webgl(ctx, index, seed) if @manifest["webgl"]
      scripted_session(ctx, index, seed)
    end

    # ---- loading ---------------------------------------------------------------------------------------------------------
    def open(ctx, seed, viewport, reduced: false, nowebgl: false, theme: "cream", throttle: true)
      page = ctx.create_page
      page.command("Emulation.setDeviceMetricsOverride", width: viewport.first, height: viewport.last, deviceScaleFactor: 1, mobile: false)
      page.command("Emulation.setCPUThrottlingRate", rate: @rule["throttle"]) if throttle
      page.command("Emulation.setEmulatedMedia", features: [ { name: "prefers-reduced-motion", value: reduced ? "reduce" : "no-preference" } ])
      url = Harness.page_host_url(Harness.issue("prev", @revision.id), seed: seed, kit: @kit, reduced: reduced, theme: theme, nowebgl: nowebgl)
      LOAD_ATTEMPTS.times do |attempt|
        page.go_to(url)
        break if defined_in?(page)

        raise ChromeRunner::Unavailable, "the page host did not define bancoPageHost" if attempt == LOAD_ATTEMPTS - 1
      end
      page
    end

    def defined_in?(page)
      deadline = @clock.call + DEFINED_WAIT
      loop do
        return true if page.evaluate("typeof window.bancoPageHost !== 'undefined'")
        return false if @clock.call >= deadline

        sleep 0.25
      end
    end

    # The page's `ready` within page.validate.ready_ms at the throttle. A transient load on the host can make one try late: it is
    # tried again once before it counts.
    def wait_ready(page, index, step, retry_once: true)
      limit = @rule["ready_ms"]
      answer = page.evaluate_async("window.bancoPageHost.ready(arguments[0]).then(arguments[1])", (limit * 6 / 1000.0).ceil + 8, limit * 5)
      if answer["ok"] && answer["ms"] > limit
        if retry_once
          page.command("Page.reload")
          return wait_ready(page, index, step, retry_once: false) if defined_in?(page)
        end
        add("E-PAGE-READY", index, step, "ready after #{answer['ms']} ms at #{@rule['throttle']}x slower CPU (at most #{limit} ms)")
      end
      unless answer["ok"]
        collect(page, index, step)
        add("E-PAGE-READY", index, step, "the page did not send ready within #{limit} ms at #{@rule['throttle']}x slower CPU (main.mjs must call await banco.init())")
        return nil
      end
      answer
    rescue Ferrum::ScriptTimeoutError, Ferrum::TimeoutError
      add("E-PAGE-READY", index, step, "the page host did not answer")
      nil
    end

    # Lets the first frames and the ResizeObserver settle.
    def settle(page)
      sleep 0.6
      page.evaluate("document.fonts ? document.fonts.ready.then(() => true) : true") rescue nil
    end

    # ---- what the host heard ---------------------------------------------------------------------------------------------
    def collect(page, index, step)
      state = page.evaluate("window.bancoPageHost.state()")
      errors = page.evaluate("window.bancoPageHost.log.errors")
      errors.each do |message|
        code = if message.start_with?("csp:") then "E-PAGE-NETWORK"
        elsif message.start_with?("api:") then "E-PAGE-API"
        else "E-PAGE-ERROR"
        end
        add(code, index, step, message)
      end
      add("E-PAGE-NAVIGATION", index, step, "the frame navigated (#{state['loads']} load events)") if state["loads"] > 1
      add("E-PAGE-ERROR", index, step, "#{state['rejected']} messages of the page were rejected by the bridge (malformed, too large or unknown)") if state["rejected"] > 50
      state
    end

    # No request outside the bundle, the kit and the declared libraries (the page's own resource timing).
    def check_resources(page, index)
      answer = audit(page, "resources")
      return unless answer["urls"]

      origin = Pages.validation_origin
      allowed = [ "#{origin}#{SHELL_PATH.call(@revision.bundle_sha256, @kit)}", "#{origin}/kit/banco-page@#{@kit}/", "#{origin}/harness/" ] +
                Array(@manifest["libs"]).filter_map { |s| Pages::Libs.parse(s) }.map { |l| "#{origin}/vendor/#{l[:name]}@#{l[:version]}/" }.uniq
      answer["urls"].each do |url|
        @resources << url
        next if allowed.any? { |prefix| url.start_with?(prefix) } || url.start_with?("data:", "blob:")

        add("E-PAGE-NETWORK", index, "network", "a request outside the bundle, the kit and the libraries: #{url.first(120)}")
      end
    end

    def audit(page, what, arg = nil)
      page.evaluate_async("window.bancoPageHost.audit(arguments[0], arguments[1]).then(arguments[2])", 12, what, arg)
    rescue Ferrum::ScriptTimeoutError, Ferrum::TimeoutError
      { "timeout" => true }
    end

    # ---- screenshots -------------------------------------------------------------------------------------------------------
    def frame_height(page) = [ [ page.evaluate("window.bancoPageHost.rect().height").to_i, 160 ].max, 2400 ].min

    def shot(page, kind, index, width, extra = {})
      height = frame_height(page)
      data = page.command("Page.captureScreenshot", format: "webp", quality: @rule["shot_quality"], captureBeyondViewport: true, clip: { x: 0, y: 0, width: width, height: height, scale: 1 })["data"]
      bytes = Base64.decode64(data)
      @shots << { "kind" => kind, "seed_index" => index, "width" => width, "height" => height, "viewport" => "#{width}x#{height}", "sha256" => @store.put(bytes), "bytes" => bytes.bytesize }.merge(extra.transform_keys(&:to_s))
    end

    def png(page)
      height = frame_height(page)
      page.command("Page.captureScreenshot", format: "png", captureBeyondViewport: true, clip: { x: 0, y: 0, width: wide.first, height: height, scale: 1 })["data"]
    end

    def narrow_shot(page, index)
      page.command("Emulation.setDeviceMetricsOverride", width: narrow.first, height: narrow.last, deviceScaleFactor: 1, mobile: false)
      sleep 0.6
      shot(page, "ready", index, narrow.first)
      collect(page, index, "narrow")
      page.command("Emulation.setDeviceMetricsOverride", width: wide.first, height: wide.last, deviceScaleFactor: 1, mobile: false)
      sleep 0.4
    end

    # ---- determinism -------------------------------------------------------------------------------------------------------
    def determinism(ctx, index, seed, first_png)
      page = open(ctx, seed, wide)
      return unless wait_ready(page, index, "determinism")

      settle(page)
      add_warning("W-PAGE-NONDETERMINISTIC", index, "determinism", "two loads with seed #{seed} gave different ready screenshots") unless png(page) == first_png
    end

    # ---- accessibility -----------------------------------------------------------------------------------------------------
    def a11y(page, index)
      axe = audit(page, "axe")
      if axe["violations"]
        axe["violations"].each do |v|
          message = "axe #{v['id']} (#{v['impact']}): #{v['help']}#{" at #{v['target']}" if v['target']}"
          if %w[serious critical].include?(v["impact"]) then add("E-PAGE-A11Y", index, "axe", message)
          else add_warning("W-PAGE-A11Y", index, "axe", message)
          end
        end
      elsif axe["error"] || axe["timeout"]
        add_warning("W-PAGE-A11Y", index, "axe", "axe did not run: #{axe['error'] || 'timeout'}")
      end
      info = audit(page, "controls")
      @controls = info["controls"] || []
      @canvases = info["canvases"] || []
      @canvases.each { |c| add("E-PAGE-A11Y", index, "canvas", "a canvas has no text alternative (aria-label, role img or text inside)") unless c["text_alternative"] }
      @controls.each { |c| add("E-PAGE-A11Y", index, "name", "a #{c['tag']} control has no accessible name") if c["name"].to_s.strip.empty? }
      tab_through(page, index)
    end

    # Tab reaches every control, each with a visible focus and a name.
    def tab_through(page, index)
      return if @controls.empty?

      page.evaluate("window.bancoPageHost.focusFrame()")
      reached = Set.new
      (@controls.size + 2).times do
        key(page, "Tab")
        sleep 0.05
        active = audit(page, "active")
        next if active["index"].nil? || active["index"] < 0

        reached << active["index"]
        add("E-PAGE-A11Y", index, "focus", "a #{active['tag']} (#{active['name'].to_s.first(30).inspect}) has no visible focus") unless active["ring"]
      end
      missing = @controls.size - reached.size
      add("E-PAGE-A11Y", index, "tab", "Tab reaches #{reached.size} of #{@controls.size} controls (#{missing} cannot be reached with the keyboard)") if missing.positive?
      collect(page, index, "tab")
    end

    # ---- reduced motion ----------------------------------------------------------------------------------------------------
    def reduced_motion(ctx, index, seed)
      page = open(ctx, seed, wide, reduced: true)
      return unless wait_ready(page, index, "reduced")

      settle(page)
      shot(page, "reduced", index, wide.first)
      first = png(page)
      sleep 1.0
      add("E-PAGE-MOTION", index, "reduced", "under reduced motion two screenshots one second apart differ") unless png(page) == first
      collect(page, index, "reduced")
    end

    # ---- no WebGL ------------------------------------------------------------------------------------------------------------
    def no_webgl(ctx, index, seed)
      page = open(ctx, seed, wide, nowebgl: true)
      ready = wait_ready(page, index, "no-webgl")
      unless ready
        add("E-PAGE-NO-FALLBACK", index, "no-webgl", "with WebGL missing the page never started (call banco.fallback() when banco.webgl() is false)")
        return
      end
      settle(page)
      state = collect(page, index, "no-webgl")
      text = audit(page, "text")["text"].to_s
      shot(page, "fallback", index, wide.first)
      needle = @manifest["fallback_it"].to_s.split.first(4).join(" ")
      add("E-PAGE-NO-FALLBACK", index, "no-webgl", "with WebGL missing the page did not show fallback_it (banco.fallback())") unless needle.empty? || text.include?(needle)
      _ = state
    end

    # ---- the scripted session --------------------------------------------------------------------------------------------
    def scripted_session(ctx, index, seed)
      page = open(ctx, seed, wide)
      return unless wait_ready(page, index, "session")

      settle(page)
      info = audit(page, "controls")
      @controls = info["controls"] || []
      @canvases = info["canvases"] || []
      page.evaluate("window.bancoPageHost.focusFrame()")
      frames0 = audit(page, "frames")
      started = @clock.call
      actions = build_actions
      shots_at = @rule["session_shots"]
      actions.each_with_index do |action, i|
        perform(page, action)
        n = i + 1
        shot(page, "session", index, wide.first, "action" => n) if shots_at.include?(n)
        collect(page, index, "action #{n}") if (n % 10).zero?
      end
      measure_frames(page, index, frames0, started)
      page.evaluate("window.bancoPageHost.setVisible(false)")
      sleep 0.4
      page.evaluate("window.bancoPageHost.setVisible(true)")
      sleep 0.4
      page.command("Emulation.setDeviceMetricsOverride", width: narrow.first, height: narrow.last, deviceScaleFactor: 1, mobile: false)
      sleep 0.8
      collect(page, index, "resize")
      idle(page, index)
      budgets(page, index)
      check_resources(page, index)
    end

    # 60 actions: Tab through every control twice, Enter and Space on each button, End and Home on each slider, 10 drags on the canvas;
    # cut at the count, and padded with Tab presses when the page has fewer controls.
    def build_actions
      list = []
      (@controls.size * 2).times { list << [ :key, "Tab" ] }
      buttons = @controls.select { |c| c["tag"] == "button" || c["role"] == "button" }
      sliders = @controls.select { |c| c["type"] == "range" || c["role"] == "slider" }
      buttons.each { |c| list << [ :focus, c["index"] ] << [ :key, "Enter" ] << [ :focus, c["index"] ] << [ :key, "Space" ] }
      sliders.each { |c| list << [ :focus, c["index"] ] << [ :key, "End" ] << [ :key, "Home" ] << [ :key, "ArrowRight" ] }
      @canvases.first(1).each { |c| 10.times { |k| list << [ :drag, c["rect"], k ] } }
      list.concat([ [ :key, "Tab" ] ] * @rule["session_actions"])
      list.first(@rule["session_actions"])
    end

    def perform(page, action)
      case action.first
      when :key then key(page, action[1])
      when :focus then audit(page, "focus", action[1])
      when :drag then drag(page, action[1], action[2])
      end
      sleep 0.03
    end

    def key(page, name)
      spec = KEYS.fetch(name)
      base = { key: spec[:key], code: spec[:code], windowsVirtualKeyCode: spec[:vk], nativeVirtualKeyCode: spec[:vk] }
      page.command("Input.dispatchKeyEvent", **base, type: spec[:text] ? "keyDown" : "rawKeyDown", **(spec[:text] ? { text: spec[:text] } : {}))
      page.command("Input.dispatchKeyEvent", **base, type: "keyUp")
    end

    def drag(page, rect, k)
      frame = page.evaluate("window.bancoPageHost.rect()")
      x0 = frame["x"] + rect["x"] + rect["width"] * 0.2
      y = frame["y"] + rect["y"] + rect["height"] * (0.25 + 0.05 * (k % 10))
      x1 = frame["x"] + rect["x"] + rect["width"] * 0.8
      page.command("Input.dispatchMouseEvent", type: "mouseMoved", x: x0, y: y, button: "none")
      page.command("Input.dispatchMouseEvent", type: "mousePressed", x: x0, y: y, button: "left", buttons: 1, clickCount: 1)
      5.times { |s| page.command("Input.dispatchMouseEvent", type: "mouseMoved", x: x0 + (x1 - x0) * (s + 1) / 5.0, y: y + s, button: "left", buttons: 1) }
      page.command("Input.dispatchMouseEvent", type: "mouseReleased", x: x1, y: y, button: "left", buttons: 0, clickCount: 1)
    end

    # ---- frames, idle, long tasks, memory --------------------------------------------------------------------------------
    def measure_frames(page, index, frames0, started)
      frames1 = audit(page, "frames")
      return unless frames0["frames"] && frames1["frames"]

      seconds = [ @clock.call - started, 0.1 ].max
      frames = frames1["frames"] - frames0["frames"]
      fps = frames / seconds
      add_warning("W-PAGE-FPS", index, "fps", "#{fps.round(1)} frames per second during the session at #{@rule['throttle']}x slower CPU (at least #{@rule['min_fps']})") if frames > 10 && fps < @rule["min_fps"]
    end

    def idle(page, index)
      a = audit(page, "frames")
      sleep @rule["idle_ms"] / 1000.0
      b = audit(page, "frames")
      return unless a["frames"] && b["frames"]

      add_warning("W-PAGE-IDLE-LOOP", index, "idle", "#{b['frames'] - a['frames']} frames rendered in #{@rule['idle_ms']} ms without any interaction (render on demand: let banco.loop rest)") if b["frames"] > a["frames"]
    end

    def budgets(page, index)
      tasks = audit(page, "longtasks")
      if tasks["tasks"] && tasks["initAt"]
        long = tasks["tasks"].select { |t| t["start"] > tasks["initAt"] && t["ms"] > @rule["longtask_ms"] }
        add_warning("W-PAGE-LONGTASK", index, "longtask", "#{long.size} tasks over #{@rule['longtask_ms']} ms after ready (the longest #{long.map { |t| t['ms'] }.max} ms)") if long.any?
      end
      heap = audit(page, "heap")["bytes"]
      add("E-PAGE-MEMORY", index, "heap", "the JavaScript heap is #{heap / 1_048_576} MB (at most #{@rule['heap_mb']} MB)") if heap && heap > @rule["heap_mb"] * 1_048_576
      collect(page, index, "end")
    end

    # ---- findings --------------------------------------------------------------------------------------------------------------
    def add(code, seed_index, step, message)
      return if @errors.any? { |e| e["code"] == code && e["step"] == step && e["message"] == message.to_s.first(300) }

      @errors << { "code" => code, "seed_index" => seed_index, "step" => step, "message" => message.to_s.first(300) }
    end

    def add_warning(code, seed_index, step, message)
      return if @warnings.any? { |e| e["code"] == code && e["step"] == step }

      @warnings << { "code" => code, "seed_index" => seed_index, "step" => step, "message" => message.to_s.first(300) }
    end
  end
end
