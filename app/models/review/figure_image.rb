require "base64"
require "fileutils"

module Review
  # An item's SVG figure as a PNG, for the agents that read the item as the student does (D-320).
  # The picture is the drawing and nothing else: the SVG is drawn by Chrome as an <img> (so it
  # runs no script and loads nothing) on a white page and only the pixels are kept. Its <title>,
  # <desc>, metadata, comments and data-* attributes cannot reach the agent, because a PNG made
  # this way carries only the image chunks. Cached by the digest of the SVG's bytes.
  class FigureImage
    WIDTH = 1000 # px: axis labels stay readable
    MAX_HEIGHT = 2000
    Image = Struct.new(:sha256, :bytes, :width, :height, keyword_init: true)

    class Unavailable < StandardError; end
    # Another run holds Chrome: a clean 409 with retry advice.
    class Busy < Unavailable; end

    LOCK_WAIT = 60 # s waited for Chrome's lock, once per open
    DRAW_BUDGET = 60 # s for all the figures of one open, drawn in one Chrome session

    class << self
      # PNGs for several SVG texts (same order): cached ones are read, bad cache files are redrawn, every
      # other figure is drawn in ONE Chrome session under one deadline.
      def png_all(svgs)
        images = svgs.map { |svg| cached(svg) }
        todo = images.each_index.select { |i| images[i].nil? }
        return images if todo.empty?

        deadline = Process.clock_gettime(Process::CLOCK_MONOTONIC) + DRAW_BUDGET
        drawn = {}
        begin
          Validation::ChromeRunner.session(wait: LOCK_WAIT) do |session|
            todo.map { |i| svgs[i] }.uniq.each do |svg|
              raise Unavailable, "drawing the figures took more than #{DRAW_BUDGET} s" if Process.clock_gettime(Process::CLOCK_MONOTONIC) > deadline

              drawn[svg] = draw(session, svg)
            end
          end
        rescue Validation::ChromeRunner::Busy => e
          raise Busy, e.message
        rescue Validation::ChromeRunner::Error => e
          raise Unavailable, e.message
        end
        svgs.each_with_index.map do |svg, i|
          bytes = drawn[svg]
          store(path_of(svg), bytes) if bytes && images[i].nil?
          images[i] || image_of(svg, bytes)
        end
      end

      def png(svg) = png_all([ svg ]).first

      def dir
        path = ENV["BANCO_ITEM_FIGURES_DIR"].presence || Rails.root.join("storage/item_figures").to_s
        FileUtils.mkdir_p(path, mode: 0o700)
        path
      end

      # A well-formed PNG: signature, IHDR first, IEND last.
      def valid_png?(bytes)
        bytes.is_a?(String) && bytes.bytesize > 57 && bytes.byteslice(0, 8) == "\x89PNG\r\n\x1a\n".b &&
          bytes.byteslice(12, 4) == "IHDR" && bytes.byteslice(-12, 12) == "\x00\x00\x00\x00IEND\xAEB`\x82".b
      end

      private

      def store(path, data)
        tmp = "#{path}.#{Process.pid}.#{SecureRandom.hex(4)}.tmp"
        File.binwrite(tmp, data, perm: 0o600)
        File.rename(tmp, path)
      end

      def path_of(svg) = File.join(dir, "#{Digest::SHA256.hexdigest(svg)}.png")

      def cached(svg)
        path = path_of(svg)
        bytes = File.binread(path) if File.file?(path)
        return nil unless valid_png?(bytes)

        image_of(svg, bytes)
      end

      def image_of(svg, bytes)
        width, height = bytes.byteslice(16, 8).unpack("NN")
        Image.new(sha256: Digest::SHA256.hexdigest(svg), bytes: bytes, width: width, height: height)
      end

      def draw(session, svg)
        html = %(<!doctype html><meta charset="utf-8"><body style="margin:0;background:#fff">) +
               %(<img id="f" style="display:block;width:#{WIDTH}px;height:auto;max-height:#{MAX_HEIGHT}px" src="data:image/svg+xml;base64,#{Base64.strict_encode64(svg)}">)
        session.context do |ctx|
          page = ctx.create_page
          page.command("Emulation.setDeviceMetricsOverride", width: WIDTH, height: 800, deviceScaleFactor: 1, mobile: false)
          page.go_to("about:blank")
          page.content = html
          box = page.evaluate_async(<<~JS, 10)
            const img = document.getElementById("f")
            const done = () => { const r = img.getBoundingClientRect(); arguments[0]({ ok: img.naturalWidth > 0, w: Math.ceil(r.width), h: Math.ceil(r.height) }) }
            img.complete ? done() : (img.onload = done, img.onerror = () => arguments[0]({ ok: false }))
          JS
          raise Unavailable, "the figure did not draw as an image" unless box && box["ok"] && box["h"].positive?

          height = [ box["h"], MAX_HEIGHT ].min
          bytes = Base64.decode64(page.command("Page.captureScreenshot", format: "png", clip: { x: 0, y: 0, width: WIDTH, height: height, scale: 1 }, captureBeyondViewport: true)["data"])
          raise Unavailable, "Chrome returned no picture" unless valid_png?(bytes)

          bytes
        end
      end
    end
  end
end
