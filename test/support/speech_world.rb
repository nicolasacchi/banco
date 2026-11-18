# A lesson/2 revision with a passed render that collected segments (D-359), and a clips directory of its own.
module SpeechWorld
  include LessonRenderWorld

  def self.included(base)
    base.setup do
      @clips_dir = Dir.mktmpdir("speech-clips")
      ENV["BANCO_SPEECH_CLIPS_DIR"] = @clips_dir
    end
    base.teardown do
      ENV.delete("BANCO_SPEECH_CLIPS_DIR")
      FileUtils.rm_rf(@clips_dir)
    end
  end

  def seg(lang, text, voice = 1) = { "lang" => lang, "text" => text, "voice" => voice }

  # A render row of +revision+ with these segments (nil: a row from before they were collected).
  def render_row!(revision, segments, status: "passed", harness_version: Validation::Harness.lesson_version)
    LessonRender.create!(lesson_revision: revision, status: status, rules_version: "8", harness_version: harness_version, attempt: 1,
                         result_json: JSON.generate("errors" => []), shots_json: "[]", segments_json: segments && JSON.generate(segments))
  end

  def revision_with_segments!(segments, **options)
    revision = store_lesson2!(served("equations"))
    render_row!(revision, segments, **options)
    revision
  end
end
