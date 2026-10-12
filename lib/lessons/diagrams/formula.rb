# frozen_string_literal: true

module Lessons
  module Diagrams
    # formula (WAVE2 2.8, chemistry.md 2.4; T7): the formula decoder. The formulas are read by Lessons::Chem (case-exact, one level of brackets); the
    # pieces, the labels, the arrows from a subscript back to its symbol, the count table and the molecules are ours: the author never writes a count.
    # `molecules` draws the library row of each formula (chem/molecules), so it is for library formulas only, and at most 30 atoms in all.
    # The browser twin is app/javascript/lesson/diagrams/science/formula.js; the semantic checks run in the same order, so both give the same first
    # finding for the vectors of test/fixtures/diagrams/types/formula.json.
    module Formula
      extend Contract

      SHOW = %w[parts count molecules].freeze
      WORDS = { "coefficient" => "coefficiente", "symbol" => "simbolo", "subscript" => "pedice", "group" => "pacchetto" }.freeze
      HINTS = { "coefficient" => "quante volte tutta la formula", "symbol" => "il tipo di atomo", "subscript" => "quanti atomi: conta quello prima", "group" => "si ripete tutto insieme" }.freeze
      NEUTRAL_DROPS = %w[show focus op_it].freeze

      class << self
        def rule(key) = Validation::Rules.get(:lesson2, :types, :formula, key)

        # The formulas are checked once, at the top (they are not a state key).
        def static(data, c)
          data["formulas"].each_with_index do |f, i|
            next if Chem.parse(f)

            bad = Chem.unknown_symbol(f)
            if bad
              c.add("E-CHEM-SYMBOL", "/formulas/#{i}", "#{bad} is not the symbol of an element (symbols are case-exact: Cl, not CL)", rule: "formulas/#{i}")
            else
              c.diagram("/formulas/#{i}", "#{f.inspect} is not a formula the grammar reads (a coefficient 2 to 20, subscripts 2 to 99, one level of brackets, a state (s) (l) (g) (aq))", rule: "formulas/#{i}")
            end
          end
        end

        def state(eff, c, path)
          return if eff["formulas"].any? { |f| Chem.parse(f).nil? } # the formulas were reported once, by static

          show = eff["show"] || %w[parts]
          if show.include?("molecules")
            eff["formulas"].each_with_index do |f, i|
              row = ScienceSupport.row_of_formula(f)
              if row.nil?
                c.add("E-LESSON-DATA", "#{path}/show", "molecules draws library formulas only: #{f.inspect} (formulas[#{i}]) is not in chem/molecules", rule: "molecules-library#{path}")
              elsif !ScienceSupport.units_fit?(row, Chem.parse(f)["coefficient"])
                c.diagram("#{path}/show", "a salt or a metal is drawn as a patch with at most #{ScienceSupport::PATCH_UNITS} units framed: #{f.inspect} has a coefficient above that", rule: "molecules-units#{path}")
              end
            end
            total = eff["formulas"].sum { |f| ScienceSupport.atoms_drawn(f) || 0 }
            max = rule(:atoms_drawn)
            c.diagram("#{path}/show", "molecules would draw #{total} atoms (at most #{max})", rule: "molecules-atoms#{path}") if total > max
          end
          return unless eff["focus"]

          unless Chem.symbol?(eff["focus"])
            c.add("E-CHEM-SYMBOL", "#{path}/focus", "#{eff['focus']} is not the symbol of an element", rule: "focus#{path}")
            return
          end
          present = eff["formulas"].any? { |f| Chem.count(f).key?(eff["focus"]) }
          c.diagram("#{path}/focus", "focus #{eff['focus']} is in none of the formulas", rule: "focus#{path}") unless present
        end

        # The figure as the student's page gets it. In :select mode everything that marks a candidate or labels a piece is dropped (L3).
        def served(data, mode: :student)
          out = Lessons::StudentBody.diagram_generic(data)
          return out unless mode == :select

          out = out.except(*NEUTRAL_DROPS)
          out["states"] = out["states"].map { |s| s.except(*NEUTRAL_DROPS) } if out["states"]
          out
        end

        # Ids "f1p3": formula 1, piece 3 in reading order. The same order as the browser's targets().
        def targets(data, set)
          return [] unless set.to_s == "pieces"

          data["formulas"].each_with_index.flat_map do |f, i|
            parsed = Chem.parse(f)
            parsed ? ScienceSupport.pieces(parsed).each_index.map { |k| "f#{i + 1}p#{k + 1}" } : []
          end
        end

        # What a teacher reads for a stored id: "pedice 2 (di H)".
        def target_names(data, set)
          return {} unless set.to_s == "pieces"

          names = { "coefficient" => "coefficiente", "symbol" => "simbolo", "subscript" => "pedice" }
          data["formulas"].each_with_index.each_with_object({}) do |(f, i), out|
            parsed = Chem.parse(f) or next
            last_symbol = nil
            ScienceSupport.pieces(parsed).each_with_index do |piece, k|
              last_symbol = piece["text"] if piece["kind"] == "symbol"
              label = "#{names[piece['kind']]} #{piece['text']}"
              label += piece["of_group"] ? " del pacchetto" : " (di #{last_symbol})" if piece["kind"] == "subscript"
              out["f#{i + 1}p#{k + 1}"] = "#{label} in #{f}"
            end
          end
        end

        # Every string the state prints (L4); the browser's printed() returns the same set.
        def printed(data, state = 0)
          eff = Diagrams.effective_states(data)[state] || data
          show = eff["show"] || %w[parts]
          out = []
          eff["formulas"].each do |f|
            out << f
            parsed = Chem.parse(f) or next
            if show.include?("parts")
              ScienceSupport.pieces(parsed).each { |p| out << p["text"] }
              pieces = ScienceSupport.pieces(parsed)
              kinds = %w[coefficient symbol subscript].select { |k| pieces.any? { |p| p["kind"] == k } }
              kinds << "group" if parsed["groups"].any? { |g| g["group"] }
              kinds.each { |k| out << WORDS[k] << HINTS[k] }
            end
            if show.include?("count")
              ScienceSupport.count_rows(parsed).each do |row|
                out << row["symbol"] << row["total"].to_s
                row["terms"].each { |u, g| out << u.to_s; out << g.to_s if g }
                out << row["coefficient"].to_s if row["coefficient"] > 1
              end
            end
            if show.include?("molecules")
              row = ScienceSupport.row_of_formula(f)
              out << row["name_it"] if row
            end
          end
          out << eff["focus"] if eff["focus"]
          op = data["states"] && data["states"][state] && data["states"][state]["op_it"]
          out << op if op
          out.uniq
        end
      end
    end
  end
end
