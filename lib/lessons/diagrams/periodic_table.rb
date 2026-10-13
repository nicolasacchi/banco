# frozen_string_literal: true

module Lessons
  module Diagrams
    # periodic_table (WAVE2 2.5, chemistry.md 2.9; T7): the first four periods or the main groups, from chem/elements. Tapping an element opens its card (name,
    # atomic number, group and period, where the symbol comes from). Below 600 px (or when a cell would be under its text) the table is a list by group with the
    # outline of the table beside each group. `highlight` marks up to four sets of elements (a marker shape, an outline style and a tint: never colour alone);
    # `mark_latin` marks the elements whose symbol comes from Latin. The full table is not built in wave 2. `symbol_name` writes the names of the highlighted
    # elements under the table and every name in the list view; `symbol_z` writes the atomic number in each cell.
    # The browser twin is app/javascript/lesson/diagrams/science/periodic_table.js; both run test/fixtures/diagrams/types/periodic_table.json.
    module PeriodicTable
      extend Contract

      NEUTRAL_DROPS = %w[show highlight mark_latin op_it].freeze
      LATIN_WORDS = "il simbolo viene dal latino"
      HINT = "Tocca un elemento per vedere la sua scheda."

      class << self
        def state(eff, c, path)
          range_symbols = ScienceSupport.range_elements(eff["range"]).map { |e| e["symbol"] }
          seen = {}
          (eff["highlight"] || []).each_with_index do |set, i|
            c.label("#{path}/highlight/#{i}/label_it", set["label_it"])
            set["symbols"].each_with_index do |sym, j|
              at = "#{path}/highlight/#{i}/symbols/#{j}"
              unless Chem.symbol?(sym)
                c.add("E-CHEM-SYMBOL", at, "#{sym} is not the symbol of an element (symbols are case-exact)", rule: "highlight-symbol#{at}")
                next
              end
              c.diagram(at, "#{sym} is not in #{eff['range']} (the table draws #{range_symbols.first} to #{range_symbols.last})", rule: "highlight-range#{at}") unless range_symbols.include?(sym)
              c.diagram(at, "#{sym} is in two highlight sets (a cell has one marker)", rule: "highlight-twice#{at}") if seen[sym]
              seen[sym] = true
            end
          end
        end

        # The figure as the student's page gets it. In :select mode what labels or marks a cell is dropped: no show, no highlight, no latin mark (L3).
        def served(data, mode: :student)
          out = Lessons::StudentBody.diagram_generic(data)
          return out unless mode == :select

          out = out.except(*NEUTRAL_DROPS)
          out["states"] = out["states"].map { |s| s.except(*NEUTRAL_DROPS) } if out["states"]
          out
        end

        # The stored ids of select set "cells": the symbols of the elements the table draws, in lower case (a target id starts with a lower-case letter or
        # digit), period by period, group by group: "na" is sodium, "co" is cobalt.
        def targets(data, set)
          set.to_s == "cells" ? ScienceSupport.range_elements(data["range"]).map { |e| e["symbol"].downcase } : []
        end

        def target_names(data, set)
          set.to_s == "cells" ? ScienceSupport.range_elements(data["range"]).to_h { |e| [ e["symbol"].downcase, "#{e['symbol']} (#{e['name_it']})" ] } : {}
        end

        # The card of an element, as the page opens it on a tap (L8: teaching content, served): number, group, period and where the symbol comes from.
        def card_text(e)
          origin = e["origin_it"] ? " Il simbolo #{e['symbol']} viene #{e['origin_it']}." : ""
          "Numero atomico #{e['z']}. Gruppo #{e['group']}, periodo #{e['period']}.#{origin}"
        end

        # Every string the state prints (L4), the tap cards included (L8): the symbols, the names, the atomic numbers, the group and period numbers, where a
        # symbol comes from, the highlight labels, the words of the legends. The browser's printed() returns the same set.
        def printed(data, state = 0)
          eff = Diagrams.effective_states(data)[state] || data
          rows = ScienceSupport.range_elements(eff["range"])
          out = rows.flat_map { |e| [ e["symbol"], e["name_it"], e["z"].to_s, e["latin"], e["origin_it"] ] }.compact
          out.concat(ScienceSupport.range_groups(eff["range"]).map(&:to_s))
          out.concat((1..rows.map { |e| e["period"] }.max).map(&:to_s))
          (eff["highlight"] || []).each { |set| out << set["label_it"] if set["label_it"] }
          out << LATIN_WORDS if eff["mark_latin"]
          out << "Gruppo" << "Periodo" << HINT
          op = data["states"] && data["states"][state] && data["states"][state]["op_it"]
          out << op if op
          out.uniq
        end
      end
    end
  end
end
