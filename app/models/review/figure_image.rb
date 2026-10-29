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

    class << self
      # The PNG of +svg+ (text): a cached one, or one drawn now (Chrome, under its lock).
      def png(svg)
        sha = Digest::SHA256.hexdigest(svg)
        path = File.join(dir, "#{sha}.png")
        bytes = File.binread(path) if File.exist?(path)
        bytes ||= draw(svg).tap { |data| store(path, data) }
        width, height = bytes.byteslice(16, 8).unpack("NN")
        Image.new(sha256: sha, bytes: bytes, width: width, height: height)
      end

      def dir
        path = ENV["BANCO_ITEM_FIGURES_DIR"].presence || Rails.root.join("storage/item_figures").to_s
        FileUtils.mkdir_p(path)
        path
      end

      private

      def store(path, data)
        tmp = "#{path}.#{Process.pid}.#{SecureRandom.hex(4)}.tmp"
        File.binwrite(tmp, data)
        File.rename(tmp, path)
      end

      def draw(svg)
        html = %(<!doctype html><meta charset="utf-8"><body style="margin:0;background:#fff">) +
               %(<img id="f" style="display:block;width:#{WIDTH}px;height:auto;max-height:#{MAX_HEIGHT}px" src="data:image/svg+xml;base64,#{Base64.strict_encode64(svg)}">)
        Validation::ChromeRunner.session(wait: 120) do |session|
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
            Base64.decode64(page.command("Page.captureScreenshot", format: "png", clip: { x: 0, y: 0, width: WIDTH, height: height, scale: 1 }, captureBeyondViewport: true)["data"])
          end
        end
      rescue Validation::ChromeRunner::Error => e
        raise Unavailable, e.message
      end
    end
  end
end
