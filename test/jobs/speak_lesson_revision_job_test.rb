require "test_helper"
require_relative "../support/lesson_render_world"
require_relative "../support/speech_world"

# The clips of a lesson revision (D-359): made once after the render check has collected what the lesson says, with the voice the speaker has, never
# for Latin, one failing clip not stopping the others, nothing without a service.
class SpeakLessonRevisionJobTest < ActiveJob::TestCase
  include SpeechWorld

  def self.seg(lang, text, voice = 1) = { "lang" => lang, "text" => text, "voice" => voice }

  SEGMENTS = [
    seg("it", "Ciao a tutti."),
    seg("en", "Are you coming on Saturday?", 1),
    seg("en", "Yes, if it doesn't rain.", 2),
    seg("en", "Hello again."),
    seg("la", "Rosa, rosae."),
    seg("es", "¿Cómo estás?", 2),
    seg("en", "Hello again.") # said twice: one clip
  ].freeze

  setup do
    @revision = revision_with_segments!(SEGMENTS)
    @stub = Speech::Client::Stub.new
  end

  def key(voice, text) = Speech::Key.for(voice, text)

  def run_job(client = @stub, revision = @revision)
    Speech::Client.using(client) { SpeakLessonRevisionJob.perform_now(revision.id) }
  end

  test "it makes a clip for each distinct segment of a language with server voices, with speaker 2's voice for the second speaker, and none for Latin" do
    run_job
    assert_equal 5, SpeechClip.count
    assert_equal [ [ "af_bella", "Yes, if it doesn't rain." ], [ "af_heart", "Are you coming on Saturday?" ], [ "af_heart", "Hello again." ],
                   [ "em_alex", "¿Cómo estás?" ], [ "im_nicola", "Ciao a tutti." ] ], @stub.calls.map { |c| [ c[:voice], c[:text] ] }.sort
    assert_equal %w[en en en es it], @stub.calls.map { |c| c[:lang] }.sort
    clip = SpeechClip.find_by!(key: key("af_bella", "Yes, if it doesn't rain."))
    assert_equal [ "kokoro-82m-v1.0", "af_bella", "en" ], [ clip.engine, clip.voice, clip.lang ]
    assert File.file?(File.join(@clips_dir, clip.key[0, 2], "#{clip.key}.mp3"))
    assert_equal File.size(Speech::Clips.path(clip.key)), clip.bytes
    assert clip.duration_ms.positive?
    assert_not SpeechClip.exists?(key: key("im_nicola", "Rosa, rosae.")), "no clip for Latin"
    assert_not stub_asked?("Rosa, rosae.")
  end

  def stub_asked?(text) = @stub.calls.any? { |c| c[:text] == text }

  test "it is idempotent: a second run asks the service for nothing and adds no row" do
    run_job
    asked = @stub.calls.size
    assert_no_difference -> { SpeechClip.count } do
      run_job
    end
    assert_equal asked, @stub.calls.size
  end

  test "another revision that says the same sentence reuses the clip" do
    run_job
    other = revision_with_segments!([ seg("it", "Ciao a tutti."), seg("it", "Una frase nuova.") ])
    assert_difference -> { SpeechClip.count }, 1 do
      run_job(@stub, other)
    end
    assert_equal 1, @stub.calls.count { |c| c[:text] == "Ciao a tutti." }
  end

  test "the rows are append-only like every ledger table" do
    run_job
    assert_raises(ActiveRecord::StatementInvalid) { SpeechClip.first.update_columns(bytes: 1) }
    assert_raises(ActiveRecord::StatementInvalid) { SpeechClip.first.delete }
  end

  test "a file stored without its row gets the row, and a row whose file was purged gets the file again, without a second row" do
    run_job
    gone = SpeechClip.find_by!(key: key("im_nicola", "Ciao a tutti."))
    File.delete(Speech::Clips.path(gone.key))
    # a row cannot be deleted: the crash between the file and its row is a clip with a file and no row
    extra = Speech::Plan::Entry.new(lang: "it", text: "Solo il file.", number: 1, voice: "im_nicola", key: key("im_nicola", "Solo il file."))
    Speech::Clips.put(extra.key, "file only")
    assert_equal :present, Speech::Maker.call(extra, @stub)
    assert_equal 9, SpeechClip.find_by!(key: extra.key).bytes
    run_job
    assert Speech::Clips.exist?(gone.key)
    assert_equal 1, SpeechClip.where(key: gone.key).count
  end

  test "one clip the service refuses does not stop the others, and a refusal is not retried" do
    refusing = Speech::Client::Stub.new
    refusing.define_singleton_method(:synthesize) do |text:, voice:, lang:, speed: 1.0|
      raise Speech::Client::Rejected, "no" if text == "Ciao a tutti."

      super(text: text, voice: voice, lang: lang, speed: speed)
    end
    assert_no_enqueued_jobs { run_job(refusing) }
    assert_equal 4, SpeechClip.count
    assert_not SpeechClip.exists?(key: key("im_nicola", "Ciao a tutti."))
  end

  test "clips the service cannot make now are tried again later, and the others are kept" do
    flaky = Speech::Client::Stub.new(down: ->(text) { text.start_with?("Yes") })
    assert_enqueued_with(job: SpeakLessonRevisionJob, args: [ @revision.id ]) { run_job(flaky) }
    assert_equal 4, SpeechClip.count, "the other clips are made"
    assert_not SpeechClip.exists?(key: key("af_bella", "Yes, if it doesn't rain."))
    clear_enqueued_jobs
    run_job(@stub)
    assert_equal 5, SpeechClip.count
  end

  test "a service that is down ends the run after a few failures, not after every sentence" do
    down = Speech::Client::Stub.new(down: true)
    assert_enqueued_with(job: SpeakLessonRevisionJob) { run_job(down) }
    assert_equal Speech::Maker::DOWN_AFTER, down.calls.size
    assert_equal 0, SpeechClip.count
  end

  test "without BANCO_TTS_URL it does nothing and says so" do
    messages = []
    logger = Object.new
    logger.define_singleton_method(:info) { |m = nil, &b| messages << (m || b.call) }
    logger.define_singleton_method(:warn) { |*| }
    saved_logger = Rails.logger
    saved_url = ENV.delete("BANCO_TTS_URL")
    begin
      Rails.logger = logger
      Speech::Client.using(nil) { SpeakLessonRevisionJob.perform_now(@revision.id) }
      assert_no_enqueued_jobs { Speech::Client.using(nil) { SpeakLessonRevisionJob.later(@revision.id) } }
    ensure
      Rails.logger = saved_logger
      ENV["BANCO_TTS_URL"] = saved_url if saved_url
    end
    assert_equal 0, SpeechClip.count
    assert_equal 2, messages.count { |m| m.include?("BANCO_TTS_URL is not set") }
  end

  test "later enqueues the job when there is a service" do
    assert_enqueued_with(job: SpeakLessonRevisionJob, args: [ @revision.id ]) do
      Speech::Client.using(@stub) { SpeakLessonRevisionJob.later(@revision.id) }
    end
  end

  test "a revision with no passed render that collected segments has nothing to make" do
    plain = store_lesson2!(served("equations"))
    render_row!(plain, nil)
    run_job(@stub, plain)
    failed = store_lesson2!(served("equations"))
    render_row!(failed, [ seg("it", "Non si dice.") ], status: "failed")
    run_job(@stub, failed)
    assert_empty @stub.calls
  end

  test "a text longer than the service takes is left out of the plan (the browser falls back to a device voice)" do
    long = revision_with_segments!([ seg("it", "a" * 1001), seg("it", "Breve.") ])
    assert_equal [ "Breve." ], Speech::Plan.entries(long).map(&:text)
  end

  test "the stub refuses what the service refuses" do
    assert_raises(Speech::Client::Rejected) { @stub.synthesize(text: "", voice: "im_nicola", lang: "it") }
    assert_raises(Speech::Client::Rejected) { @stub.synthesize(text: "x" * 1001, voice: "im_nicola", lang: "it") }
    assert_raises(Speech::Client::Rejected) { @stub.synthesize(text: "Hi", voice: "nobody", lang: "en") }
    assert_raises(Speech::Client::Rejected) { @stub.synthesize(text: "Hi", voice: "af_heart", lang: "es") }
  end
end
