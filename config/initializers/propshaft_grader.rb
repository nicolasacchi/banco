# The expression grader (app/javascript/grader: worker, checker, vendored Compute
# Engine, tests) runs in Node on the server only (A-01). importmap-rails puts all of
# app/javascript on the asset load path, which would digest 3.8 MB of it into
# public/assets and serve it to browsers. Propshaft can only exclude whole load
# path entries, so the grader directory is filtered out of the files it lists.
module GraderOutOfAssets
  GRADER_DIR = "#{Rails.root.join('app/javascript/grader')}/".freeze

  private

  def without_dotfiles(files)
    super.reject { |file| file.to_s.start_with?(GRADER_DIR) }
  end
end

Propshaft::LoadPath.prepend(GraderOutOfAssets)
