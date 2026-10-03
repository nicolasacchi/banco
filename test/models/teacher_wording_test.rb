require "test_helper"

# The gate's English sentences, said to the teacher in Italian; what is unknown stays visible.
class TeacherWordingTest < ActiveSupport::TestCase
  W = Teacher::Wording

  test "the gate's reasons are worded in Italian, with the item's key where it is known" do
    names = { 7 => "math-number-1" }
    assert_equal "Prima approva il grafo su cui poggia questo test.", W.italian("the graph revision 3 of this test is not approved")
    assert_equal "math-number-1: Il controllo meccanico non è passato. Manca la prova alla cieca.",
                 W.italian("item revision 7 is not approvable: validation has not passed; no blind solve on this revision", names)
    assert_equal "Apri la schermata dell'abilità dell'item math-number-1.", W.italian("item revision 7 was not opened in the preview", names)
    assert_equal "Apri la schermata dell'abilità dell'item revisione 9.", W.italian("item revision 9 was not opened in the preview", names)
    assert_equal "2 rilievi gravi senza una tua decisione.", W.italian("2 blocker or major finding(s) without the teacher's disposition")
    assert_equal "Hai rimandato questa revisione: serve una revisione nuova.", W.italian("the teacher sent this revision back: a new revision is needed")
    assert_equal "Scrivi il motivo.", W.italian("a reason is required")
  end

  test "a sentence it does not know is shown as it is" do
    assert_equal "something new went wrong", W.italian("something new went wrong")
  end
end
