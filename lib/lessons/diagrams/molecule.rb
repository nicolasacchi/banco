# frozen_string_literal: true

module Lessons
  module Diagrams
    # molecule (WAVE2 2.8, chemistry.md 2.5; T7): 2D molecules from chem/molecules. A coefficient draws copies ('2 O2' is two molecules). Honesty rule: an ionic
    # row (NaCl, Ca(OH)2) and a metal row (Fe, Co) have no molecules: they are drawn as a small patch with the first units framed and labelled "unità", never
    # "molecola". The atoms carry their symbol inside, a colour and a size, so colour is never the only cue; `angle` and `partial` come from the library only.
    # The browser twin is app/javascript/lesson/diagrams/science/molecule.js; the semantic checks run in the same order, so both give the same first finding for
    # the vectors of test/fixtures/diagrams/types/molecule.json.
    module Molecule
      extend Contract

      NEUTRAL_DROPS = %w[show style].freeze

      class << self
        def rule(key) = Validation::Rules.get(:lesson2, :types, :formula, key)

        def static(data, c)
          rows = []
          data["items"].each_with_index do |item, i|
            f = item["formula"]
            path = "/items/#{i}/formula"
            parsed = Chem.parse(f)
            unless parsed
              bad = Chem.unknown_symbol(f)
              if bad
                c.add("E-CHEM-SYMBOL", path, "#{bad} is not the symbol of an element (symbols are case-exact: Cl, not CL)", rule: "item#{i}")
              else
                c.diagram(path, "#{f.inspect} is not a formula the grammar reads (a coefficient 2 to 20, subscripts 2 to 99, one level of brackets, a state (s) (l) (g) (aq))", rule: "item#{i}")
              end
              next
            end
            row = ScienceSupport.row_of_formula(f)
            if row.nil?
              c.add("E-LESSON-DATA", path, "#{f.inspect} is not in chem/molecules: a molecule is drawn from the library only", rule: "item#{i}-library")
              next
            end
            rows << [ row, parsed["coefficient"] ]
            c.diagram(path, "a salt or a metal is drawn as a patch with at most #{ScienceSupport::PATCH_UNITS} units framed: #{f.inspect} has a coefficient above that", rule: "item#{i}-units") unless ScienceSupport.units_fit?(row, parsed["coefficient"])
            c.label("/items/#{i}/label_it", item["label_it"])
          end
          return unless rows.size == data["items"].size

          total = rows.sum { |row, k| ScienceSupport.drawn_count(row, k) }
          max = rule(:atoms_drawn)
          c.diagram("/items", "the figure would draw #{total} atoms (at most #{max})", rule: "atoms") if total > max
          show = data["show"] || %w[symbols]
          c.diagram("/show", "angle is drawn for a molecule of three atoms from the library (CO2, H2O, O3): no item has one", rule: "show-angle") if show.include?("angle") && rows.none? { |row, _| row["angle"] }
          c.diagram("/show", "partial charges are drawn from the library (H2O, CO2, H2O2, NH3): no item has them", rule: "show-partial") if show.include?("partial") && rows.none? { |row, _| row["partial_charges"] }
        end

        # The figure as the student's page gets it. In :select mode what labels or marks an atom is dropped: no show, no style, no caption (L3).
        def served(data, mode: :student)
          out = Lessons::StudentBody.diagram_generic(data)
          return out unless mode == :select

          out = out.except(*NEUTRAL_DROPS)
          out["items"] = out["items"].map { |it| it.except("label_it") }
          out
        end

        # Ids in reading order: "i2" (an item); atoms "i1c2a3" (item 1, copy 2, atom 3 of its row) or, for a patch, "i1x5" (the 5th disc of the patch).
        def targets(data, set)
          case set.to_s
          when "items" then data["items"].each_index.map { |i| "i#{i + 1}" }
          when "atoms"
            data["items"].each_with_index.flat_map do |item, i|
              parsed = Chem.parse(item["formula"])
              row = parsed && ScienceSupport.row_of_formula(item["formula"])
              next [] unless row

              if row["kind"] == "molecular"
                (1..parsed["coefficient"]).flat_map { |copy| row["atoms"].each_index.map { |a| "i#{i + 1}c#{copy}a#{a + 1}" } }
              else
                (1..ScienceSupport.drawn_count(row, 1)).map { |d| "i#{i + 1}x#{d}" }
              end
            end
          else []
          end
        end

        def target_names(data, set)
          data["items"].each_with_index.each_with_object({}) do |(item, i), out|
            parsed = Chem.parse(item["formula"])
            row = parsed && ScienceSupport.row_of_formula(item["formula"])
            next unless row

            out["i#{i + 1}"] = "#{item['formula']}" if set.to_s == "items"
            next unless set.to_s == "atoms"

            if row["kind"] == "molecular"
              (1..parsed["coefficient"]).each { |copy| row["atoms"].each_with_index { |a, k| out["i#{i + 1}c#{copy}a#{k + 1}"] = "atomo #{a['symbol']} di #{item['formula']}" } }
            else
              groups = ScienceSupport.ion_groups(row)
              discs = row["kind"] == "metal" ? Array.new(ScienceSupport::METAL_DISCS) { row["atoms"][0]["symbol"] } : ionic_sequence(row, groups)
              discs.each_with_index { |name, d| out["i#{i + 1}x#{d + 1}"] = "#{name} di #{item['formula']}" }
            end
          end
        end

        # The ions of the patch in drawing order (rows from the top, each row shifted one ion): their formulas as text.
        def ionic_sequence(row, groups)
          names = groups.map { |idx| ion_text(row, idx) }
          Array.new(ScienceSupport::PATCH_ROWS) { |ri| Array.new(names.size * ScienceSupport::PATCH_UNITS) { |k| names[(k + ri) % names.size] } }.flatten
        end

        # "OH", "NO3", "HCO3": the atoms of one ion, in the order the row lists them.
        def ion_text(row, indices)
          runs = []
          indices.each do |i|
            s = row["atoms"][i]["symbol"]
            runs.last && runs.last[0] == s ? runs.last[1] += 1 : runs << [ s, 1 ]
          end
          runs.map { |s, n| "#{s}#{n > 1 ? n : ''}" }.join
        end

        # Every string the figure prints (L4); the browser's printed() returns the same set.
        def printed(data, _state = 0)
          show = data["show"] || %w[symbols]
          out = []
          data["items"].each do |item|
            out << item["formula"]
            Chem.parse(item["formula"]) or next
            row = ScienceSupport.row_of_formula(item["formula"]) or next
            out << (item["label_it"] || row["name_it"])
            if row["kind"] == "molecular"
              row["atoms"].each { |a| out << a["symbol"] } if show.include?("symbols")
              out << angle_text(row["angle"]) if show.include?("angle") && row["angle"]
              if show.include?("partial") && row["partial_charges"]
                out << "δ+" if row["partial_charges"].any? { |v| Diagrams.num(v) > 0 }
                out << "δ−" if row["partial_charges"].any? { |v| Diagrams.num(v) < 0 }
              end
            else
              out << "unità"
              if row["kind"] == "metal"
                out << row["atoms"][0]["symbol"] if show.include?("symbols")
              else
                ScienceSupport.ion_groups(row).each { |idx| out << ion_text(row, idx) } if show.include?("symbols")
              end
            end
          end
          out.uniq
        end

        def angle_text(text) = "#{text.sub(/,0\z/, '')}°"
      end
    end
  end
end
