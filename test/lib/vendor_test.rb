require "test_helper"

# The libraries the student's browser runs are copied into public/vendor at fixed
# versions and served by the app (X-02): the checksums hold, the versions are the
# ones the design names, and no page points at a CDN.
class VendorTest < ActiveSupport::TestCase
  VENDOR = Rails.root.join("public/vendor")
  PINNED = { "mathlive@0.111.0" => "MathLive 0.111.0", "katex@0.19.0" => nil, "compute-engine@0.146.0" => nil, "atkinson-hyperlegible@5.3.0" => nil }.freeze

  test "the libraries are there at their pinned versions" do
    assert_equal PINNED.keys.sort, VENDOR.children.map { |c| c.basename.to_s }.sort
  end

  test "every file matches the SHA256SUMS next to it, and every file is listed" do
    PINNED.each_key do |dir|
      root = VENDOR.join(dir)
      sums = root.join("SHA256SUMS").read.lines.to_h { |l| l.strip.split(/\s+/, 2).reverse }
      sums.each do |file, sha|
        path = root.join(file.delete_prefix("./"))
        assert path.file?, "#{dir}/#{file} is listed but missing"
        assert_equal sha, Digest::SHA256.file(path).hexdigest, "#{dir}/#{file} changed"
      end
      on_disk = root.glob("**/*").select(&:file?).map { |f| "./#{f.relative_path_from(root)}" } - [ "./SHA256SUMS" ]
      assert_equal on_disk.sort, sums.keys.map { |k| k.start_with?("./") ? k : "./#{k}" }.sort, "#{dir}: files and SHA256SUMS differ"
    end
  end

  test "the font is under the SIL Open Font License, which travels with it, and the stylesheet names only files that exist" do
    root = VENDOR.join("atkinson-hyperlegible@5.3.0")
    assert_includes root.join("LICENSE").read, "SIL OPEN FONT LICENSE Version 1.1"
    css = Rails.root.join("app/assets/stylesheets/application.css").read
    files = css.scan(%r{/vendor/atkinson-hyperlegible@5\.3\.0/fonts/[\w.-]+\.woff2}).uniq
    assert_equal 4, files.size
    files.each { |f| assert Rails.root.join("public#{f}").file?, "#{f} is missing" }
  end

  test "the files say which version they are" do
    assert_includes VENDOR.join("mathlive@0.111.0/mathlive.min.mjs").read(200), "MathLive 0.111.0"
    assert_match(/version\s*=\s*"0\.19\.0"|"0\.19\.0"/, VENDOR.join("katex@0.19.0/katex.mjs").read)
  end

  test "MathLive's fonts are local and its Compute Engine is ours, never fetched from a CDN" do
    assert VENDOR.join("mathlive@0.111.0/fonts").children.any?
    assert VENDOR.join("compute-engine@0.146.0/compute-engine.js").file?
    # The one remote address in the library is its fallback for a Compute Engine that
    # nobody set; expression.js sets ours before any use, and the CSP would refuse it.
    source = Rails.root.join("app/javascript/items/expression.js").read
    assert_includes source, "/vendor/compute-engine@0.146.0/compute-engine.js"
    assert_includes source, "MathfieldElement.fontsDirectory = `${VENDOR}/fonts/`"
    assert_includes source, "soundsDirectory = null"
    assert_includes source, 'decimalSeparator = ","'
  end

  test "the student's importmap points at the app's own files and its own pins only" do
    map = Importmap::Map.new.draw(Rails.root.join("config/importmap.student.rb"))
    paths = map.packages.values.map(&:path) + map.directories.values.map { |d| d.path.to_s }
    refute paths.any? { |p| p.to_s.match?(%r{\Ahttps?://}) }, "a pin points at another origin: #{paths}"
    refute_includes map.packages.keys, "@hotwired/turbo-rails"
    assert_equal "/vendor/mathlive@0.111.0/mathlive.min.mjs", map.packages["mathlive"].path
    assert_equal "/vendor/katex@0.19.0/katex.mjs", map.packages["katex"].path
  end

  test "no student-facing source mentions a CDN or imports from another origin" do
    sources = Rails.root.glob("app/javascript/{items,student_controllers}/**/*.js") + [ Rails.root.join("app/javascript/diagnosis.js") ]
    sources.each do |file|
      assert_no_match(%r{https?://}, file.read, "#{file.relative_path_from(Rails.root)} names another origin")
    end
    layout = Rails.root.join("app/views/layouts/student.html.erb").read
    assert_no_match(%r{https?://}, layout)
  end
end
