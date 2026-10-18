# frozen_string_literal: true

module Lessons
  module Diagrams
    # cell (WAVE2 2.8, biology.md 2.1; T7, D-312): one or two cells (a bacterium, an animal cell, a plant cell) drawn by our code with fixed shapes, places
    # and colours. The parts each kind may have, their Italian names, jobs and colours are the vetted table bio/cell_parts: a part the kind does not have is
    # refused (a bacterium with a nucleus, an animal cell with a wall), every cell has the four shared parts (membrane, cytoplasm, DNA in a nucleoid or a
    # nucleus, ribosomes). `dna` is listed by no kind: highlight, paths and notes may name it, and it is drawn inside the nucleoid or the nucleus (in a
    # eukaryotic cell it gets a label of its own when the figure names it). Held back with a clear finding: the red blood cell (`kind: red_blood`,
    # `omit_shared`) and `true_scale` (it waits for the vetted sizes of bio/sizes). Select set `parts`: `c1.nucleoid`, in the table's order, cell by cell.
    # The browser twin is app/javascript/lesson/diagrams/science/cell.js; both run test/fixtures/diagrams/types/cell.json.
    module Cell
      extend Contract

      TABLE = "bio/cell_parts"
      SHARED = %w[membrane cytoplasm ribosomes].freeze
      HINT_ALL = "Tocca una parte per leggere che cosa fa."
      HINT_TAP = "Tocca una parte per leggere il suo nome e che cosa fa."
      # what a select check's figure never carries (L3): nothing that names, lights or notes a part, no states
      NEUTRAL_DROPS = %w[labels highlight paths fill notes states].freeze
      KIND_EN = { "bacterium" => "bacterium", "animal" => "animal cell", "plant" => "plant cell", "red_blood" => "red blood cell" }.freeze
      SPECIAL = {
        "bacterium:nucleus" => "a bacterium has no nucleus: its DNA lies in the cytoplasm (nucleoid)",
        "animal:wall" => "an animal cell has no wall: only the plant cell and the bacterium have one",
        "animal:chloroplasts" => "an animal cell has no chloroplasts: they are only in the plant cell",
        "animal:vacuole" => "an animal cell has no large central vacuole (its small sacs are the vesicles)",
        "animal:nucleoid" => "a eukaryotic cell keeps its DNA in the nucleus: list nucleus, not nucleoid",
        "plant:nucleoid" => "a eukaryotic cell keeps its DNA in the nucleus: list nucleus, not nucleoid",
        "animal:flagellum" => "the figure draws a typical animal cell: it has no flagellum",
        "plant:flagellum" => "the figure draws a typical plant cell: it has no flagellum"
      }.freeze

      class << self
        def table = VettedData.table(TABLE)

        def parts_table = table.fetch("parts")

        def kinds = table.fetch("kinds")

        # The canonical order of the parts (the table's): the order of the key, the targets and the descriptions.
        def order = parts_table.keys

        def name_of(part) = parts_table.dig(part, "name_it") || part

        def eukaryote?(kind) = kinds.fetch(kind, []).include?("nucleus")

        # Does the cell have the part (dna: always, in its nucleoid or its nucleus)?
        def has?(cell, part)
          parts = cell["parts"].to_a
          part == "dna" ? parts.include?("nucleoid") || parts.include?("nucleus") : parts.include?(part)
        end

        def in_any?(cells, part) = cells.any? { |c| has?(c, part) }

        def part_problem(kind, part)
          return "dna is not a part to list: a bacterium lists nucleoid, an animal or plant cell nucleus (highlight, paths and notes may name dna)" if part == "dna"
          return "#{part} is not a part the figure draws (#{(order - [ 'dna' ]).join(', ')})" unless parts_table.key?(part)
          return nil if kinds.fetch(kind).include?(part)
          return SPECIAL["#{kind}:#{part}"] if SPECIAL.key?("#{kind}:#{part}")
          return "a bacterium has no organelles closed by a membrane: it has no #{part}" if kind == "bacterium"

          "a #{KIND_EN[kind]} has no #{part} (it may show #{kinds.fetch(kind).join(', ')})"
        end

        # The first finding of the whole figure, in the order of the browser's semantic(): one finding, then stop.
        def static(data, c)
          cells = data["cells"]
          cells.each_with_index do |cell, i|
            at = "/cells/#{i}"
            return c.diagram("#{at}/kind", "the red blood cell is not drawn yet: it has no nucleus and no ribosomes, say it in a more block", rule: "red-blood#{at}") if cell["kind"] == "red_blood"
            return c.diagram("#{at}/omit_shared", "omit_shared is for the red blood cell, which is not drawn yet", rule: "omit#{at}") if cell.key?("omit_shared")

            cell["parts"].each_with_index do |part, j|
              bad = part_problem(cell["kind"], part)
              return c.diagram("#{at}/parts/#{j}", bad, rule: "part#{at}/#{j}") if bad
              return c.diagram("#{at}/parts/#{j}", "#{part} is listed twice", rule: "twice#{at}/#{j}") if cell["parts"].index(part) != j
            end
            missing = SHARED.reject { |p| cell["parts"].include?(p) } + (has?(cell, "dna") ? [] : [ cell["kind"] == "bacterium" ? "nucleoid" : "nucleus" ])
            return c.diagram("#{at}/parts", "every cell has a membrane, cytoplasm, DNA and ribosomes: add #{missing.join(', ')}", rule: "shared#{at}") if missing.any?

            before = c.findings.size
            c.label("#{at}/label_it", cell["label_it"])
            return if c.findings.size > before
          end
          return c.diagram("/true_scale", "true_scale waits for the vetted sizes of bio/sizes: draw the cells side by side without it", rule: "true-scale") if data["true_scale"] == true

          notes = data["notes"].to_a
          return c.diagram("/notes", "a note is read on a tap: with labels none nothing can be tapped", rule: "notes-none") if notes.any? && (data["labels"] || "all") == "none"

          notes.each_with_index do |note, k|
            part = note["part"]
            return c.diagram("/notes/#{k}/part", "#{part} is not a part of the figure's cells", rule: "note#{k}") unless in_any?(cells, part)
            return c.diagram("/notes/#{k}/part", "#{part} has two notes", rule: "note-twice#{k}") if notes.index { |n| n["part"] == part } != k
          end
          nil
        end

        # The first finding of one effective state.
        def state(eff, c, path)
          cells = eff["cells"]
          (eff["highlight"] || []).each_with_index do |part, j|
            return c.diagram("#{path}/highlight/#{j}", "#{part} is not a part of the figure's cells", rule: "highlight#{path}/#{j}") unless in_any?(cells, part)
          end
          (eff["paths"] || []).each_with_index do |p, j|
            at = "#{path}/paths/#{j}"
            return c.diagram("#{at}/from", "#{p['from']} is not a part of the figure's cells", rule: "from#{at}") unless in_any?(cells, p["from"])
            return c.diagram("#{at}/to", "#{p['to']} is not a part of the figure's cells", rule: "to#{at}") unless in_any?(cells, p["to"])
            return c.diagram("#{at}/to", "a path joins two different parts", rule: "same#{at}") if p["from"] == p["to"]
            return c.diagram(at, "no cell has both #{p['from']} and #{p['to']}", rule: "both#{at}") unless cells.any? { |cell| has?(cell, p["from"]) && has?(cell, p["to"]) }

            before = c.findings.size
            c.label("#{at}/label_it", p["label_it"])
            return if c.findings.size > before
          end
          (eff["fill"] || {}).each_key do |key|
            return c.diagram("#{path}/fill/#{key}", "only the vacuole has a fill level (low, mid, high)", rule: "fill#{path}/#{key}") if key != "vacuole"
            return c.diagram("#{path}/fill/#{key}", "no cell of the figure has a vacuole", rule: "fill-none#{path}") unless in_any?(cells, "vacuole")
            return c.diagram("#{path}/fill/#{key}", "a fill level is low, mid or high", rule: "fill-level#{path}") unless %w[low mid high].include?(eff["fill"][key])
          end
          nil
        end

        # Does the figure name the DNA of a eukaryotic cell (a highlight, a path or a note of any state)? Then its threads get a label of their own.
        def names_dna?(data)
          scopes = [ data ] + Array(data["states"])
          scopes.any? { |s| s["highlight"].to_a.include?("dna") || s["paths"].to_a.any? { |p| p["from"] == "dna" || p["to"] == "dna" } } ||
            data["notes"].to_a.any? { |n| n["part"] == "dna" }
        end

        # The parts of a cell that carry a label, in the canonical order (dna after the nucleus when the figure names it).
        def labelled_parts(cell, data)
          list = order.select { |p| cell["parts"].include?(p) }
          list.insert(list.index("nucleus") + 1, "dna") if eukaryote?(cell["kind"]) && names_dna?(data)
          list
        end

        # The author's note on a part (a note on dna is the note of a bacterium's nucleoid too), or nil.
        def note_of(data, cell, part)
          notes = data["notes"].to_a
          own = notes.find { |n| n["part"] == part }
          return own["text_it"] if own
          return notes.find { |n| n["part"] == "dna" }&.fetch("text_it") if part == "nucleoid" && cell["kind"] == "bacterium"

          nil
        end

        # The figure as the student's page gets it; a select check's figure has nothing that names, lights or notes a part (L3).
        def served(data, mode: :student)
          out = Lessons::StudentBody.diagram_generic(data)
          mode == :select ? out.except(*NEUTRAL_DROPS) : out
        end

        # Ids of set `parts` in reading order: the parts of the first cell in the table's order (c1.wall, c1.membrane...), then the second's.
        def targets(data, set)
          return [] unless set.to_s == "parts"

          data["cells"].each_with_index.flat_map { |cell, i| order.select { |p| cell["parts"].include?(p) }.map { |p| "c#{i + 1}.#{p}" } }
        end

        # The words that name a target: the part's name without its bracket ("DNA" for the nucleoid), what the alt text must not say (L3) and
        # what the teacher reads.
        def target_names(data, set)
          targets(data, set).to_h { |id| [ id, name_of(id.split(".", 2).last).sub(/\s*\(.*\)\z/, "") ] }
        end

        # The drawn style of each candidate of a select figure (L3): what the served neutral figure could still say of a part (lit, noted). The
        # projection drops all of it, so every candidate is drawn alike; a projection that kept one would show here.
        def select_signatures(data, set)
          figure = served(data, mode: :select)
          targets(data, set).to_h do |id|
            part = id.split(".", 2).last
            [ id, [ figure["highlight"].to_a.include?(part), figure["notes"].to_a.any? { |n| n["part"] == part }, figure["labels"] || "none" ] ]
          end
        end

        # Every string the state prints (L4). A tap reveals a part's name and its job or note (L8): with labels all or tap they count as printed.
        def printed(data, state = 0)
          eff = Diagrams.effective_states(data)[state] || data
          labels = eff["labels"] || "all"
          out = data["cells"].filter_map { |cell| cell["label_it"] }
          if labels != "none"
            data["cells"].each do |cell|
              labelled_parts(cell, data).each do |part|
                out << name_of(part)
                out << (note_of(data, cell, part) || parts_table.dig(part, "job_it"))
              end
            end
            out << (labels == "tap" ? HINT_TAP : HINT_ALL)
          end
          (eff["paths"] || []).each { |p| out << p["label_it"] if p["label_it"] }
          op = data["states"] && data["states"][state] && data["states"][state]["op_it"]
          out << op if op
          out.uniq
        end

        # "Solo le differenze" lights parts already named: nothing new is reachable.
        def reachable(_data) = []
      end
    end
  end
end
