require "digest"
require "fileutils"

module Items
  # Puts an item's figure where the student's browser can fetch it (D-321). An instance display names
  # its figure by asset (`assets/h1-01.svg`, a file of the item revision); the browser gets it only as
  # an <img src="/assets/items/<sha256>.svg"> served by ItemAssetsController. The ledger rows are never
  # rewritten, so the digest is worked out when the item is drawn and the file is written once under
  # its digest (storage/item_assets/, config.x.item_assets_dir overrides), atomically.
  #
  # The SVG is agent-written. It runs nowhere (an <img> never runs scripts), and a stored copy is
  # refused anyway when it carries anything active: the validation's own check
  # (Validation::ItemChecks.svg_problem) plus a stricter pass here (DOCTYPE and entities, javascript:
  # and data: addresses, embedding or animating elements, outside references). A refused figure is
  # not shown; the student sees the alt text.
  module Figures
    EXTRA = [
      [ /<!DOCTYPE|<!ENTITY/i, "a DOCTYPE or entity" ],
      [ /=\s*["']\s*(?:javascript|vbscript|data)\s*:/i, "a script or data address" ],
      [ /<\s*(?:iframe|embed|object|audio|video|canvas|animate|set|handler|listener)\b/i, "an embedding or scripting element" ],
      [ /<\s*(?:use|image|a|feImage|link|style)\b[^>]*href\s*=\s*["']\s*(?!#)/i, "an outside reference" ]
    ].freeze
    MAX_BYTES = 512 * 1024

    module_function

    # The digest of the asset's stored copy, or nil (no such file in the revision, or the SVG is refused).
    def digest_for(asset, files)
      text = files[asset.to_s]
      return nil unless text.is_a?(String) && asset.to_s.end_with?(".svg")
      return nil unless problem(text).nil?

      sha = Digest::SHA256.hexdigest(text)
      store(sha, text)
      sha
    rescue SystemCallError, IOError => e
      Rails.logger.warn("Items::Figures: #{asset} not stored (#{e.class}: #{e.message}); the alt text is shown")
      nil
    end

    # Whether a stored copy exists under this digest.
    def stored?(sha) = ItemAssetsController.directory.join("#{sha}.svg").file?

    # Why an SVG may not be stored, or nil.
    def problem(text)
      return "too big" if text.bytesize > MAX_BYTES
      return "not an SVG" unless text.match?(/<svg\b/i)

      Validation::ItemChecks.svg_problem(text) || EXTRA.find { |re, _| text.match?(re) }&.last
    end

    def store(sha, text)
      dir = ItemAssetsController.directory
      path = dir.join("#{sha}.svg")
      return if path.file?

      FileUtils.mkdir_p(dir)
      tmp = dir.join(".#{sha}.#{Process.pid}.#{SecureRandom.hex(4)}.tmp")
      File.binwrite(tmp, text)
      File.rename(tmp, path)
    ensure
      FileUtils.rm_f(tmp) if tmp
    end
  end
end
