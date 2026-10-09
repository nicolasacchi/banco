# Random banco.lesson/2 bodies for the property tests: every block type, every check component, blanks at every step
# position, and a unique sentinel (ANS-<hex>) in every answer-side field. Not validated lessons: the projection must hold
# for any body of the shape, whatever its text.
module Lesson2Random
  Result = Struct.new(:body, :sentinels, keyword_init: true)

  module_function

  def build(seed)
    rng = Random.new(seed)
    sentinels = []
    ans = -> { "ANS-#{format('%08x', rng.rand(2**32))}#{sentinels.size}".tap { |s| sentinels << s } }
    cards = Array.new(rng.rand(3..7)) { |i| card(rng, ans, i + 1) }
    hero = rng.rand < 0.5 ? balance(rng, ans) : nil
    body = { "schema" => "banco.lesson/2", "schema_version" => 2, "key" => "ripasso.math.demo-random", "kind" => "ripasso", "subject" => "math",
             "title_it" => "Prova", "goals_it" => [ "**Fare** una prova" ], "why_it" => "Perché sì. Perché no.", "skills" => [ "math.demo-equation" ], "uses" => [],
             "refs" => [ { "source" => "x", "line" => 1, "fragment" => "y", "role" => "taught_in" } ], "scope" => "studied", "minutes" => 20, "calculator" => false,
             "cards" => cards, "words" => { "core" => 0, "extra" => 0 }, "pages" => [] }
    body["hero"] = hero if hero
    Result.new(body: body, sentinels: sentinels)
  end

  def card(rng, ans, n)
    blocks = Array.new(rng.rand(1..5)) { |j| block(rng, ans, j + 1) }
    { "n" => n, "id" => "c#{n}", "role" => "idea", "level" => "core", "title_it" => "Scheda #{n}", "icon" => "lightbulb", "line" => 10 * n, "blocks" => blocks }
  end

  def block(rng, ans, n)
    kinds = %w[text callout math procedure cases legend example mistake check summary schema diagram table try more]
    send("b_#{kinds.sample(random: rng)}", rng, ans, n)
  end

  def b_text(_r, _a, n) = { "n" => n, "type" => "text", "text_it" => "Un testo.", "line" => 3 }
  def b_callout(_r, _a, n) = { "n" => n, "type" => "callout", "kind" => "tip", "text_it" => "Breve.", "line" => 3 }
  def b_math(r, _a, n) = r.rand < 0.5 ? { "n" => n, "type" => "math", "tex" => "x = 1", "line" => 3 } : { "n" => n, "type" => "math", "lines" => [ { "tex" => "a" }, { "tex" => "b", "note_it" => "poi" } ], "line" => 3 }
  def b_procedure(_r, _a, n) = { "n" => n, "type" => "procedure", "steps" => [ { "tag" => "move", "text_it" => "Sposta.", "example_tex" => "x" }, { "tag" => "divide", "text_it" => "Dividi." } ], "line" => 3 }
  def b_legend(_r, _a, n) = { "n" => n, "type" => "legend", "roles" => [ { "role" => "unknown" }, { "role" => "known", "note_it" => "n" } ], "line" => 3 }
  def b_summary(_r, _a, n) = { "n" => n, "type" => "summary", "points_it" => %w[Uno Due Tre], "line" => 3 }
  def b_table(_r, _a, n) = { "n" => n, "type" => "table", "header" => %w[A B], "rows" => [ %w[1 2] ], "line" => 3 }
  def b_mistake(_r, ans, n) = { "n" => n, "type" => "mistake", "wrong_it" => "no", "right_it" => "sì", "why_it" => "perché", "code" => ans.call, "line" => 3 }
  def b_schema(_r, _a, n) = { "n" => n, "type" => "schema", "schema" => { "type" => "table", "alt_it" => "tabella", "header" => %w[A], "rows" => [ %w[1] ] }, "line" => 3 }
  def b_diagram(r, a, n) = { "n" => n, "type" => "diagram", "diagram" => balance(r, a), "line" => 3 }

  def b_cases(r, a, n)
    { "n" => n, "type" => "cases", "cases" => Array.new(2) { |i| { "title_it" => "Caso #{i}", "text_it" => "t", "diagram" => (balance(r, a) if r.rand < 0.5) }.compact }, "line" => 3 }
  end

  def b_more(r, a, n)
    { "n" => n, "type" => "more", "title_it" => "Di più", "blocks" => [ b_text(r, a, 1), b_diagram(r, a, 2) ], "line" => 3 }
  end

  def balance(rng, ans)
    left = { "x" => rng.rand(1..3), "units" => rng.rand(0..4) }
    right = { "units" => rng.rand(5..9) }
    d = { "type" => "balance", "alt_it" => "una bilancia con tanti pesi e scatole", "left" => left, "right" => right, "x_value" => ans.call }
    d["show_value"] = false
    d["try"] = { "from" => 0, "to" => 5 } if rng.rand < 0.5
    d["states"] = [ { "op_it" => "uno" }, { "op_it" => "due", "left" => { "x" => 1 } } ] if rng.rand < 0.5
    d
  end

  def check_error(ans, answer)
    { "answer" => answer, "code" => ans.call, "message_it" => ans.call }
  end

  def check(rng, ans)
    base = { "prompt_it" => "Domanda?", "explain_it" => ans.call }
    case %w[choice number fraction normalized_text matching span_select].sample(random: rng)
    when "choice"
      ids = %w[a b c d].first(rng.rand(2..4))
      base.merge("component" => "choice", "options" => ids.map { |i| { "id" => i, "text_it" => "Opzione #{i}" } }, "answer" => ans.call, "errors" => [ check_error(ans, ids.last) ])
    when "number" then base.merge("component" => "number", "answer" => ans.call, "errors" => [ check_error(ans, ans.call) ], "unit" => "cm")
    when "fraction" then base.merge("component" => "fraction", "answer" => ans.call, "mixed" => false, "errors" => [ check_error(ans, ans.call) ])
    when "normalized_text" then base.merge("component" => "normalized_text", "answer" => ans.call, "accept" => [ ans.call ], "errors" => [ check_error(ans, ans.call) ])
    when "matching"
      base.merge("component" => "matching", "left" => [ { "id" => "l1", "text_it" => "uno" }, { "id" => "l2", "text_it" => "due" } ],
                 "right" => [ { "id" => "r1", "text_it" => "A" }, { "id" => "r2", "text_it" => "B" } ], "answer" => { "l1" => ans.call, "l2" => ans.call }, "errors" => [ check_error(ans, { "l1" => ans.call }) ])
    else
      base.merge("component" => "span_select", "text_it" => "Marco legge", "spans" => [ { "id" => "s1", "text_it" => "Marco" }, { "id" => "s2", "text_it" => "legge" } ], "answer" => [ ans.call ], "errors" => [ check_error(ans, [ ans.call ]) ])
    end
  end

  def b_check(rng, ans, n) = check(rng, ans).merge("n" => n, "type" => "check", "line" => 3)

  def b_example(rng, ans, n)
    count = rng.rand(2..8)
    blank = rng.rand < 0.7 ? rng.rand(0...count) : nil
    steps = Array.new(count) do |i|
      s = { "tag" => "move", "do_it" => "passo #{i}", "why_it" => "perché #{i}" }
      if blank && i == blank
        s["do_it"] = ans.call
        s["blank"] = check(rng, ans).tap { |c| c["component"] = "number"; c["answer"] = ans.call; c.delete_if { |k, _| %w[options left right spans text_it accept mixed].include?(k) } }
      elsif blank && i > blank
        s["do_it"] = ans.call
        s["why_it"] = ans.call
      end
      s
    end
    block = { "n" => n, "type" => "example", "problem_it" => "Problema", "steps" => steps, "line" => 3 }
    block["result_it"] = blank ? ans.call : "Fine."
    block["diagram"] = balance(rng, ans) if rng.rand < 0.3
    block
  end

  def b_try(rng, ans, n)
    exercises = Array.new(rng.rand(1..4)) do |i|
      e = { "n" => i + 1, "text_it" => "Esercizio #{i}", "final_it" => ans.call }
      rng.rand < 0.5 ? e["solution_it"] = ans.call : e["solution_steps"] = [ { "do_it" => ans.call, "why_it" => ans.call }, { "do_it" => ans.call, "why_it" => ans.call } ]
      case rng.rand(3)
      when 0 then e["check"] = check(rng, ans)
      when 1 then e["checks"] = Array.new(rng.rand(1..3)) { check(rng, ans) }
      end
      e
    end
    { "n" => n, "type" => "try", "intro_it" => "Su", "exercises" => exercises, "line" => 3 }
  end
end
