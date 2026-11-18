require "test_helper"

# D-359: the name of a clip is the same in Ruby and in the browser (lesson/speech_clips.js reads the same vectors), and the voices come from config.
class SpeechKeyTest < ActiveSupport::TestCase
  VECTORS = JSON.parse(Rails.root.join("test/fixtures/speech/keys.json").read)

  test "the shared vectors give the same keys (accents, quotes, guillemets, a dash, an apostrophe)" do
    assert_operator VECTORS["vectors"].size, :>=, 5
    VECTORS["vectors"].each do |v|
      assert_equal v["key"], Speech::Key.for(v["voice"], v["text"], engine: VECTORS["engine"]), v["text"]
      assert Speech::Key.valid?(v["key"])
    end
    texts = VECTORS["vectors"].map { |v| v["text"] }
    [ "è", "ñ", "«", "\"", "'" ].each { |mark| assert texts.any? { |t| t.include?(mark) }, "a vector with #{mark}" }
    assert_equal VECTORS["engine"], Speech::Voices.engine, "the vectors are made for the engine of voices.yml"
  end

  test "the key is the hex SHA-256 of engine|voice|text over UTF-8, and any change of the three is another key" do
    assert_equal Digest::SHA256.hexdigest("kokoro-82m-v1.0|im_nicola|Più"), Speech::Key.for("im_nicola", "Più")
    keys = [ Speech::Key.for("im_nicola", "Più"), Speech::Key.for("af_heart", "Più"), Speech::Key.for("im_nicola", "Piu"), Speech::Key.for("im_nicola", "Più", engine: "other") ]
    assert_equal 4, keys.uniq.size
  end

  test "a key is 64 lowercase hex characters and nothing else, and its url is under the clip path" do
    key = "a" * 64
    assert Speech::Key.valid?(key)
    [ "A" * 64, "a" * 63, "a" * 65, "../#{'a' * 61}", "#{'a' * 64}\n", "", nil ].each { |bad| assert_not Speech::Key.valid?(bad), bad.inspect }
    assert_equal "/speech/clips/#{key}.mp3", Speech::Key.url(key)
  end

  test "the voice of a segment is the speaker's place in the language's list, round and round; Latin has none" do
    assert_equal "im_nicola", Speech::Voices.voice_for("it")
    assert_equal "im_nicola", Speech::Voices.voice_for("it", 2)
    assert_equal %w[af_heart af_bella af_heart], [ 1, 2, 3 ].map { |n| Speech::Voices.voice_for("en", n) }
    assert_equal %w[ef_dora em_alex], [ 1, 2 ].map { |n| Speech::Voices.voice_for("es", n) }
    assert_equal "af_heart", Speech::Voices.voice_for("en", 0), "a number below 1 is speaker 1"
    assert_nil Speech::Voices.voice_for("la")
    assert_equal "es", Speech::Voices.language_of("em_alex")
  end

  test "the generated browser file carries the same server block as voices.yml" do
    js = Rails.root.join("app/javascript/lesson/voices.js").read[/export default (.*)$/, 1]
    assert_equal Speech::Voices.config, JSON.parse(js)["server"]
  end

  test "the clip files live under the first two characters of the key" do
    Dir.mktmpdir do |dir|
      ENV["BANCO_SPEECH_CLIPS_DIR"] = dir
      key = Speech::Key.for("im_nicola", "Ciao")
      assert_equal File.join(dir, key[0, 2], "#{key}.mp3"), Speech::Clips.path(key)
      assert_nil Speech::Clips.path("../etc/passwd")
      assert_not Speech::Clips.exist?(key)
      Speech::Clips.put(key, "bytes")
      assert Speech::Clips.exist?(key)
    ensure
      ENV.delete("BANCO_SPEECH_CLIPS_DIR")
    end
  end
end
