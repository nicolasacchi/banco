# Agent figures live at /assets/items/<sha256>.svg and are served by
# ItemAssetsController (nosniff, a sandbox policy), not from the asset pipeline.
# Propshaft's development server answers 404 itself for anything under /assets/ that
# it does not know, so these paths are handed on to the application.
module ItemAssetsPassThrough
  ITEM_ASSETS = %r{\A/assets/items/[0-9a-f]{64}\.svg\z}

  def call(env)
    return @app.call(env) if ITEM_ASSETS.match?(env["PATH_INFO"])

    super
  end
end

Propshaft::Server.prepend(ItemAssetsPassThrough)
