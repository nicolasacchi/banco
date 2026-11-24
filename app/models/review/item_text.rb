module Review
  # What a reviewer or a blind solver may see of an item revision, and the text a
  # review finding may quote (A-05): item.json, the instances shown (8 of a
  # generator item for the solver, every stored instance for the reviewer) and the programme lines the
  # item's skill cites. Never generator.mjs, verify.mjs, or another reviewer's work.
  class ItemText
    INSTANCES_OF_GENERATOR = 8
    # The texts of a bilingual item are written twice, under `<base>_it` and `<base>_en|_es` (D-402).
    SIBLINGS = %w[_it _en _es].freeze

    attr_reader :revision

    # all: true lists every stored instance of a generator item (the reviewer, D-133);
    # the blind solver keeps the first INSTANCES_OF_GENERATOR.
    def initialize(revision, all: false)
      @revision = revision
      @all = all
    end

    def body = @body ||= JSON.parse(revision.body_json)

    def practice? = body["kind"] == "practice_item"

    def generated? = body["generator"].present?

    # Instance rows in the order the reviewer sees them; position + 1 is the number
    # findings and answers use ("instance": 1 is the first).
    def instances
      @instances ||= begin
        rows = revision.instances.order(:id)
        generated? && !@all ? rows.limit(INSTANCES_OF_GENERATOR).to_a : rows.to_a
      end
    end

    def instance_row(number) = number.is_a?(Integer) && number >= 1 ? instances[number - 1] : nil

    # {instance, display, answer, errors, solution} for the reviewer. A bilingual item shows both layers (the display and the solution hold the
    # target text and its Italian side by side, D-402); an instance's own hints are `hints_it` for a legacy item and `hints_<lang>` + `hints_it`
    # for a bilingual one.
    def review_instances
      instances.each_with_index.map do |row, i|
        hints = row.hints_json.present? ? JSON.parse(row.hints_json) : nil
        { instance: i + 1, display: figures.mark(with_passage(JSON.parse(row.display_json)), i + 1, keep: true), answer: JSON.parse(row.answer_json),
          errors: row.errors_json.present? ? JSON.parse(row.errors_json) : nil,
          solution: row.solution_json.present? ? JSON.parse(row.solution_json) : nil,
          accept: row.accept_json.present? ? JSON.parse(row.accept_json) : nil,
          **(hints.is_a?(Hash) ? hints.symbolize_keys : { hints_it: hints }) }.compact
      end
    end

    # {instance, display} for the blind solver: nothing that holds the key. The solver stands for the student with the translation open, so it
    # reads both layers, except the Italian of a reading passage, the item's or the instance's own (display.passage_*): the student has no translation of
    # the passage before he has answered (a bilingual passage is `passage_<lang>` + `passage_it`), so the solver does not either.
    def solver_instances
      instances.each_with_index.map { |row, i| { instance: i + 1, display: figures.mark(student_view(with_passage(JSON.parse(row.display_json))), i + 1) } }
    end

    def bilingual? = body["bilingual"] == true

    # Form material is not translated (D-402): the item says `translate_material: false`. The student has no translation of the instance sentence, the options
    # or the rows, so the solver has none either; the instruction around them stays in both layers.
    def material_off? = Items::Text.material_off?(body)

    def student_view(display)
      display = display.except("passage_it") if bilingual?
      return display unless material_off?

      shown = display.key?("sub_items") ? display.merge("sub_items" => Array(display["sub_items"]).map { |s| s.is_a?(Hash) && s["display"].is_a?(Hash) ? s.merge("display" => untranslated(s["display"])) : s }) : display
      untranslated(shown)
    end

    def untranslated(display)
      out = display.except("stem_it")
      %w[options elements left right].each { |k| out[k] = Items::Text.shown_entries(out[k], body) if out[k] }
      out
    end

    # The figures of the instances read so far (call review_instances or solver_instances first), each as a PNG of the
    # drawing alone (D-320); [] when no instance shows one.
    def figure_files = figures.files

    def figures = @figures ||= Figures.new(revision.other_files)

    # What the student reads beyond the stored display: the item's own passage and
    # its prompt (stem, table, quote, figure; an ordering's direction lives there).
    # The stored display of older revisions does not hold them. An instance's own
    # stem stays under stem_it; the prompt's stem then goes under prompt_stem_it (D-169).
    # A bilingual item carries every text under its siblings (`stem_en` + `stem_it`, D-402); each is kept under its own name.
    def with_passage(display)
      return with_testlet_parts(display) if body["kind"] == "testlet"

      with_prompt(display, body)
    end

    # A testlet's passage once at the top, and each sub item's own prompt beside its display (D-184).
    def with_testlet_parts(display)
      subs = Array(display["sub_items"]).map do |shown|
        sub = Array(body["sub_items"]).find { |s| s["id"] == shown["id"] }
        sub && shown["display"].is_a?(Hash) ? shown.merge("display" => with_prompt(shown["display"], sub, passage: false)) : shown
      end
      extra = SIBLINGS.to_h { |s| [ "passage#{s}", body["passage#{s}"] ] }.select { |k, v| v.present? && !display.key?(k) }
      extra.merge(display).merge("sub_items" => subs)
    end

    def with_prompt(display, source, passage: true)
      extra = {}
      SIBLINGS.each { |s| extra["passage#{s}"] = source["passage#{s}"] if passage && source["passage#{s}"].present? }
      prompt = source["prompt"].is_a?(Hash) ? source["prompt"] : {}
      # An instance stem that is form material has no Italian (stem_en alone): the instruction's stem_it must not read as its translation.
      own_stem = SIBLINGS.any? { |s| display.key?("stem#{s}") }
      SIBLINGS.each do |s|
        key = "stem#{s}"
        extra[display.key?(key) || own_stem ? "prompt_#{key}" : key] = prompt[key] if prompt[key].present?
      end
      %w[table quote figure].each { |k| extra[k] = prompt[k] if prompt[k].present? && !display.key?(k) }
      # The supports the student reads with the item (D-216): the item's own, unless the instance has its own.
      SIBLINGS.flat_map { |s| [ "answer_format#{s}", "steps#{s}" ] }.each { |k| extra[k] = source[k] if source[k].present? && !display.key?(k) }
      extra.merge(display)
    end

    # Lines of the programme the reviewer should check the item against: those the
    # item's skill cites in its subject's graph plus those the item's own sources cite
    # (ref "SOURCE-KEY:LINE", D-178). cited_by says which side named the line:
    # "both", "skill" (graph only) or "item" (the item's sources only; role is nil).
    def programme_lines
      own = own_source_refs
      graph_refs = skill_refs
      keys = (graph_refs.map { |r| [ r["source"], r["line"].to_i ] } + own).uniq
      keys.filter_map do |source_key, number|
        source = SyllabusSource.find_by(key: source_key) or next
        line = SyllabusLine.find_by(syllabus_source: source, number: number) or next
        next unless line.citable?

        ref = graph_refs.find { |r| r["source"] == source_key && r["line"].to_i == number }
        cited_by = ref && own.include?([ source_key, number ]) ? "both" : (ref ? "skill" : "item")
        { source: source_key, line: number, role: ref && ref["role"], skill: ref && ref["skill"], cited_by: cited_by, text: line.text.chomp }
      end
    end

    # Every string a quote may come from, for finding at +instance+ (nil: the item as
    # a whole, which may quote any shown instance too).
    def strings(instance: nil)
      rows = instance ? [ instance_row(instance) ].compact : instances
      # A finding about one instance quotes the item's own text or that instance, not
      # another instance written in item.json.
      pool = instance ? leaves(body.except("instances")) : [ revision.body_json ] + leaves(body)
      rows.each do |row|
        %w[display_json answer_json errors_json solution_json accept_json hints_json].each do |col|
          next if row[col].blank?

          pool.concat(leaves(JSON.parse(row[col])))
        end
      end
      pool.concat(programme_lines.map { |l| l[:text] })
      pool
    end

    def quote?(quote, instance: nil)
      return false if quote.to_s.empty?

      strings(instance: instance).any? { |s| s.include?(quote) }
    end

    private

    def skill_refs
      graph = SkillGraphRevision.where(subject: revision.item.subject).order(:seq).last or return []
      skills = body["kind"] == "testlet" ? Array(body["sub_items"]).map { |s| s["skill"] } : [ body["skill"] ]
      JSON.parse(graph.body_json)["skills"].select { |s| skills.include?(s["key"]) }
          .flat_map { |s| s["refs"].to_a.map { |r| r.merge("skill" => s["key"]) } }
          .uniq { |r| [ r["source"], r["line"] ] }
    end

    # [source key, line number] pairs found in the item's (and its sub-items') sources.
    def own_source_refs
      sources = Array(body["sources"]) + Array(body["sub_items"]).flat_map { |s| Array(s["sources"]) }
      sources.flat_map { |s| s["ref"].to_s.scan(/([A-Za-z0-9][A-Za-z0-9_-]*):(\d+)/).map { |k, n| [ k, n.to_i ] } }.uniq
    end

    def leaves(node)
      case node
      when String then [ node ]
      when Hash then node.values.flat_map { |v| leaves(v) }
      when Array then node.flat_map { |v| leaves(v) }
      when Numeric then [ node.to_s ]
      else []
      end
    end
  end
end
