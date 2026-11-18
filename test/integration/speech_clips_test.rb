require "test_helper"
require_relative "../support/multi_user"

# D-359: GET /speech/clips/<key>.mp3, the file made ahead of time, for the student, the preview, the teacher and the guest; the headers of a file that
# never changes; a 404 for a missing or malformed name; nothing recorded; byte ranges for Safari.
class SpeechClipsTest < ActionDispatch::IntegrationTest
  include MultiUser

  BYTES = (+"ID3\x04\x00clip bytes of a short sentence").b.freeze

  setup do
    @dir = Dir.mktmpdir("speech-clips")
    ENV["BANCO_SPEECH_CLIPS_DIR"] = @dir
    @key = Speech::Key.for("im_nicola", "Ciao a tutti.")
    Speech::Clips.put(@key, BYTES)
  end

  teardown do
    ENV.delete("BANCO_SPEECH_CLIPS_DIR")
    FileUtils.rm_rf(@dir)
  end

  def clip(headers, key = @key, **options) = on(:web, "/speech/clips/#{key}.mp3", headers: headers, remote_addr: EDGE, **options)

  test "an existing clip is served as audio/mpeg, cached for a year, to the student, a trial student, the teacher and the guest" do
    [ OFFICIAL, TRIAL, TEACHER, GUEST ].each do |who|
      clip(who)
      assert_response :success, who.inspect
      assert_equal "audio/mpeg", response.media_type
      assert_equal %w[immutable max-age=31536000 public], response.headers["Cache-Control"].split(/,\s*/).sort
      assert_equal "bytes", response.headers["Accept-Ranges"]
      assert_equal "nosniff", response.headers["X-Content-Type-Options"]
      assert_equal BYTES, response.body.b
    end
  end

  test "a missing clip, a key that is not 64 lowercase hex characters and a name that tries to leave the directory are 404" do
    clip(OFFICIAL, "b" * 64)
    assert_response :not_found
    [ "short", "A" * 64, "a" * 65, "..%2F..%2Fetc%2Fpasswd", "%2e%2e", "#{@key}.mp3" ].each do |bad|
      clip(OFFICIAL, bad)
      assert_response :not_found, bad
    end
    on(:web, "/speech/clips/#{@key}", headers: OFFICIAL, remote_addr: EDGE)
    assert_response :not_found, "the .mp3 is part of the name"
    on(:web, "/speech/clips/#{@key}.wav", headers: OFFICIAL, remote_addr: EDGE)
    assert_response :not_found
  end

  test "somebody who is not signed in, or not configured as a student, is refused, and the API listener never serves it" do
    clip({})
    assert_response :forbidden
    clip(UNMAPPED)
    assert_response :forbidden
    on(:api, "/speech/clips/#{@key}.mp3", remote_addr: "127.0.0.1")
    assert_response :not_found
    on(:harness, "/speech/clips/#{@key}.mp3", remote_addr: "127.0.0.1")
    assert_response :not_found
  end

  test "nothing is recorded by asking for a clip" do
    before = ActiveRecord::Base.connection.tables.reject { |t| t.start_with?("ar_") || t == "schema_migrations" }.to_h { |t| [ t, ActiveRecord::Base.connection.select_value("SELECT COUNT(*) FROM #{t}") ] }
    clip(OFFICIAL)
    clip(TEACHER, "c" * 64)
    after = before.keys.to_h { |t| [ t, ActiveRecord::Base.connection.select_value("SELECT COUNT(*) FROM #{t}") ] }
    assert_equal before, after
  end

  test "a byte range is answered with 206 and its Content-Range (Safari asks before it plays), a range past the end with 416" do
    on(:web, "/speech/clips/#{@key}.mp3", headers: OFFICIAL.merge("Range" => "bytes=0-4"), remote_addr: EDGE)
    assert_response :partial_content
    assert_equal BYTES.byteslice(0, 5), response.body.b
    assert_equal "bytes 0-4/#{BYTES.bytesize}", response.headers["Content-Range"]
    on(:web, "/speech/clips/#{@key}.mp3", headers: OFFICIAL.merge("Range" => "bytes=3-"), remote_addr: EDGE)
    assert_response :partial_content
    assert_equal BYTES.byteslice(3..), response.body.b
    on(:web, "/speech/clips/#{@key}.mp3", headers: OFFICIAL.merge("Range" => "bytes=-4"), remote_addr: EDGE)
    assert_equal BYTES.byteslice(-4, 4), response.body.b
    on(:web, "/speech/clips/#{@key}.mp3", headers: OFFICIAL.merge("Range" => "bytes=#{BYTES.bytesize}-"), remote_addr: EDGE)
    assert_response :range_not_satisfiable
    assert_equal "bytes */#{BYTES.bytesize}", response.headers["Content-Range"]
  end
end
