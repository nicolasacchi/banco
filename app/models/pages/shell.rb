# The shell of a page (SPEC B3): generated from the stored manifest and the kit version, so the agent cannot add inline
# scripts, meta refreshes or external links. The response headers are exact and fixed per mount.
module Pages
  module Shell
    Rendered = Struct.new(:html, :csp, keyword_init: true)

    PERMISSIONS = "camera=(), microphone=(), geolocation=(), usb=(), serial=(), hid=(), bluetooth=(), payment=(), clipboard-read=(), display-capture=()"
    AXE = "/harness/axe-core@4.14.0/axe.min.js"
    AUDIT = "/harness/page-audit@1/audit.mjs"

    module_function

    # manifest: the stored banco.page/1 hash; paths: the files of the revision; mode :production or :validate;
    # origin: the pages origin of the mount; parent: the framing origin.
    def render(manifest, paths:, kit:, mode:, origin:, parent:)
      kit_base = "/kit/banco-page@#{kit}"
      map = { "banco" => "#{kit_base}/bridge.mjs" }.merge(Libs.importmap(Array(manifest["libs"])))
      importmap = JSON.generate("imports" => map).gsub("<", "\\u003c")
      h = ERB::Util.method(:html_escape)
      head = +%(<!doctype html><html lang="it" data-theme="cream"><head><meta charset="utf-8"><meta name="viewport" content="width=device-width, initial-scale=1">)
      head << %(<title>#{h.call(manifest['title_it'])}</title><link rel="stylesheet" href="#{kit_base}/page.css">)
      head << %(<link rel="stylesheet" href="style.css">) if paths.include?("style.css")
      head << %(<script type="importmap">#{importmap}</script>)
      head << %(<script src="#{AXE}"></script>) if mode == :validate
      head << "</head>"
      body = +%(<body><main id="app" data-fallback-it="#{h.call(manifest['fallback_it'])}"></main><noscript><p class="banco-fallback">#{h.call(manifest['fallback_it'])}</p></noscript>)
      body << %(<script type="module" src="#{kit_base}/boot.mjs"></script>)
      body << %(<script type="module" src="#{AUDIT}"></script>) if mode == :validate
      body << %(<script type="module" src="main.mjs"></script></body></html>)
      Rendered.new(html: head + body, csp: csp(importmap, origin: origin, parent: parent))
    end

    def csp(importmap, origin:, parent:)
      hash = Base64.strict_encode64(Digest::SHA256.digest(importmap))
      [ "sandbox allow-scripts", "default-src 'none'", "script-src #{origin} 'sha256-#{hash}'", "style-src #{origin} 'unsafe-inline'", "img-src #{origin} data: blob:",
        "font-src #{origin}", "media-src #{origin} blob:", "connect-src 'none'", "worker-src 'none'", "frame-src 'none'", "child-src 'none'", "object-src 'none'",
        "manifest-src 'none'", "form-action 'none'", "base-uri 'none'", "frame-ancestors #{parent}" ].join("; ")
    end
  end
end
