# frozen_string_literal: true

module Lessons
  # What the student's browser is told about a banco.lesson/2 revision (A2): a whitelist per block type and per
  # check component. Only named fields are copied, so a field added to a schema later cannot leak by accident;
  # test/fixtures/lesson2/whitelist.json lists, for every type, what is served and what is dropped, and the tests
  # fail until a new field is in one of the two columns.
  #
  # Never served: answer, accept, errors (with their messages), explain_it, final_it, solution_it, solution_steps,
  # result_it of an example with a blank, the do_it of a blank step and of every step after it, and a diagram's
  # solution fields (balance.x_value becomes a computed tilt per state). Choice options, matching columns and the
  # spans of a span_select get fresh ids in shown order (Diagnosis::Rekey, seeded per student and block), and the
  # check endpoint recomputes the same pure result to grade (Lessons::Checks).
  #
  # Pure: no database, no clock. +seed+ is the student's key ("preview" for the teacher's box).
  module StudentBody
    FRONT = %w[key kind subject title_it goals_it why_it minutes scope calculator book_it].freeze
    CHECK_COLUMNS = {
      "choice" => %w[component prompt_it answer_format_it],
      "number" => %w[component prompt_it answer_format_it input_before input_after unit],
      "fraction" => %w[component prompt_it answer_format_it input_before input_after mixed],
      "normalized_text" => %w[component prompt_it answer_format_it input_before input_after],
      "matching" => %w[component prompt_it answer_format_it reuse_right],
      "span_select" => %w[component prompt_it answer_format_it text_it]
    }.freeze
    # Simple blocks: the fields served; nested lists: {field => the fields of each element}.
    BLOCKS = {
      "text" => [ %w[n type text_it], {} ],
      "callout" => [ %w[n type kind title_it text_it], {} ],
      "math" => [ %w[n type tex], { "lines" => %w[tex note_it] } ],
      "procedure" => [ %w[n type title_it], { "steps" => %w[tag text_it example_tex] } ],
      "legend" => [ %w[n type], { "roles" => %w[role note_it question_it] } ],
      "mistake" => [ %w[n type group_it wrong_it right_it why_it], {} ],
      "summary" => [ %w[n type points_it], {} ],
      "table" => [ %w[n type caption_it header rows], {} ]
    }.freeze
    CASE_FIELDS = %w[title_it icon tone condition_it text_it example_it].freeze

    module_function

    def for(revision, seed:) = project(revision.body, revision_id: revision.id, seed: seed)

    def project(body, revision_id:, seed:)
      out = body.slice(*FRONT)
      out["hero"] = diagram(body["hero"]) if body["hero"]
      out["parts"] = Array(body["parts"]).map { |p| p.slice("n", "title_it") } if body["parts"]
      subject = body["subject"]
      out["cards"] = body["cards"].map { |card| card_json(card, subject, revision_id, seed) }
      out
    end

    def card_json(card, subject, revision_id, seed)
      out = card.slice("n", "id", "role", "level", "title_it", "short_it", "icon", "tone", "part")
      out["blocks"] = card["blocks"].map { |b| block(b, subject, seed_for(seed, revision_id, card["n"], b["n"])) }
      out
    end

    # "lesson|STUDENT|REVISION|CARD|BLOCK" (A2); more parts for the exercise or step of a check.
    def seed_for(student, revision_id, card, block, *rest)
      (%W[lesson #{student} #{revision_id} #{card} #{block}] + rest.map(&:to_s)).join("|")
    end

    def block(b, subject, seed)
      type = b["type"]
      if BLOCKS.key?(type)
        fields, nested = BLOCKS.fetch(type)
        out = b.slice(*fields)
        nested.each { |key, keep| out[key] = b[key].map { |e| e.slice(*keep) } if b[key] }
        out
      else
        case type
        when "cases" then cases(b)
        when "diagram" then b.slice("n", "type").merge("diagram" => diagram(b["diagram"]))
        when "schema" then b.slice("n", "type").merge("schema" => diagram(b["schema"]))
        when "check" then b.slice("n", "type").merge(check(b, subject, seed))
        when "example" then example(b, subject, seed)
        when "try" then try(b, subject, seed)
        when "more" then b.slice("n", "type", "title_it").merge("blocks" => b["blocks"].map { |inner| block(inner, subject, "#{seed}|#{inner['n']}") })
        else raise ArgumentError, "StudentBody does not serve a #{type.inspect} block"
        end
      end
    end

    def cases(b)
      out = b.slice("n", "type", "title_it")
      out["cases"] = b["cases"].map do |c|
        item = c.slice(*CASE_FIELDS)
        item["diagram"] = diagram(c["diagram"]) if c["diagram"]
        item
      end
      out
    end

    # ---- diagrams -----------------------------------------------------------------------------------

    # The declared drawing fields of a diagram with its states merged; the solution fields replaced by what the
    # drawing needs (balance: tilt, computed here, and x_value only when show_value is true).
    def diagram(data)
      type = data["type"]
      declared = Diagrams.schema_def(type).fetch("properties").keys
      solution = Diagrams.solution_fields(type)
      merged = Diagrams.merge_states(data)
      out = merged.slice(*declared).except(*solution)
      varying = Diagrams.state_keys(type)
      if merged["states"]
        out["states"] = merged["states"].map do |eff|
          s = eff.slice(*varying)
          s["tilt"] = tilt_of(eff) if type == "balance"
          s
        end
      elsif type == "balance"
        out["tilt"] = tilt_of(merged)
      end
      out["x_value"] = data["x_value"] if type == "balance" && data["show_value"] == true && data["x_value"]
      out["try"] = data["try"].slice("from", "to") if data["try"]
      out
    end

    def tilt_of(eff)
      Diagrams::Balance.tilt(eff["left"], eff["right"], Diagrams::Balance.x_value(eff))
    end

    # ---- checks -------------------------------------------------------------------------------------

    # The served columns of a check (or of a step blank, or an exercise check), without n and type.
    def check(c, subject, seed)
      component = c["component"]
      out = c.slice(*CHECK_COLUMNS.fetch(component))
      case component
      when "choice"
        out["options"] = Checks.rekey(c, seed).display["options"]
      when "matching"
        shown = Checks.rekey(c, seed).display
        out["left"] = shown["left"]
        out["right"] = shown["right"]
      when "span_select"
        out["spans"] = c["spans"].each_with_index.map { |s, i| { "id" => "s#{i + 1}", "text_it" => s["text_it"] } }
      when "normalized_text"
        accents = Items::Part::ACCENT_SETS[subject]
        out["accents"] = accents if accents
      end
      out
    end

    # An example: the steps up to the first blank; for that step its reason and the blank. Without a blank it is
    # served whole (result_it included). The diagram's states are cut the same way (a state shows what its step did).
    def example(b, subject, seed)
      out = b.slice("n", "type", "problem_it")
      cut = b["steps"].index { |s| s["blank"] }
      steps = b["steps"].each_with_index.map do |s, i|
        next if cut && i > cut

        item = s.slice("tag", "why_it")
        if cut == i
          item["blank"] = check(s["blank"], subject, seed_for_step(seed, i))
        else
          item["do_it"] = s["do_it"]
        end
        item
      end.compact
      out["steps"] = steps
      out["result_it"] = b["result_it"] if b["result_it"] && cut.nil?
      if b["diagram"]
        d = diagram(b["diagram"])
        d["states"] = d["states"].first(cut) if cut && d["states"]
        out["diagram"] = d
      end
      out
    end

    def seed_for_step(seed, step) = "#{seed}|step#{step}"
    def seed_for_exercise(seed, exercise, part = nil) = [ "#{seed}|ex#{exercise}", part ].compact.join("|")

    def try(b, subject, seed)
      out = b.slice("n", "type", "intro_it")
      out["exercises"] = b["exercises"].map do |e|
        item = e.slice("n", "text_it")
        item["diagram"] = diagram(e["diagram"]) if e["diagram"]
        item["check"] = check(e["check"], subject, seed_for_exercise(seed, e["n"])) if e["check"]
        item["checks"] = e["checks"].each_with_index.map { |c, k| check(c, subject, seed_for_exercise(seed, e["n"], k)) } if e["checks"]
        item
      end
      out
    end
  end
end
