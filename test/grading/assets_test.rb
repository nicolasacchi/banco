require "test_helper"

# The grader lives under app/javascript but is for the server's Node only.
class GradingAssetsTest < ActiveSupport::TestCase
  test "no grader file is on the asset load path, so none is precompiled or served" do
    logical = Rails.application.assets.load_path.assets.map { |a| a.logical_path.to_s }
    assert_empty logical.grep(%r{\Agrader/})
    assert_includes logical, "application.js", "the rest of app/javascript is still served"
  end

  test "the worker script and the vendored engine are where the worker expects them" do
    assert File.file?(Grading::Expression::WORKER_SCRIPT)
    assert File.file?(Rails.root.join("app/javascript/grader/vendor/compute-engine/compute-engine.js"))
  end
end
