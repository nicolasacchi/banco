# Figures that agents draw, served as images only (X-02): from
# /assets/items/<sha256>.svg, never inline. The browser is told not to sniff and
# the file gets a policy of its own that allows nothing but its own styles and
# puts it in a sandbox, so a script inside the SVG cannot run even when the URL is
# opened directly.
class ItemAssetsController < ApplicationController
  SHA256 = /\A[0-9a-f]{64}\z/

  def show
    return head(:forbidden) unless current_identity

    sha = params[:sha256].to_s
    return head(:not_found) unless SHA256.match?(sha)

    # Found by listing the directory, so the request's text never builds a path.
    path = self.class.directory.glob("*.svg").find { |file| file.basename.to_s == "#{sha}.svg" }
    return head(:not_found) unless path&.file?

    response.headers["X-Content-Type-Options"] = "nosniff"
    response.headers["Content-Security-Policy"] = "default-src 'none'; style-src 'unsafe-inline'; sandbox"
    response.headers["Cache-Control"] = "private, max-age=31536000, immutable"
    send_file path, type: "image/svg+xml", disposition: "inline"
  end

  # Where validation stores figures, named by the sha256 of their bytes.
  def self.directory
    Pathname(Rails.application.config.x.item_assets_dir.presence || Rails.root.join("storage/item_assets"))
  end
end
