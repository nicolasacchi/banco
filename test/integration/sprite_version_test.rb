require "test_helper"
require "minitest/mock"
require_relative "../support/multi_user"
require_relative "../support/student_course_world"

# D-347: public/ is served with a one-year cache, so a sprite at a fixed URL never reaches a browser that already has it
# (the gear of D-343 never reached the student). The address of every sprite carries ?v= and the first 12 hex digits
# of the SHA-256 of the file: a changed sprite is a new URL.
class SpriteVersionTest < ActionDispatch::IntegrationTest
  include MultiUser
  include StudentCourseWorld

  SPRITE = "public/vendor/lucide@1.54.0/banco-sprite.svg"

  setup { Banco::Sprites.reset! }
  teardown { Banco::Sprites.reset! }

  def hrefs
    css_select("svg use").map { |use| use["href"] }
  end

  test "the icons of a student's page point to the sprite with the digest of its file" do
    build_student_world
    on(:web, "/today", headers: OFFICIAL, remote_addr: EDGE)
    assert_response :success
    expected = Digest::SHA256.file(Rails.root.join(SPRITE)).hexdigest[0, 12]
    assert_match(/\A[0-9a-f]{12}\z/, expected)
    assert_not_empty hrefs
    hrefs.each { |href| assert_match(%r{\A/vendor/lucide@1\.54\.0/banco-sprite\.svg\?v=#{expected}#[\w-]+\z}, href) }
  end

  test "the version follows the bytes of the file" do
    digest = ->(bytes) { Digest::SHA256.hexdigest(bytes)[0, 12] }
    file = Rails.root.join(SPRITE)
    original = file.read
    first = Banco::Sprites.href("banco-sprite.svg")
    assert_equal "/vendor/lucide@1.54.0/banco-sprite.svg?v=#{digest.(original)}", first

    Banco::Sprites.stub(:digest, ->(name) { digest.("#{original}<!-- changed -->") }) do
      changed = Banco::Sprites.href("banco-sprite.svg")
      assert_equal "/vendor/lucide@1.54.0/banco-sprite.svg?v=#{digest.("#{original}<!-- changed -->")}", changed
      assert_not_equal first, changed
    end
  end

  test "the digests are those of the files on disk, subject sprites included" do
    Dir.glob(Rails.root.join("public/vendor/lucide@1.54.0/banco-sprite*.svg")).each do |path|
      name = File.basename(path)
      assert_equal "/vendor/lucide@1.54.0/#{name}?v=#{Digest::SHA256.file(path).hexdigest[0, 12]}", Banco::Sprites.href(name)
    end
  end

  test "the browser's version file is the one bin/build-icons writes from the same digests" do
    js = Rails.root.join("app/javascript/lesson/sprites.js").read
    versions = JSON.parse(js[/export default (\{.*\})/, 1])
    assert_equal Dir.children(Rails.root.join("public/vendor/lucide@1.54.0")).grep(/\Abanco-sprite.*\.svg\z/).sort, versions.keys.sort
    versions.each { |name, version| assert_equal Banco::Sprites.digest(name), version }
  end
end
