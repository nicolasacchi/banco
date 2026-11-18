require "test_helper"
require_relative "../support/validation_servers"
require_relative "../support/chrome_helper"
require_relative "../support/lesson_render_world"

# D-359: the render check's host collects, with the verdict, every segment the lesson says aloud ({lang, text, voice}): what "Ascolta" reads of each card
# in each state it draws, a dialogue's lines with their speakers' voices, the speaker beside a foreign word and the text of a listening check.
# The server then makes a clip of each. Needs Chrome (BROWSER_PATH); skips without.
class LessonRenderSegmentsTest < ActiveSupport::TestCase
  include ChromeHelper
  include LessonRenderWorld

  setup do
    require_chrome!
    @shots_dir = Dir.mktmpdir("lesson-shots")
    ENV["BANCO_LESSON_SHOTS_DIR"] = @shots_dir
  end

  teardown do
    ENV.delete("BANCO_LESSON_SHOTS_DIR")
    FileUtils.rm_rf(@shots_dir)
  end

  def draw(body)
    revision = store_lesson2!(body)
    Validation::LessonRenderCheck.new(revision).call
    LessonRender.where(lesson_revision_id: revision.id).order(:id).last
  end

  def dump(row) = row.result["errors"].map { |e| "#{e['code']} card #{e['card']} #{e['state'] || '-'} #{e['viewport']}: #{e['message']}" }.join("\n")

  def seg(lang, text, voice = 1) = { "lang" => lang, "text" => text, "voice" => voice }

  test "a lesson with a dialogue gives each line with its speaker's voice, and the figure's own sentences" do
    findings = Validation::Findings.new
    body = Lessons::Parser2.call(Rails.root.join("test/fixtures/lesson2/gallery/words-english.md").read, findings).body
    row = draw(body)
    assert_equal "passed", row.status, dump(row)
    segments = row.segments
    assert_kind_of Array, segments
    assert_equal segments.uniq, segments, "each segment once"
    assert segments.all? { |s| s.keys.sort == %w[lang text voice] }
    assert_includes segments, seg("en", "Are you coming to the lake on Saturday?", 1)
    assert_includes segments, seg("en", "Yes, if it doesn't rain.", 2)
    assert_includes segments, seg("en", "I will call you when I arrive.", 1)
    assert segments.any? { |s| s["lang"] == "it" && s["voice"] == 1 }, "the card's own Italian is read too"
    # what the server would make of them: speaker 2 of an English dialogue is the second English voice
    plan = Speech::Plan.entries(row.lesson_revision)
    assert_equal "af_bella", plan.find { |e| e.text == "Yes, if it doesn't rain." && e.number == 2 }.voice
    assert_equal "af_heart", plan.find { |e| e.text == "Are you coming to the lake on Saturday?" && e.number == 1 }.voice
  end

  test "a foreign word with its speaker, a listening check and the exercises of Prova tu, each in its state" do
    findings = Validation::Findings.new
    md = <<~MD
      ---
      schema: banco.lesson/2
      key: ripasso.english.render-segments
      kind: ripasso
      subject: english
      title_it: "Prova dei segmenti"
      goals_it:
        - "**Sentire** ogni frase"
        - "**Aprire** ogni parte"
      skills: [english.render-segments]
      refs:
        - {source: prima-2025-26, line: 21, fragment: "una prova", role: taught_in}
      scope: studied
      minutes: 20
      calculator: false
      why_it: "Ogni frase detta ad alta voce è nota prima. Il contenuto è inventato."
      ---

      ## Una parola nuova {idea icon=lightbulb}

      Si dice [[en:good morning]] la mattina e [[es:hablar]] vuol dire parlare.

      ## Prova tu {try}

      ::: try
      intro_it: "Due esercizi."
      exercises:
        - text_it: "Primo esercizio: leggi e scrivi sul quaderno."
          solution_it: "Una risposta."
        - text_it: "Secondo esercizio: scrivi ancora sul quaderno."
          solution_it: "Un'altra risposta."
      :::

      ## Ascolta e rispondi {idea icon=lightbulb}

      ::: check choice
      prompt_it: "Che cosa dice la frase?"
      listen: {text_en: "She is reading a book."}
      options:
        - {id: a, text_it: "Una cosa"}
        - {id: b, text_it: "Un'altra cosa"}
      answer: a
      :::
    MD
    parsed = Lessons::Parser2.call(md, findings, allow_reserved: true)
    assert parsed&.body, findings.map(&:message).first(3).inspect
    row = draw(parsed.body)
    assert_equal "passed", row.status, dump(row)
    segments = row.segments
    assert_includes segments, seg("en", "good morning"), "the speaker beside [[en:]]"
    assert_includes segments, seg("es", "hablar")
    assert_includes segments, seg("en", "She is reading a book."), "the text of the listening check, behind «Mostra il testo»"
    assert segments.any? { |s| s["text"].include?("Primo esercizio") }, "the first exercise is on screen as drawn"
    assert segments.any? { |s| s["text"].include?("Secondo esercizio") }, "the second exercise is drawn in its own state: #{segments.inspect}"
    assert_empty segments.select { |s| s["text"].strip.empty? }
  end
end
