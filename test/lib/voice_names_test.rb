require "test_helper"

# D-378: «Impostazioni» shows each server voice by a friendly name in the student's language, never its id (im_nicola, af_heart): every voice of
# config/banco/voices.yml has a name in Italian and English, the generated lesson/voices.js carries them, and the page's script reads them.
class VoiceNamesTest < ActiveSupport::TestCase
  CONFIG = YAML.safe_load_file(Rails.root.join("config/banco/voices.yml")).fetch("server")

  test "every server voice has a name in Italian and in English, with the language and the voice's own name, and no id" do
    ids = CONFIG.fetch("voices").values.flatten
    assert_equal ids.sort, CONFIG.fetch("names").keys.sort, "a name for each voice and for no other"
    CONFIG.fetch("names").each do |id, names|
      assert_equal %w[en it], names.keys.sort, id
      names.each_value { |name| assert_no_match(/#{Regexp.escape(id)}|_/, name, "#{id}: the id is for the machine") }
      assert_match(/\AVoce (italiana|inglese|spagnola) — \p{Upper}/, names["it"])
      assert_match(/\A(Italian|English|Spanish) voice — \p{Upper}/, names["en"])
    end
    assert_equal "Voce italiana — Nicola", CONFIG.dig("names", "im_nicola", "it")
  end

  test "the generated browser file carries the names, and the settings script uses them" do
    js = Rails.root.join("app/javascript/lesson/voices.js").read
    assert_includes js, '"names"'
    assert_includes js, "Voce italiana — Nicola"
    script = Rails.root.join("app/javascript/student_controllers/voices_controller.js").read
    assert_includes script, "this.voiceName(sample.name)"
    assert_not_includes script, "name.textContent = sample.name"
  end
end
