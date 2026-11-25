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
    # D-402: a field `foo_it` of a bilingual revision has its target sibling `foo_en` / `foo_es`, and the projection serves it with it (the whitelist
    # fixture lists the columns of the schema as it is; the siblings are derived from it, as Banco::Schemas::Bilingual derives the schema). A legacy
    # revision has no sibling, so nothing more is served for it. The R2 twins (`header_it`, `rows_it` of a table: the bare key holds the target text) have none.
    R2_TWINS = %w[header_it rows_it].freeze
    WIDE = lambda do |fields|
      fields.flat_map { |f| (base = f[/\A(.+)_it\z/, 1]) && !Bilingual::EXEMPT.include?(base) && !R2_TWINS.include?(f) ? [ f, "#{base}_en", "#{base}_es" ] : [ f ] }.uniq.freeze
    end
    # D-402: the marker `translate_material: false` of a check, a `try` exercise, a `table` block or figure goes with the served text: the form material of it has
    # no Italian text (the fold serves it in the `_it` slot with no `tr` entry), and the page does not ask for a translation of it. Not in the whitelist fixture:
    # like the siblings it is a column of the derived schema (Banco::Schemas::Bilingual::MATERIAL_AT). The same goes for the check's own `sentence_<lang>`
    # (Bilingual::SENTENCE, SENTENCE_AT): its column `sentence_it` is served with its siblings, and the fold puts the target text in that slot.
    MATERIAL = Bilingual::MARKER
    SENTENCE = "sentence_it"
    FRONT = WIDE.call(%w[key kind subject title_it goals_it why_it minutes scope calculator book_it])
    CHECK_COLUMNS = {
      "choice" => %w[component prompt_it answer_format_it listen],
      "number" => %w[component prompt_it answer_format_it input_before input_after unit],
      "fraction" => %w[component prompt_it answer_format_it input_before input_after mixed],
      "normalized_text" => %w[component prompt_it answer_format_it input_before input_after input],
      "matching" => %w[component prompt_it answer_format_it reuse_right listen],
      "span_select" => %w[component prompt_it answer_format_it text_it text_en text_es listen],
      "select" => %w[component prompt_it answer_format_it targets pick],
      "tiles" => %w[component prompt_it answer_format_it builds],
      "ordering" => %w[component prompt_it answer_format_it]
    }.transform_values { |fields| (WIDE.call(fields) + [ MATERIAL, *WIDE.call([ SENTENCE ]) ]).freeze }.freeze
    # Simple blocks: the fields served; nested lists: {field => the fields of each element}.
    BLOCKS = {
      "text" => [ %w[n type text_it], {} ],
      "callout" => [ %w[n type kind title_it text_it], {} ],
      "math" => [ %w[n type tex], { "lines" => %w[tex note_it] } ],
      "procedure" => [ %w[n type title_it], { "steps" => %w[tag text_it example_tex] } ],
      "legend" => [ %w[n type], { "roles" => %w[role note_it question_it] } ],
      "mistake" => [ %w[n type group_it wrong_it right_it why_it], {} ],
      "summary" => [ %w[n type points_it], {} ],
      "table" => [ %w[n type caption_it header rows header_it rows_it translate_material], {} ],
      # wave 2, the docs family (T8): teaching content, served whole (L8); the oral and the compare of a source are special below
      "source" => [ %w[n type kind title_it ref open author_it year about_year for_whom_it where_it translation original], { "parts" => %w[text_it plain_it marks], "guide" => %w[span_it note_it] } ],
      "reveal" => [ %w[n type prompt_it answer_it year who_it situation_it real_it], { "options" => %w[id text_it then_it real] } ],
      # words (T3): the glosses are teaching content, served whole (L8), and read aloud only after the student opens them
      "dialogue" => [ %w[n type title_it speakers transcript], { "lines" => %w[speaker text_en text_es gloss_it] } ],
      # release 2 (D-290): a free page pin; `for` adds the server's `view` (poster, texts, shell address) from the page revision
      "page" => [ %w[n type page revision caption_it], {} ],
      # release 2 (D-329): a whole program for S to copy; it is never graded and holds no answer, so every field is served
      "code" => [ %w[n type lang title_it text input_it output note_it], {} ]
    }.transform_values { |fields, nested| [ WIDE.call(fields), nested.transform_values { |keep| WIDE.call(keep) }.freeze ].freeze }.freeze
    SOURCE_COMPARE = WIDE.call(%w[title_it author_it year about_year for_whom_it where_it translation original])
    CASE_FIELDS = WIDE.call(%w[title_it icon tone condition_it text_it example_it])

    module_function

    # The fields of +fields+ with their target siblings (WIDE), for the places that slice by name.
    def wide(fields) = WIDE.call(fields)

    # Pure except for the page blocks (D-290): their `view` is read from the page revision (Pages::Served), the one place that
    # asks the database.
    def for(revision, seed:) = project(revision.body, revision_id: revision.id, seed: seed, pages: Pages::Served)

    # +pages+: an object with view(block, student:) -> Hash, or nil (a page block is then served without its view).
    # A bilingual revision (D-402) is served with the target text in the `_it` slots the renderer reads and its Italian in the `tr` tables of the body,
    # the card and the block (Lessons::Bilingual.fold), after the choice options are re-keyed (their ids and shown order are unchanged).
    def project(body, revision_id:, seed:, pages: nil)
      out = body.slice(*FRONT)
      out["hero"] = diagram(body["hero"]) if body["hero"]
      out["parts"] = Array(body["parts"]).map { |p| p.slice(*WIDE.call(%w[n title_it])) } if body["parts"]
      out["glossary"] = body["glossary"].map { |g| g.slice(*WIDE.call(%w[term_it def_it example_it])) } if body["glossary"]
      subject = body["subject"]
      out["cards"] = body["cards"].map { |card| card_json(card, subject, revision_id, seed) }
      if pages
        out["cards"].each { |card| card["blocks"].each { |b| b["view"] = pages.view(b, student: seed) if b["type"] == "page" } }
      end
      folded(out, body)
    end

    # The language of a bilingual revision's text ("en", "es"), nil for a legacy one (its flag is the front matter's `bilingual`).
    def lang_of(body) = body["bilingual"] == true ? Lang.target(body["subject"]) : nil

    def folded(out, body)
      lang = lang_of(body)
      lang ? Bilingual.fold(out, lang) : out
    end

    SCHEMA_FRONT = WIDE.call(%w[key kind subject title_it minutes])

    # The schema page of a topic (D-372): the projection of the core summary card alone, the `summary` block and the `schema`, with the
    # glossary the card's words need. It is `project`'s own card (the same blocks, the same whitelist), so nothing more is served than
    # the lesson serves; nil when the body has no summary card (a lesson/2 always has one: E-LESSON-MAP).
    def schema(body, revision_id:, seed:)
      card = body["cards"].find { |c| c["role"] == "summary" && c["level"] == "core" } or return nil
      out = body.slice(*SCHEMA_FRONT)
      out["glossary"] = body["glossary"].map { |g| g.slice(*WIDE.call(%w[term_it def_it example_it])) } if body["glossary"]
      out["cards"] = [ card_json(card, body["subject"], revision_id, seed) ]
      folded(out, body)
    end

    def card_json(card, subject, revision_id, seed)
      out = card.slice(*WIDE.call(%w[n id role level title_it short_it icon tone part]))
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
        out["compare"] = compare(b["compare"]) if type == "source" && b["compare"]
        out
      else
        case type
        when "cases" then cases(b)
        when "diagram" then b.slice("n", "type").merge("diagram" => diagram(b["diagram"]))
        when "schema" then b.slice("n", "type").merge("schema" => diagram(b["schema"]))
        when "oral" then oral(b, seed)
        when "check" then b.slice("n", "type").merge(check(b, subject, seed))
        when "example" then example(b, subject, seed)
        when "try" then try(b, subject, seed)
        when "more" then b.slice(*WIDE.call(%w[n type title_it])).merge("blocks" => b["blocks"].map { |inner| block(inner, subject, "#{seed}|#{inner['n']}") })
        else raise ArgumentError, "StudentBody does not serve a #{type.inspect} block"
        end
      end
    end

    def compare(c)
      out = c.slice(*SOURCE_COMPARE)
      out["parts"] = c["parts"].map { |part| part.slice(*WIDE.call(%w[text_it plain_it marks])) }
      out["guide"] = c["guide"].map { |g| g.slice(*WIDE.call(%w[span_it note_it])) } if c["guide"]
      out
    end

    # An oral: the question, the outline tiles shuffled (ids e1..eN in shown order, like an ordering), the connectives and the terms to
    # say. The key, the typical errors and the model answer stay on the server; the check endpoint grades the outline.
    def oral(b, seed)
      out = b.slice(*WIDE.call(%w[n type question_it connectives terms]))
      out["outline"] = Checks.rekey(Oral.check(b), seed).display["elements"]
      out
    end

    def cases(b)
      out = b.slice(*WIDE.call(%w[n type title_it]))
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
    # D-402: a figure with pairs (`label_en` + `label_it`...) is served as the lesson is: the target text in the `_it` slots every type already reads, and
    # the Italian in the figure's own `tr` table {target => Italian}, which the figure's translation panel lists. A legacy figure is served as it was.
    def diagram(data) = translated_figure(data) { |view| Diagrams.served(view) || diagram_generic(view) }

    def translated_figure(data)
      folded = Bilingual.fold(data, nil)
      out = yield folded.except("lang", "tr")
      folded["tr"] ? out.merge("tr" => folded["tr"]) : out
    end

    # What every type is served as unless its module serves it itself (Diagrams.served): the declared fields, the states merged, the
    # solution fields out.
    def diagram_generic(data)
      type = data["type"]
      declared = Diagrams.schema_def(type).fetch("properties").keys
      declared += R2_TWINS + [ MATERIAL ] if type == "table" # the Italian of a table's cells, next to the cells in the subject's language (D-402), and the marker that has none
      declared += [ MATERIAL ] if type == "concept_map" # the marker of a map whose nodes are verb forms with no Italian (D-402, round 6)
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
      out["try"] = data["try"].slice("from", "to") if type == "balance" && data["try"]
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
        key = Blocks::Check::TEXT_KEYS.find { |k| c.key?(k) } || "text_it"
        out["spans"] = c["spans"].each_with_index.map { |s, i| { "id" => "s#{i + 1}", key => s[key] } }
      when "tiles" then out["tiles"] = Checks.rekey(c, seed).display["elements"]
      when "ordering" then out["items"] = Checks.rekey(c, seed).display["elements"]
      when "select" then out["diagram"] = select_figure(c)
      when "number"
        # a whole-number key (and every accepted form whole): the box does not tell about decimals. A boolean about the key's kind, never the key.
        out["integer"] = true if whole?(c["answer"]) && Array(c["accept"]).all? { |v| whole?(v) }
      when "normalized_text"
        accents = Items::Part::ACCENT_SETS[subject]
        out["accents"] = accents if accents
        # input: bits is the switches of a register (T9): they are served with the width of the profile; an error under test that the
        # switches would make impossible (padding_missing: the answer is too short) keeps the typed input
        if c["input"] == "bits"
          if Checks.bits_switches?(c) then out["input_width"] = c.dig("profile", "width")
          else out.delete("input")
          end
        end
      end
      out
    end

    def whole?(value) = value.to_s.strip.match?(/\A[-\u2212]?\d+\z/)

    # The figure of a select check as the student sees it: the type's own "select" projection (targets in reading order, every
    # candidate in one neutral style, no label that names one: L3). A type that cannot give it is never served as if it could.
    def select_figure(check)
      mod = SelectTargets.module_of(check) or raise ArgumentError, "select check on an unknown diagram type"
      raise NotImplementedError, "#{check.dig('diagram', 'type')} has no select projection" unless mod.is_a?(Diagrams::Contract)

      # the check's own target set goes with the figure: a type that offers more than one set (map: areas, places, bands...)
      # must serve and describe the set the check taps, not the first one it happens to have
      takes_set = mod.method(:served).parameters.any? { |kind, name| kind == :keyrest || name == :set }
      translated_figure(check["diagram"]) { |view| takes_set ? mod.served(view, mode: :select, set: check["targets"]) : mod.served(view, mode: :select) }
    end

    # An example: the steps up to the first blank; for that step its reason and the blank. Without a blank it is
    # served whole (result_it included). The diagram's states are cut the same way (a state shows what its step did).
    def example(b, subject, seed)
      out = b.slice(*WIDE.call(%w[n type problem_it]))
      cut = b["steps"].index { |s| s["blank"] }
      steps = b["steps"].each_with_index.map do |s, i|
        next if cut && i > cut

        item = s.slice(*WIDE.call(%w[tag why_it]))
        if cut == i
          item["blank"] = check(s["blank"], subject, seed_for_step(seed, i))
        else
          item.merge!(s.slice(*WIDE.call(%w[do_it])))
        end
        item
      end.compact
      out["steps"] = steps
      out["steps_total"] = b["steps"].size # the page's counter «passo N di M» counts every step, the ones after the blank included
      out.merge!(b.slice(*WIDE.call(%w[result_it]))) if cut.nil?
      if b["diagram"]
        d = diagram(b["diagram"])
        d = cut_states(d, cut) if cut && d["states"]
        out["diagram"] = d
      end
      out
    end

    # The states up to the blank step. A figure with states has at least two (schema minItems 2): with one state left that state is the
    # figure, with none the figure is drawn as its base, so that the page never gets a states list the browser refuses (a blank at step 1 or 2).
    def cut_states(d, cut)
      kept = d["states"].first(cut)
      return d.merge("states" => kept) if kept.size >= 2

      d = d.except("states")
      kept.size == 1 ? d.merge(kept.first) : d
    end

    def seed_for_step(seed, step) = "#{seed}|step#{step}"
    def seed_for_exercise(seed, exercise, part = nil) = [ "#{seed}|ex#{exercise}", part ].compact.join("|")

    def try(b, subject, seed)
      out = b.slice(*WIDE.call(%w[n type intro_it]))
      out["exercises"] = b["exercises"].map do |e|
        item = e.slice(*WIDE.call(%w[n text_it]), MATERIAL)
        item["diagram"] = diagram(e["diagram"]) if e["diagram"]
        # an exercise that says the material has no translation says it of its checks too: the page reads the marker of the check it draws
        inner = e[MATERIAL] == false ? { MATERIAL => false } : {}
        item["check"] = check(e["check"], subject, seed_for_exercise(seed, e["n"])).merge(inner) if e["check"]
        item["checks"] = e["checks"].each_with_index.map { |c, k| check(c, subject, seed_for_exercise(seed, e["n"], k)).merge(inner) } if e["checks"]
        item
      end
      out
    end
  end
end
