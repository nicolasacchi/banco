require "test_helper"

# The `dialogue` block (WAVE2 2.6, T3): the rules the schema cannot hold, what is served to the student, and the apparatus words it adds.
class LessonsDialogueTest < ActiveSupport::TestCase
  BLOCK = {
    "n" => 1, "type" => "dialogue", "title_it" => "Ascolta Ana e Luis",
    "speakers" => [ { "id" => "a", "name" => "Ana", "voice" => 1 }, { "id" => "l", "name" => "Luis", "voice" => 2 } ],
    "transcript" => "shown",
    "lines" => [
      { "speaker" => "a", "text_es" => "¿Me das el libro, por favor?", "gloss_it" => "Mi dai il libro, per favore?" },
      { "speaker" => "l", "text_es" => "Sí, te lo doy ahora.", "gloss_it" => "Sì, te lo do adesso." }
    ]
  }.freeze

  def run_check(block, subject: "spanish")
    findings = Validation::Findings.new
    ctx = Lessons::Blocks::Context.new(subject: subject, findings: findings)
    ctx.at("/cards/0/blocks/0", 7) { Lessons::Blocks::Dialogue.check(block, ctx) }
    findings.map { |f| [ f.code, f.field ] }
  end

  def with(**changes) = BLOCK.merge(changes.transform_keys(&:to_s))

  def line(text, speaker: "a", key: "text_es") = { "speaker" => speaker, key => text, "gloss_it" => "x" }

  test "a good dialogue passes, and it passes the block's schema" do
    assert_empty run_check(BLOCK)
  end

  test "one language for the dialogue, and a subject that teaches it" do
    assert_includes run_check(BLOCK, subject: "english").map(&:first), "E-LESSON-LANG"
    both = with(lines: [ line("Hola"), line("Hello", speaker: "l", key: "text_en") ])
    assert_includes run_check(both).map(&:first), "E-LESSON-LANG"
    two = with(lines: [ BLOCK["lines"][0].merge("text_en" => "Hello"), BLOCK["lines"][1] ])
    assert_includes run_check(two), [ "E-LESSON-BLOCK", "/cards/0/blocks/0/lines/0" ]
  end

  test "a line is at most 12 words (E-READ) and the tilde of a Spanish line is warned about, not refused" do
    long = with(lines: [ line("uno dos tres cuatro cinco seis siete ocho nueve diez once doce trece"), BLOCK["lines"][1] ])
    assert_includes run_check(long), [ "E-READ", "/cards/0/blocks/0/lines/0/text_es" ]
    tilde = with(lines: [ line("Ayer fué largo."), BLOCK["lines"][1] ])
    assert_equal [ [ "W-ES-TILDE", "/cards/0/blocks/0/lines/0/text_es" ] ], run_check(tilde)
    assert_empty run_check(with(lines: [ line("¿Dónde está tu papá? Sí, también aquí."), BLOCK["lines"][1] ]))
  end

  test "speakers: ids and names and voices differ, every line has a real speaker, every speaker speaks" do
    assert_includes run_check(with(speakers: [ { "id" => "a", "name" => "Ana" }, { "id" => "a", "name" => "Luis" } ])).map(&:last), "/cards/0/blocks/0/speakers"
    assert_includes run_check(with(speakers: [ { "id" => "a", "name" => "Ana" }, { "id" => "l", "name" => "Ana" } ])).map(&:last), "/cards/0/blocks/0/speakers"
    assert_includes run_check(with(speakers: [ { "id" => "a", "name" => "Ana", "voice" => 1 }, { "id" => "l", "name" => "Luis", "voice" => 1 } ])).map(&:last), "/cards/0/blocks/0/speakers"
    assert_includes run_check(with(lines: [ line("Hola"), line("Adiós", speaker: "z") ])), [ "E-LESSON-BLOCK", "/cards/0/blocks/0/lines/1/speaker" ]
    assert_includes run_check(with(lines: [ line("Hola"), line("Adiós") ])).map(&:last), "/cards/0/blocks/0/lines", "a monologue"
    three = with(speakers: BLOCK["speakers"] + [ { "id" => "m", "name" => "Marta" } ])
    assert_includes run_check(three), [ "E-LESSON-BLOCK", "/cards/0/blocks/0/speakers/2" ]
  end

  test "the lines are apparatus words open by default, unless the transcript starts hidden; the glosses are not" do
    assert_equal 11, Lessons::Blocks.apparatus_words(BLOCK)
    assert_equal 0, Lessons::Blocks.apparatus_words(BLOCK.merge("transcript" => "hidden"))
  end

  test "a mirror's rows are apparatus words too, a piece written joined counts as one word" do
    mirror = { "type" => "diagram", "diagram" => { "type" => "mirror", "rows" => [ { "pieces_it" => [ "Glie+lo", "do" ], "pieces_es" => [ "Se", "lo", "doy" ] } ] } }
    assert_equal 5, Lessons::Blocks.apparatus_words(mirror)
  end

  test "a dialogue is served whole to the student (L8): speakers, lines and glosses, nothing else" do
    served = Lessons::StudentBody.block(BLOCK.merge("line" => 9, "secret" => "ANS-1"), "spanish", "seed")
    assert_equal %w[n speakers title_it transcript type lines].sort, served.keys.sort
    assert_equal %w[gloss_it speaker text_es], served["lines"][0].keys.sort
    assert_equal "Sì, te lo do adesso.", served["lines"][1]["gloss_it"]
  end

  test "the Spanish tilde warnings come from the engine" do
    assert_equal [ "fué" ], Lessons::Words.tilde_warnings("Ayer fué largo, ¿dónde está?")
    assert_empty Lessons::Words.tilde_warnings("María se fue con papá y también con él.")
  end
end
