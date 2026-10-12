# frozen_string_literal: true

module Lessons
  module Diagrams
    # What the science family shares on the Ruby side (T7): the rows of chem/molecules, the pieces of a formula in reading order (the select targets
    # of `formula`) and the element table's rows. The browser twin is app/javascript/lesson/diagrams/science/common.js.
    module ScienceSupport
      MOLECULES = "chem/molecules"
      PATCH_ROWS = 2
      PATCH_UNITS = 2
      METAL_DISCS = 7

      module_function

      # The row of chem/molecules for a formula key (coefficient and state already removed), or nil.
      def molecule_row(key) = key && VettedData.row(MOLECULES, "molecules", key)

      # The row of the library for a formula as an author writes it ("3 H2O", "Ca(NO3)2(aq)"), or nil.
      def row_of_formula(formula) = molecule_row(Chem.base(formula))

      # The groups of atom indices joined by bonds, in order of their first atom: the ions of a salt, or the one piece of a molecule.
      def ion_groups(row)
        parent = (0...row["atoms"].size).to_a
        find = ->(i) { parent[i] == i ? i : (parent[i] = find.call(parent[i])) }
        row["bonds"].to_a.each { |a, b, _| parent[find.call(a)] = find.call(b) }
        (0...parent.size).group_by { |i| find.call(i) }.values
      end

      # How many discs a figure draws for a library row at a coefficient: the atoms of every molecule, or the discs of a patch (an ionic or metal row
      # is drawn as a small patch with the first units framed: the coefficient is the number of framed units, at most PATCH_UNITS).
      def drawn_count(row, coefficient)
        case row["kind"]
        when "metal" then METAL_DISCS
        when "ionic" then PATCH_ROWS * PATCH_UNITS * ion_groups(row).size
        else row["atoms"].size * coefficient
        end
      end

      # Whether a patch can frame this many units.
      def units_fit?(row, coefficient) = row["kind"] == "molecular" || coefficient <= PATCH_UNITS

      # How many discs a figure draws for a formula as an author writes it; nil outside the library.
      def atoms_drawn(formula)
        row = row_of_formula(formula) or return nil
        drawn_count(row, Chem.parse(formula)["coefficient"])
      end

      # The leaf pieces of a parsed formula in reading order: [{"kind" => "coefficient" | "symbol" | "subscript", "text" =>, "group" => bool}].
      # A subscript is a piece only when it is written (a 1 is not); a bracket group's subscript is the group's.
      def pieces(parsed)
        out = []
        out << { "kind" => "coefficient", "text" => parsed["coefficient"].to_s, "group" => false } if parsed["coefficient"] > 1
        parsed["groups"].each do |g|
          if g["group"]
            g["group"].each do |a|
              out << { "kind" => "symbol", "text" => a["symbol"], "group" => true }
              out << { "kind" => "subscript", "text" => a["count"].to_s, "group" => true } if a["count"] > 1
            end
            out << { "kind" => "subscript", "text" => g["count"].to_s, "group" => true, "of_group" => true }
          else
            out << { "kind" => "symbol", "text" => g["symbol"], "group" => false }
            out << { "kind" => "subscript", "text" => g["count"].to_s, "group" => false } if g["count"] > 1
          end
        end
        out
      end

      # The rows of the count table of a parsed formula, one per symbol in order of first appearance:
      # {"symbol", "terms" => [[unit_count, group_count], ...] (group_count nil outside brackets), "coefficient", "total"}.
      def count_rows(parsed)
        rows = {}
        parsed["groups"].each do |g|
          if g["group"]
            g["group"].each { |a| (rows[a["symbol"]] ||= []) << [ a["count"], g["count"] ] }
          else
            (rows[g["symbol"]] ||= []) << [ g["count"], nil ]
          end
        end
        k = parsed["coefficient"]
        rows.map do |symbol, terms|
          { "symbol" => symbol, "terms" => terms, "coefficient" => k, "total" => terms.sum { |u, grp| u * (grp || 1) } * k }
        end
      end
    end
  end
end
