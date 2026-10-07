require "test_helper"
require_relative "../support/decision_world"

# D-218: every skill key and item key on the teacher's pages is a reference (the Italian
# name, the key, an info button with a native popover) and has a permalink page.
class TeacherRefsTest < ActionDispatch::IntegrationTest
  include DecisionWorld

  setup { build_decision_world }

  def page(path, headers: TEACHER) = on(:web, path, headers: headers, remote_addr: EDGE)

  def pages
    rev = @world[:revisions]["number"]
    [ "/teacher", "/teacher/subjects/math/graph", "/teacher/subjects/math/test", "/teacher/subjects/math/test/all",
      "/teacher/subjects/math/test/skills/math.number", "/teacher/subjects/math/report", "/teacher/corrections",
      "/teacher/items/#{rev.id}", "/teacher/items/#{rev.id}/play", "/teacher/refs/math.number", "/teacher/refs/#{rev.item.key}" ]
  end

  test "a skill reference shows the name, the key and a button that targets its own popover" do
    page "/teacher/subjects/math/test/skills/math.number"
    assert_response :success
    assert_select "h1 .ref[data-ref=skill][data-ref-key='math.number']" do
      assert_select ".ref-name", "Abilità number"
      assert_select ".key", "(math.number)"
      assert_select "button.ref-info[popovertarget][popovertargetaction=toggle][type=button][aria-label]"
    end
    id = css_select("h1 .ref-info").first["popovertarget"]
    assert_select "body > div##{id}[popover=auto][role=dialog]" do
      assert_select "[data-ref-card=skill]"
      assert_select "dd", /Studiata/
      assert_select "dd", /2 domande|Una domanda/
      assert_select "a[href='/teacher/subjects/math/graph#skill-math-number']"
      assert_select "a[href='/teacher/subjects/math/test/skills/math.number']"
      assert_select "a[href='/teacher/subjects/math/test/all#skill-math-number']"
      assert_select "a[href='/teacher/refs/math.number']"
    end
  end

  test "an item reference names the question after its skill and its component" do
    rev = @world[:revisions]["number"]
    page "/teacher/subjects/math/test/skills/math.number"
    assert_select "article[data-item='#{rev.item.key}'] h2 .ref[data-ref=item]" do
      assert_select ".ref-name", "Domanda su: Abilità number (risposta numerica)"
      assert_select ".key", "(#{rev.item.key})"
    end
    id = css_select("article[data-item='#{rev.item.key}'] h2 .ref-info").first["popovertarget"]
    assert_select "div##{id}[popover]" do
      assert_select "dd", "risposta numerica"
      assert_select "dd", /il test usa questa revisione/
      assert_select "a[href='/teacher/items/#{rev.id}']"
      assert_select "a[href='/teacher/items/#{rev.id}/play']"
      assert_select "a[href='/teacher/subjects/math/test/all#item-#{rev.id}']"
    end
    page "/teacher/subjects/math/test/all"
    assert_select "article#item-#{rev.id}"
  end

  test "ids are unique on every page, even when a key repeats" do
    pages.each do |path|
      page path
      assert_response :success, path
      ids = css_select("[id^=refpop-]").map { |e| e["id"] }
      assert_equal ids.uniq.size, ids.size, "#{path}: duplicate ids #{ids.tally.select { |_, n| n > 1 }.keys}"
      css_select("[popovertarget]").each { |b| assert_select "[popover]##{b['popovertarget']}", 1, "#{path}: no popover for #{b['popovertarget']}" }
    end
    # The same key twice on one page: two buttons, two popovers.
    page "/teacher/subjects/math/graph"
    buttons = css_select(".ref[data-ref-key='math.number'] .ref-info")
    assert_operator buttons.size, :>=, 1
    assert_equal buttons.map { |b| b["popovertarget"] }.uniq.size, buttons.size
  end

  test "no script handler is written into the pages and the popovers need none" do
    pages.each do |path|
      page path
      assert_select "*" do |all|
        all.each { |e| e.attributes.each_key { |a| flunk "#{path}: #{e.name} has #{a}" if a.start_with?("on") } }
      end
      assert_select "script:not([src]):not([nonce])", 0, path
    end
  end

  test "no heading shows an item key without the reference around it" do
    keys = Item.pluck(:key)
    pages.each do |path|
      page path
      css_select("h1, h2, h3, h4").each do |h|
        next unless keys.any? { |k| h.text.include?(k) }

        assert h.css(".ref").any?, "#{path}: bare item key in #{h.text.squish}"
      end
    end
  end

  test "the permalink shows the whole card of a skill and of an item" do
    page "/teacher/refs/math.number"
    assert_response :success
    assert_select "h1", /Abilità number.*\(math\.number\)/
    assert_select "[data-ref-card=skill] dt", "Domande nel test"
    assert_select "button.ref-info", 0 # the card on its own page has no popover of itself
    rev = @world[:revisions]["number"]
    page "/teacher/refs/#{rev.item.key}"
    assert_response :success
    assert_select "h1", /Domanda su: Abilità number \(risposta numerica\)/
    assert_select "[data-ref-card=item] dt", "Varianti"
    assert_select "[data-ref-card=item] dd", "#{rev.instances.count}"
    assert_select "[data-ref-card=item] .ref[data-ref=skill][data-ref-key='math.number']"
  end

  test "an unknown key is a 404 page in Italian, and the page is for the teacher only" do
    [ "/teacher/refs/math.nothing", "/teacher/refs/nothing-here" ].each do |path|
      page path
      assert_response :not_found
      assert_select "h1", "Non trovato"
      assert_select ".notice", /Nessuna abilità o domanda ha la chiave/
    end
    page "/teacher/refs/math.number", headers: { "Remote-User" => "student", "Remote-Groups" => "banco-student" }
    assert_response :forbidden
    on(:api, "/teacher/refs/math.number")
    assert_response :not_found
  end
end
